#!/usr/bin/env python3
"""Validate and transactionally apply one complete interface manifest."""

from __future__ import annotations

import argparse
import datetime
import fcntl
import hashlib
import ipaddress
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
from typing import Iterable

from contract import (
    ContractError,
    INTERFACES,
    OPAQUE_ID_RE,
    validate_peer_address,
    validate_wireguard_key,
)

DESIRED_ROOT = pathlib.Path("/var/lib/rs-gateway/desired")
APPLIED_ROOT = pathlib.Path("/var/lib/rs-gateway/applied")
RUNTIME_ROOT = pathlib.Path("/run/rs-gateway")
MANIFEST_FIELDS = {
    "schema_version",
    "interface",
    "generation",
    "generated_at",
    "peers",
}
PEER_FIELDS = {
    "peer_id",
    "public_key",
    "address",
    "health_policy",
}
USER_PEER_FIELDS = PEER_FIELDS | {"permissions"}
HEALTH_POLICIES = {"required", "on_demand"}


def canonical_manifest(manifest: dict) -> bytes:
    """Return the stable bytes used by delivery and acknowledgement digests."""
    return json.dumps(
        manifest,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode("utf-8")


def manifest_digest(manifest: dict) -> str:
    return hashlib.sha256(canonical_manifest(manifest)).hexdigest()


def run(command: list[str], *, stdin: str | None = None, check: bool = True) -> str:
    completed = subprocess.run(
        command,
        input=stdin,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if check and completed.returncode:
        raise RuntimeError(f"command failed: {command[0]} {command[1]}")
    return completed.stdout


def parse_timestamp(value: object) -> str:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ContractError("generated_at must be an RFC3339 UTC timestamp")
    try:
        datetime.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise ContractError("generated_at must be an RFC3339 UTC timestamp") from error
    return value


def validate_manifest(document: object, expected_interface: str) -> dict:
    if expected_interface not in INTERFACES:
        raise ContractError("unknown expected interface")
    if not isinstance(document, dict) or set(document) != MANIFEST_FIELDS:
        raise ContractError("manifest has unknown or missing fields")
    if document["schema_version"] != 1:
        raise ContractError("unsupported schema version")
    if document["interface"] != expected_interface:
        raise ContractError("manifest interface does not match its destination")
    generation = document["generation"]
    if not isinstance(generation, int) or isinstance(generation, bool) or generation < 1:
        raise ContractError("generation must be a positive integer")
    parse_timestamp(document["generated_at"])
    peers = document["peers"]
    interface = INTERFACES[expected_interface]
    if not isinstance(peers, list) or len(peers) > interface.peer_limit:
        raise ContractError("invalid or excessive peer count")

    public_keys: set[str] = set()
    addresses: set[str] = set()
    peer_ids: set[str] = set()
    validated_peers = []
    for peer in peers:
        allowed_fields = USER_PEER_FIELDS if expected_interface == "wg-users" else PEER_FIELDS
        if not isinstance(peer, dict) or set(peer) != allowed_fields:
            raise ContractError("peer has unknown or missing fields")
        peer_id = peer["peer_id"]
        if not isinstance(peer_id, str) or not OPAQUE_ID_RE.fullmatch(peer_id):
            raise ContractError("peer_id is invalid")
        public_key = validate_wireguard_key(peer["public_key"])
        address = validate_peer_address(peer["address"], interface)
        health_policy = peer["health_policy"]
        if health_policy not in HEALTH_POLICIES:
            raise ContractError("unsupported health policy")
        if peer_id in peer_ids or public_key in public_keys or address in addresses:
            raise ContractError("duplicate peer ID, key, or address")
        peer_ids.add(peer_id)
        public_keys.add(public_key)
        addresses.add(address)

        validated = {
            "peer_id": peer_id,
            "public_key": public_key,
            "address": address,
            "health_policy": health_policy,
        }
        if expected_interface == "wg-users":
            permissions = peer["permissions"]
            if (
                not isinstance(permissions, list)
                or len(permissions) != len(set(permissions))
                or set(permissions) not in ({"egress"}, {"egress", "games"})
            ):
                raise ContractError("user permissions must be egress with optional games")
            validated["permissions"] = permissions
        validated_peers.append(validated)
    return {**document, "peers": validated_peers}


def read_manifest(path: pathlib.Path, expected_interface: str) -> dict:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError("manifest is unreadable or invalid JSON") from error
    return validate_manifest(document, expected_interface)


def current_generation(interface_name: str) -> int:
    path = APPLIED_ROOT / f"{interface_name}.json"
    if not path.exists():
        return 0
    return read_manifest(path, interface_name)["generation"]


def require_generation(
    candidate: int,
    current: int,
    *,
    candidate_digest: str | None = None,
    current_digest: str | None = None,
    restore: bool = False,
) -> None:
    if candidate < current:
        raise ContractError("generation is stale")
    if candidate == current and not restore:
        if (
            candidate_digest is None
            or current_digest is None
            or candidate_digest != current_digest
        ):
            raise ContractError("generation conflicts with the applied manifest")


def game_target_for(manifest: dict) -> dict | None:
    if not any("games" in peer.get("permissions", []) for peer in manifest["peers"]):
        return None
    path = pathlib.Path("/etc/rs-gateway/game-target.json")
    try:
        target = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError("games permission has no reviewed target") from error
    if not isinstance(target, dict) or set(target) != {
        "schema_version",
        "destination",
        "protocol",
        "port",
    }:
        raise ContractError("game target has unknown or missing fields")
    if target["schema_version"] != 1 or target["protocol"] not in {"tcp", "udp"}:
        raise ContractError("game target version or protocol is invalid")
    try:
        destination = ipaddress.ip_network(target["destination"])
    except (TypeError, ValueError) as error:
        raise ContractError("game target destination is invalid") from error
    if not isinstance(destination, ipaddress.IPv4Network) or destination.prefixlen != 32:
        raise ContractError("game target must be an IPv4 /32")
    if (
        not isinstance(target["port"], int)
        or isinstance(target["port"], bool)
        or not 1 <= target["port"] <= 65535
    ):
        raise ContractError("game target port is invalid")
    return target


def sync_configuration(manifest: dict) -> str:
    interface_name = manifest["interface"]
    baseline = run(
        [
            "wg-quick",
            "strip",
            str(RUNTIME_ROOT / "wireguard" / f"{interface_name}.conf"),
        ]
    ).rstrip()
    sections = [baseline]
    for peer in manifest["peers"]:
        sections.append(
            "\n".join(
                [
                    "[Peer]",
                    f"PublicKey = {peer['public_key']}",
                    f"AllowedIPs = {peer['address']}",
                ]
            )
        )
    return "\n\n".join(sections) + "\n"


def user_policy(manifest: dict, game_target: dict | None) -> str:
    lines = ["flush chain inet rs_gateway users_authorize"]
    if game_target is not None:
        for peer in manifest["peers"]:
            if "games" in peer["permissions"]:
                source = peer["address"].removesuffix("/32")
                destination = game_target["destination"].removesuffix("/32")
                lines.append(
                    "add rule inet rs_gateway users_authorize "
                    f"ip saddr {source} ip daddr {destination} "
                    f"{game_target['protocol']} dport {game_target['port']} accept"
                )
    lines.append("")
    return "\n".join(lines)


def atomic_persist(path: pathlib.Path, manifest: dict) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def apply_routes(interface_name: str, old: Iterable[str], new: Iterable[str]) -> None:
    new_set = set(new)
    old_set = set(old)
    for address in old_set - new_set:
        run(["ip", "route", "del", address, "dev", interface_name], check=False)
    for address in new_set:
        run(["ip", "route", "replace", address, "dev", interface_name])


def expected_user_rules(manifest: dict, game_target: dict | None) -> set[str]:
    prefix = "add rule inet rs_gateway users_authorize "
    return {
        line.removeprefix(prefix)
        for line in user_policy(manifest, game_target).splitlines()
        if line.startswith(prefix)
    }


def live_user_rules() -> set[str]:
    output = run(
        ["nft", "-a", "list", "chain", "inet", "rs_gateway", "users_authorize"]
    )
    return {
        " ".join(line.split(" # handle", 1)[0].split())
        for line in output.splitlines()
        if " # handle " in line
    }


def verify(manifest: dict, game_target: dict | None = None) -> None:
    interface_name = manifest["interface"]
    actual_peers = set(run(["wg", "show", interface_name, "peers"]).split())
    expected_peers = {peer["public_key"] for peer in manifest["peers"]}
    if actual_peers != expected_peers:
        raise RuntimeError("live WireGuard peers did not match the candidate")
    try:
        route_records = json.loads(
            run(["ip", "-json", "route", "show", "dev", interface_name])
        )
    except (TypeError, json.JSONDecodeError) as error:
        raise RuntimeError("live peer routes were unreadable") from error
    if not isinstance(route_records, list):
        raise RuntimeError("live peer routes were unreadable")
    actual_routes = {
        record.get("dst")
        for record in route_records
        if isinstance(record, dict)
        and isinstance(record.get("dst"), str)
        and record["dst"].endswith("/32")
    }
    expected_routes = {peer["address"] for peer in manifest["peers"]}
    if actual_routes != expected_routes:
        raise RuntimeError("live peer routes did not match the candidate")
    if (
        interface_name == "wg-users"
        and live_user_rules() != expected_user_rules(manifest, game_target)
    ):
        raise RuntimeError("live user authorization did not match the candidate")


def apply_manifest(manifest: dict, *, restore: bool = False) -> dict:
    interface_name = manifest["interface"]
    APPLIED_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_path = RUNTIME_ROOT / "locks" / f"{interface_name}.lock"
    lock_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with lock_path.open("w", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        previous_path = APPLIED_ROOT / f"{interface_name}.json"
        previous = read_manifest(previous_path, interface_name) if previous_path.exists() else None
        candidate_digest = manifest_digest(manifest)
        current = previous["generation"] if previous else 0
        current_digest = manifest_digest(previous) if previous else None
        require_generation(
            manifest["generation"],
            current,
            candidate_digest=candidate_digest,
            current_digest=current_digest,
            restore=restore,
        )
        previous_addresses = [peer["address"] for peer in previous["peers"]] if previous else []
        candidate_addresses = [peer["address"] for peer in manifest["peers"]]
        game_target = game_target_for(manifest) if interface_name == "wg-users" else None

        transaction_dir = pathlib.Path(
            tempfile.mkdtemp(prefix=f"{interface_name}-", dir=RUNTIME_ROOT)
        )
        try:
            snapshot_path = transaction_dir / "wireguard.snapshot"
            snapshot_path.write_text(
                run(["wg", "showconf", interface_name]), encoding="utf-8"
            )
            os.chmod(snapshot_path, 0o600)
            candidate_path = transaction_dir / "wireguard.candidate"
            candidate_path.write_text(sync_configuration(manifest), encoding="utf-8")
            os.chmod(candidate_path, 0o600)

            if interface_name == "wg-users":
                run(["nft", "-f", "-"], stdin=user_policy(manifest, game_target))

            try:
                run(["wg", "syncconf", interface_name, str(candidate_path)])
                apply_routes(interface_name, previous_addresses, candidate_addresses)
                verify(manifest, game_target)
                atomic_persist(previous_path, manifest)
            except BaseException:
                run(["wg", "syncconf", interface_name, str(snapshot_path)], check=False)
                apply_routes(interface_name, candidate_addresses, previous_addresses)
                if interface_name == "wg-users":
                    previous_target = game_target_for(previous) if previous else None
                    previous_manifest = previous or {
                        "interface": "wg-users",
                        "peers": [],
                    }
                    run(
                        ["nft", "-f", "-"],
                        stdin=user_policy(previous_manifest, previous_target),
                        check=False,
                    )
                raise
        finally:
            shutil.rmtree(transaction_dir)
        return {
            "interface": interface_name,
            "generation": manifest["generation"],
            "manifest_digest": candidate_digest,
        }


def reconcile_path(path: pathlib.Path, *, restore: bool = False) -> None:
    expected_interface = path.stem
    if path.name != f"{expected_interface}.json" or expected_interface not in INTERFACES:
        raise ContractError("manifest filename is not an owned interface")
    if restore and path.parent != APPLIED_ROOT:
        raise ContractError("boot restore may read only the applied cache")
    apply_manifest(read_manifest(path, expected_interface), restore=restore)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--restore", action="store_true")
    parser.add_argument("manifest", type=pathlib.Path)
    arguments = parser.parse_args()
    reconcile_path(arguments.manifest, restore=arguments.restore)


if __name__ == "__main__":
    main()
