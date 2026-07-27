#!/bin/sh
set -eu

for interface_name in wg-users wg-personal wg-nodes; do
  manifest="/var/lib/rs-gateway/applied/$interface_name.json"
  if [ -f "$manifest" ]; then
    /usr/lib/rs-gateway/gateway_reconciler.py --restore "$manifest"
  fi
done
