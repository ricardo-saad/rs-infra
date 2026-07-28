#!/usr/bin/env python3
"""Pull console-owned peer manifests over outbound mTLS and acknowledge apply."""

from __future__ import annotations

import http.client
import json
import os
import pathlib
import re
import ssl
import stat
import time
import urllib.parse
from typing import Mapping

from contract import ContractError, OPAQUE_ID_RE
from gateway_reconciler import (
    APPLIED_ROOT,
    DESIRED_ROOT,
    apply_manifest,
    atomic_persist,
    manifest_digest,
    read_manifest,
    validate_manifest,
)

CONSOLE_INTERFACES = ("wg-users", "wg-nodes")
DELIVERY_FIELDS = {
    "schema_version",
    "gateway_id",
    "delivery_id",
    "manifest_digest",
    "manifest",
}
CONFIG_FIELDS = {
    "CONTROL_PLANE_GATEWAY_ID",
    "CONTROL_PLANE_DESIRED_URL",
    "CONTROL_PLANE_ACK_URL",
    "CONTROL_PLANE_CA_FILE",
    "CONTROL_PLANE_CLIENT_CERT_FILE",
    "CONTROL_PLANE_CLIENT_KEY_FILE",
    "CONTROL_PLANE_POLL_SECONDS",
}
DIGEST_RE = re.compile(r"^[a-f0-9]{64}$")
MAXIMUM_RESPONSE_BYTES = 1024 * 1024


def required_configuration(environment: Mapping[str, str]) -> dict[str, str]:
    config = {}
    for name in CONFIG_FIELDS:
        value = environment.get(name, "")
        if not value or any(character in value for character in "\r\n\0"):
            raise ContractError(f"missing or invalid control-plane identifier: {name}")
        config[name] = value

    gateway_id = config["CONTROL_PLANE_GATEWAY_ID"]
    if not OPAQUE_ID_RE.fullmatch(gateway_id):
        raise ContractError("control-plane gateway ID is invalid")

    desired = validate_https_url(config["CONTROL_PLANE_DESIRED_URL"])
    acknowledgement = validate_https_url(config["CONTROL_PLANE_ACK_URL"])
    if (desired.hostname, desired.port or 443) != (
        acknowledgement.hostname,
        acknowledgement.port or 443,
    ):
        raise ContractError("control-plane URLs must have the same origin")

    try:
        poll_seconds = int(config["CONTROL_PLANE_POLL_SECONDS"])
    except ValueError as error:
        raise ContractError("control-plane poll interval is invalid") from error
    if not 5 <= poll_seconds <= 300:
        raise ContractError("control-plane poll interval is invalid")

    for name in (
        "CONTROL_PLANE_CA_FILE",
        "CONTROL_PLANE_CLIENT_CERT_FILE",
        "CONTROL_PLANE_CLIENT_KEY_FILE",
    ):
        path = pathlib.Path(config[name])
        if not path.is_absolute():
            raise ContractError(f"{name} must be an absolute path")
    validate_private_key_file(pathlib.Path(config["CONTROL_PLANE_CLIENT_KEY_FILE"]))
    return config


def validate_https_url(value: str) -> urllib.parse.SplitResult:
    parsed = urllib.parse.urlsplit(value)
    try:
        port = parsed.port
    except ValueError as error:
        raise ContractError("control-plane URL is invalid") from error
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.fragment
        or parsed.query
        or not parsed.path.startswith("/")
        or port == 0
    ):
        raise ContractError("control-plane URL must be an exact HTTPS endpoint")
    return parsed


def validate_private_key_file(path: pathlib.Path) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ContractError("control-plane client key is unavailable") from error
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_mode & 0o077:
        raise ContractError("control-plane client key must be a private regular file")


def tls_context(config: Mapping[str, str]) -> ssl.SSLContext:
    context = ssl.create_default_context(
        purpose=ssl.Purpose.SERVER_AUTH,
        cafile=config["CONTROL_PLANE_CA_FILE"],
    )
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.check_hostname = True
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_cert_chain(
        certfile=config["CONTROL_PLANE_CLIENT_CERT_FILE"],
        keyfile=config["CONTROL_PLANE_CLIENT_KEY_FILE"],
    )
    return context


