#!/usr/bin/env python3
"""Fail-closed AWS secret loader for the steady-state gateway role."""

from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import tempfile
from typing import Mapping

from contract import BCRYPT_RE, ContractError, INTERFACES, validate_wireguard_key

RUNTIME_ROOT = pathlib.Path("/run/rs-gateway")
ALLOWED_ENV = {
    "AWS_REGION",
    "WIREGUARD_SECRET_ID",
    "ADGUARD_SECRET_ID",
    "PUBLIC_KEY_PARAMETER_PREFIX",
    "CLOUDWATCH_NAMESPACE",
    "WAN_INTERFACE",
    "BUILD_VERSION",
}


def required_environment(environment: Mapping[str, str]) -> dict[str, str]:
    result = {}
    for name in ALLOWED_ENV:
        value = environment.get(name, "")
        if not value or any(character in value for character in "\r\n\0"):
            raise ContractError(f"missing or invalid runtime identifier: {name}")
        result[name] = value
    if result["AWS_REGION"] != "eu-west-2":
        raise ContractError("gateway region must be eu-west-2")
    if not result["PUBLIC_KEY_PARAMETER_PREFIX"].startswith("/"):
        raise ContractError("public-key parameter prefix must be absolute")
    if not re.fullmatch(r"[A-Za-z0-9/_.-]{1,128}", result["CLOUDWATCH_NAMESPACE"]):
        raise ContractError("CloudWatch namespace is invalid")
    return result


