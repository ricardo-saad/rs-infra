#!/usr/bin/env python3
"""One-time gateway identity bootstrap; never used by the runtime role."""

from __future__ import annotations

import base64
import json
import os
import secrets
import string

from contract import INTERFACES, ContractError, validate_wireguard_key
from secret_loader import publish_public_keys, required_environment, run


def has_current_version(secret_id: str, region: str) -> bool:
    raw = run(
        [
            "aws",
            "secretsmanager",
            "describe-secret",
            "--region",
            region,
            "--secret-id",
            secret_id,
            "--query",
            "VersionIdsToStages",
            "--output",
            "json",
        ]
    )
    try:
        versions = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ContractError("secret metadata response is invalid") from error
    if not isinstance(versions, dict):
        raise ContractError("secret metadata response is invalid")
    return any(
        isinstance(stages, list) and "AWSCURRENT" in stages
        for stages in versions.values()
    )


def generate_wireguard_keys() -> dict[str, str]:
    keys = {}
    for interface_name in INTERFACES:
        key = run(["wg", "genkey"]).strip()
        keys[interface_name] = validate_wireguard_key(key)
    return keys


def generate_adguard_credentials() -> dict[str, str]:
    alphabet = string.ascii_letters + string.digits + "-_"
    password = "".join(secrets.choice(alphabet) for _ in range(40))
    return {"username": "admin", "password": password}


def put_first_version(secret_id: str, region: str, value: dict) -> None:
    token = base64.urlsafe_b64encode(os.urandom(24)).decode("ascii").rstrip("=")
    run(
        [
            "aws",
            "secretsmanager",
            "put-secret-value",
            "--region",
            region,
            "--secret-id",
            secret_id,
            "--client-request-token",
            token,
            "--secret-string",
            "file:///dev/stdin",
        ],
        stdin=json.dumps(value, separators=(",", ":")),
    )


def main() -> None:
    config = required_environment(os.environ)
    secret_ids = [
        config["WIREGUARD_SECRET_ID"],
        config["ADGUARD_SECRET_ID"],
    ]
    if any(has_current_version(secret_id, config["AWS_REGION"]) for secret_id in secret_ids):
        raise RuntimeError("bootstrap refused because AWSCURRENT already exists")

    keys = generate_wireguard_keys()
    credentials = generate_adguard_credentials()
    put_first_version(config["WIREGUARD_SECRET_ID"], config["AWS_REGION"], keys)
    put_first_version(config["ADGUARD_SECRET_ID"], config["AWS_REGION"], credentials)
    publish_public_keys(keys, config)
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
            "BootstrapComplete",
            "--value",
            "1",
            "--unit",
            "Count",
        ]
    )


if __name__ == "__main__":
    main()
