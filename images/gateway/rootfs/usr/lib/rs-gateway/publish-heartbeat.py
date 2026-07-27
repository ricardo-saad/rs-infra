#!/usr/bin/env python3
"""Publish a value-free steady-state gateway heartbeat."""

from __future__ import annotations

import os
import pathlib

from secret_loader import required_environment, run


def main() -> None:
    config = required_environment(os.environ)
    if not pathlib.Path("/run/rs-gateway/loaded-versions.json").is_file():
        raise RuntimeError("runtime secret load has not completed")
    for unit in (
        "rs-gateway-wireguard@wg-users.service",
        "rs-gateway-wireguard@wg-personal.service",
        "rs-gateway-wireguard@wg-nodes.service",
        "rs-gateway-nftables.service",
        "rs-gateway-restore.service",
        "rs-gateway-adguard.service",
    ):
        if run(["systemctl", "is-active", unit]).strip() != "active":
            raise RuntimeError("a required gateway unit is not active")
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
            "GatewayHeartbeat",
            "--value",
            "1",
            "--unit",
            "Count",
        ]
    )


if __name__ == "__main__":
    main()