def canonical_json(document: object) -> bytes:
    return json.dumps(
        document,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode("utf-8")


def post_json(
    url: str,
    document: object,
    context: ssl.SSLContext,
    *,
    timeout: int = 30,
) -> tuple[int, bytes]:
    parsed = validate_https_url(url)
    body = canonical_json(document)
    connection = http.client.HTTPSConnection(
        parsed.hostname,
        parsed.port or 443,
        context=context,
        timeout=timeout,
    )
    try:
        connection.request(
            "POST",
            parsed.path,
            body=body,
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
        )
        response = connection.getresponse()
        content_length = response.getheader("Content-Length")
        if content_length is not None:
            try:
                declared_length = int(content_length)
            except ValueError as error:
                raise RuntimeError("control-plane response length is invalid") from error
            if declared_length < 0 or declared_length > MAXIMUM_RESPONSE_BYTES:
                raise RuntimeError("control-plane response is excessive")
        response_body = response.read(MAXIMUM_RESPONSE_BYTES + 1)
        if len(response_body) > MAXIMUM_RESPONSE_BYTES:
            raise RuntimeError("control-plane response is excessive")
        return response.status, response_body
    finally:
        connection.close()


def applied_state(gateway_id: str) -> dict:
    applied = []
    for interface_name in CONSOLE_INTERFACES:
        path = APPLIED_ROOT / f"{interface_name}.json"
        if not path.exists():
            continue
        current = read_manifest(path, interface_name)
        applied.append(
            {
                "interface": interface_name,
                "generation": current["generation"],
                "manifest_digest": manifest_digest(current),
            }
        )
    return {
        "schema_version": 1,
        "gateway_id": gateway_id,
        "applied": applied,
    }


def validate_delivery(document: object, gateway_id: str) -> tuple[dict, dict]:
    if not isinstance(document, dict) or set(document) != DELIVERY_FIELDS:
        raise ContractError("delivery has unknown or missing fields")
    if document["schema_version"] != 1:
        raise ContractError("delivery schema version is unsupported")
    if document["gateway_id"] != gateway_id:
        raise ContractError("delivery is intended for another gateway")
    delivery_id = document["delivery_id"]
    if not isinstance(delivery_id, str) or not OPAQUE_ID_RE.fullmatch(delivery_id):
        raise ContractError("delivery ID is invalid")
    supplied_digest = document["manifest_digest"]
    if not isinstance(supplied_digest, str) or not DIGEST_RE.fullmatch(supplied_digest):
        raise ContractError("delivery manifest digest is invalid")
    manifest = document["manifest"]
    if not isinstance(manifest, dict) or manifest.get("interface") not in CONSOLE_INTERFACES:
        raise ContractError("delivery exceeds console interface authority")
    validated = validate_manifest(manifest, manifest["interface"])
    if manifest_digest(validated) != supplied_digest:
        raise ContractError("delivery manifest digest does not match its payload")
    return document, validated


def acknowledgement(delivery: Mapping[str, object], result: Mapping[str, object]) -> dict:
    return {
        "schema_version": 1,
        "gateway_id": delivery["gateway_id"],
        "delivery_id": delivery["delivery_id"],
        "interface": result["interface"],
        "generation": result["generation"],
        "manifest_digest": result["manifest_digest"],
        "outcome": "applied",
    }


def deliver(document: object, gateway_id: str) -> dict:
    delivery, manifest = validate_delivery(document, gateway_id)
    destination = DESIRED_ROOT / f"{manifest['interface']}.json"
    atomic_persist(destination, manifest)
    result = apply_manifest(manifest)
    if result["manifest_digest"] != delivery["manifest_digest"]:
        raise RuntimeError("applied manifest digest did not match the delivery")
    return acknowledgement(delivery, result)


def cycle(config: Mapping[str, str], context: ssl.SSLContext) -> None:
    gateway_id = config["CONTROL_PLANE_GATEWAY_ID"]
    status, body = post_json(
        config["CONTROL_PLANE_DESIRED_URL"],
        applied_state(gateway_id),
        context,
    )
    if status == 204:
        if body:
            raise RuntimeError("empty control-plane response carried a body")
        return
    if status != 200:
        raise RuntimeError("control-plane desired-state request failed")
    try:
        delivery = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ContractError("control-plane delivery is invalid JSON") from error
    applied = deliver(delivery, gateway_id)
    ack_status, ack_body = post_json(
        config["CONTROL_PLANE_ACK_URL"],
        applied,
        context,
    )
    if ack_status not in {200, 204} or ack_body:
        raise RuntimeError("control-plane acknowledgement failed")


def main() -> None:
    config = required_configuration(os.environ)
    context = tls_context(config)
    interval = int(config["CONTROL_PLANE_POLL_SECONDS"])
    while True:
        cycle(config, context)
        time.sleep(interval)


if __name__ == "__main__":
    main()
