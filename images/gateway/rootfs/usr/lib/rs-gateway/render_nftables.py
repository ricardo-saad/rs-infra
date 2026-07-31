#!/usr/bin/env python3
"""Render the value-free baseline firewall for the three-interface gateway."""

from __future__ import annotations

import os
import pathlib
import re
import tempfile

INTERFACE_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,15}$")


def render(wan_interface: str) -> str:
    if not INTERFACE_RE.fullmatch(wan_interface):
        raise ValueError("invalid WAN interface")
    return f"""flush ruleset
table inet rs_gateway {{
  chain users_authorize {{
  }}

  chain input {{
    type filter hook input priority 0; policy drop;
    iifname "lo" accept
    ct state established,related accept
    iifname "{wan_interface}" udp dport {{ 51820, 51822, 51823 }} accept
    iifname {{ "wg-users", "wg-personal", "wg-nodes" }} udp dport 53 accept
    iifname {{ "wg-users", "wg-personal", "wg-nodes" }} tcp dport 53 accept
    iifname "wg-personal" tcp dport 3000 accept
  }}

  chain forward {{
    type filter hook forward priority 0; policy drop;
    ct state established,related accept

    # Exact additive allows return here before the general private drop.
    iifname "wg-users" jump users_authorize
    # Humans receive internet egress, never a generic private path.
    iifname "wg-users" ip daddr {{
      10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8,
      169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16,
      224.0.0.0/4, 240.0.0.0/4
    }} drop
    iifname "wg-users" oifname "{wan_interface}" accept

    # Role 4 is private-only: VPC/private ranges and enrolled nodes are
    # reachable, but the WAN is not an internet-egress path for this role.
    iifname "wg-personal" ip daddr {{
      10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16,
      172.16.0.0/12, 192.168.0.0/16
    }} oifname "{wan_interface}" accept
    iifname "wg-personal" oifname "{wan_interface}" drop
    iifname "wg-personal" oifname "wg-nodes" accept

    # Nodes have no gateway internet or node-to-node path. Exact relays are
    # installed by the separately versioned routing-policy reconciler.
    iifname "wg-nodes" oifname "{wan_interface}" drop
    iifname "wg-nodes" oifname "wg-nodes" drop

    # AWS security-group ingress restricts this same-interface forwarding
    # path to the declared Talos subnet. Keep private destinations denied;
    # only public egress is permitted until named relay policy is installed.
    iifname "{wan_interface}" ip saddr {{
      10.0.0.0/8, 100.64.0.0/10, 172.16.0.0/12, 192.168.0.0/16
    }} ip daddr {{
      10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8,
      169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16,
      224.0.0.0/4, 240.0.0.0/4
    }} drop
    iifname "{wan_interface}" ip saddr {{
      10.0.0.0/8, 100.64.0.0/10, 172.16.0.0/12, 192.168.0.0/16
    }} oifname "{wan_interface}" accept
  }}
}}

table ip rs_gateway_nat {{
  chain postrouting {{
    type nat hook postrouting priority srcnat; policy accept;
    iifname "wg-users" oifname "{wan_interface}" masquerade
    iifname "{wan_interface}" ip saddr {{
      10.0.0.0/8, 100.64.0.0/10, 172.16.0.0/12, 192.168.0.0/16
    }} oifname "{wan_interface}" masquerade
  }}
}}
"""


def main() -> None:
    wan_interface = os.environ.get("WAN_INTERFACE", "")
    content = render(wan_interface)
    destination = pathlib.Path("/run/rs-gateway/nftables.conf")
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=destination.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


if __name__ == "__main__":
    main()