def run(command: list[str], *, stdin: str | None = None) -> str:
    completed = subprocess.run(
        command,
        input=stdin,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode:
        # Never include captured output: AWS errors can echo request context.
        raise RuntimeError(f"command failed: {command[0]} {command[1]}")
    return completed.stdout


def retrieve_current(secret_id: str, region: str) -> tuple[dict, str]:
    raw = run(
        [
            "aws",
            "secretsmanager",
            "get-secret-value",
            "--region",
            region,
            "--secret-id",
            secret_id,
            "--version-stage",
            "AWSCURRENT",
            "--query",
            "{SecretString:SecretString,VersionId:VersionId}",
            "--output",
            "json",
        ]
    )
    try:
        envelope = json.loads(raw)
        value = json.loads(envelope["SecretString"])
        version_id = envelope["VersionId"]
    except (KeyError, TypeError, json.JSONDecodeError) as error:
        raise ContractError("secret response has an invalid shape") from error
    if not isinstance(value, dict) or not isinstance(version_id, str) or not version_id:
        raise ContractError("secret response has an invalid shape")
    return value, version_id


def validate_wireguard_secret(value: object) -> dict[str, str]:
    if not isinstance(value, dict) or set(value) != set(INTERFACES):
        raise ContractError("WireGuard secret must contain exactly three interfaces")
    return {name: validate_wireguard_key(value[name]) for name in INTERFACES}


def validate_adguard_secret(value: object) -> dict[str, str]:
    if not isinstance(value, dict) or set(value) != {"username", "password"}:
        raise ContractError("AdGuard secret has unknown or missing fields")
    username = value["username"]
    password = value["password"]
    if (
        not isinstance(username, str)
        or not username
        or len(username) > 64
        or any(character in username for character in "\r\n\0:")
    ):
        raise ContractError("AdGuard username is invalid")
    if (
        not isinstance(password, str)
        or not 32 <= len(password) <= 128
        or any(character in password for character in "\r\n\0")
    ):
        raise ContractError("AdGuard password is invalid")
    return {"username": username, "password": password}


def hash_adguard_credentials(credentials: Mapping[str, str]) -> dict[str, str]:
    output = run(
        ["htpasswd", "-niBC", "12", credentials["username"]],
        stdin=credentials["password"] + "\n",
    ).strip()
    try:
        _, password_hash = output.split(":", 1)
    except ValueError as error:
        raise RuntimeError("credential hashing failed") from error
    if not BCRYPT_RE.fullmatch(password_hash):
        raise RuntimeError("credential hashing returned an invalid hash")
    return {
        "username": credentials["username"],
        "password_hash": password_hash,
    }


def atomic_write(path: pathlib.Path, content: str, mode: int = 0o600) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(dir=path.parent)
    try:
        os.fchmod(file_descriptor, mode)
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def wireguard_configuration(interface_name: str, private_key: str) -> str:
    interface = INTERFACES[interface_name]
    return (
        "[Interface]\n"
        f"PrivateKey = {private_key}\n"
        f"ListenPort = {interface.port}\n"
        f"Address = {interface.gateway}/{interface.subnet.prefixlen}\n"
    )


def read_adguard_build_config(
    path: pathlib.Path = pathlib.Path("/etc/rs-gateway/adguard-build.json"),
) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError("AdGuard build configuration is invalid") from error
    if not isinstance(value, dict) or set(value) != {
        "schema_version",
        "upstream_dns",
        "filter_name",
        "filter_url",
    }:
        raise ContractError("AdGuard build configuration is invalid")
    if (
        not isinstance(value["schema_version"], int)
        or isinstance(value["schema_version"], bool)
        or value["schema_version"] < 1
    ):
        raise ContractError("AdGuard schema version is invalid")
    for field in ("upstream_dns", "filter_url"):
        if (
            not isinstance(value[field], str)
            or not value[field].startswith("https://")
            or any(character in value[field] for character in "\r\n\0\"")
        ):
            raise ContractError(f"AdGuard {field} is invalid")
    if (
        not isinstance(value["filter_name"], str)
        or not re.fullmatch(r"[A-Za-z0-9 _.-]{1,80}", value["filter_name"])
    ):
        raise ContractError("AdGuard filter name is invalid")
    return value


def adguard_configuration(credentials: Mapping[str, str], build: Mapping[str, object]) -> str:
    # JSON string encoding is also valid YAML scalar encoding.
    username = json.dumps(credentials["username"])
    password_hash = json.dumps(credentials["password_hash"])
    bind_hosts = "\n".join(
        f"    - {interface.gateway}" for interface in INTERFACES.values()
    )
    return f"""http:
  address: 10.100.2.1:3000
users:
  - name: {username}
    password: {password_hash}
auth_attempts: 5
block_auth_min: 15
dns:
  bind_hosts:
    - 127.0.0.1
{bind_hosts}
  port: 53
  protection_enabled: true
  ratelimit: 20
  querylog_enabled: true
  querylog_file_enabled: true
  querylog_interval: 24h
  querylog_size_memory: 1000
  anonymize_client_ip: true
  cache_size: 4194304
  upstream_dns:
    - {json.dumps(build["upstream_dns"])}
filtering:
  filtering_enabled: true
  parental_enabled: false
  safebrowsing_enabled: false
  safesearch_enabled: false
  rewrites: []
filters:
  - enabled: true
    url: {json.dumps(build["filter_url"])}
    name: {json.dumps(build["filter_name"])}
    id: 1
schema_version: {build["schema_version"]}
"""


def publish_public_keys(keys: Mapping[str, str], config: Mapping[str, str]) -> None:
    prefix = config["PUBLIC_KEY_PARAMETER_PREFIX"].rstrip("/")
    for interface_name, private_key in keys.items():
        public_key = run(["wg", "pubkey"], stdin=private_key)
        validate_wireguard_key(public_key.strip())
        run(
            [
                "aws",
                "ssm",
                "put-parameter",
                "--region",
                config["AWS_REGION"],
                "--name",
                f"{prefix}/{interface_name}",
                "--type",
                "String",
                "--value",
                public_key.strip(),
                "--overwrite",
            ]
        )


def publish_metric_safely(config: Mapping[str, str], metric_name: str) -> None:
    try:
        run(
            [
                "aws",
                "cloudwatch",
                "put-metric-data",
                "--region",
                config["AWS_REGION"],
                "--namespace",
                config["CLOUDWATCH_NAMESPACE"],
                "--metric-name",
                metric_name,
                "--value",
                "1",
                "--unit",
                "Count",
            ]
        )
    except Exception:
        # Telemetry cannot turn a specific failure into a different failure.
        pass


def main() -> None:
    config = required_environment(os.environ)
    try:
        wireguard_raw, wireguard_version = retrieve_current(
            config["WIREGUARD_SECRET_ID"], config["AWS_REGION"]
        )
        adguard_raw, adguard_version = retrieve_current(
            config["ADGUARD_SECRET_ID"], config["AWS_REGION"]
        )
        keys = validate_wireguard_secret(wireguard_raw)
        credentials = validate_adguard_secret(adguard_raw)

        for interface_name, private_key in keys.items():
            atomic_write(
                RUNTIME_ROOT / "wireguard" / f"{interface_name}.conf",
                wireguard_configuration(interface_name, private_key),
            )
        atomic_write(
            RUNTIME_ROOT / "adguard" / "AdGuardHome.yaml",
            adguard_configuration(
                hash_adguard_credentials(credentials),
                read_adguard_build_config(),
            ),
        )
        atomic_write(
            RUNTIME_ROOT / "loaded-versions.json",
            json.dumps(
                {
                    "wireguard_version_id": wireguard_version,
                    "adguard_version_id": adguard_version,
                    "build_version": config["BUILD_VERSION"],
                },
                sort_keys=True,
            )
            + "\n",
            mode=0o644,
        )
    except Exception:
        publish_metric_safely(config, "SecretLoadFailure")
        raise
    try:
        publish_public_keys(keys, config)
    except Exception:
        publish_metric_safely(config, "PublicKeyPublicationFailure")
        raise


if __name__ == "__main__":
    main()
