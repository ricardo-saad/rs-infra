#!/bin/sh
set -eu

interface_name="${1:?interface name required}"
case "$interface_name" in
  wg-users|wg-personal|wg-nodes) ;;
  *) exit 2 ;;
esac

configuration="/run/rs-gateway/wireguard/$interface_name.conf"
test -s "$configuration"
test "$(stat -c '%a' "$configuration")" = "600"

if ip link show "$interface_name" >/dev/null 2>&1; then
  wg-quick down "$configuration"
fi
wg-quick up "$configuration"
