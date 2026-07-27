#!/usr/bin/env python3
"""Shared, secret-free gateway contract validation."""

from __future__ import annotations

import base64
import ipaddress
import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Interface:
    name: str
    port: int
    subnet: ipaddress.IPv4Network
    gateway: ipaddress.IPv4Address
    peer_limit: int = 253


INTERFACES = {
    "wg-users": Interface(
        "wg-users",
        51820,
        ipaddress.ip_network("10.100.0.0/24"),
        ipaddress.ip_address("10.100.0.1"),
    ),
    "wg-personal": Interface(
        "wg-personal",
        51822,
        ipaddress.ip_network("10.100.2.0/24"),
        ipaddress.ip_address("10.100.2.1"),
    ),
    "wg-nodes": Interface(
        "wg-nodes",
        51823,
        ipaddress.ip_network("10.100.3.0/24"),
        ipaddress.ip_address("10.100.3.1"),
    ),
}

WIREGUARD_KEY_RE = re.compile(r"^[A-Za-z0-9+/]{43}=$")
BCRYPT_RE = re.compile(r"^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$")
OPAQUE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")


class ContractError(ValueError):
    """An input violates the effective gateway contract."""


def validate_wireguard_key(value: object) -> str:
    if not isinstance(value, str) or not WIREGUARD_KEY_RE.fullmatch(value):
        raise ContractError("malformed WireGuard key")
    try:
        decoded = base64.b64decode(value, validate=True)
    except ValueError as error:
        raise ContractError("malformed WireGuard key") from error
    if len(decoded) != 32:
        raise ContractError("malformed WireGuard key")
    return value


def validate_peer_address(value: object, interface: Interface) -> str:
    if not isinstance(value, str):
        raise ContractError("peer address must be a string")
    try:
        address = ipaddress.ip_interface(value)
    except ValueError as error:
        raise ContractError("malformed peer address") from error
    if not isinstance(address, ipaddress.IPv4Interface) or address.network.prefixlen != 32:
        raise ContractError("peer address must be an IPv4 /32")
    if address.ip not in interface.subnet:
        raise ContractError("peer address is outside the interface subnet")
    if address.ip in {
        interface.subnet.network_address,
        interface.subnet.broadcast_address,
        interface.gateway,
    }:
        raise ContractError("peer address is reserved")
    return str(address)
