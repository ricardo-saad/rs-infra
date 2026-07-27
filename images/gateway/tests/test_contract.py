import base64
import copy
import importlib.util
import json
import pathlib
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
LIB = ROOT / "rootfs/usr/lib/rs-gateway"
sys.path.insert(0, str(LIB))

import contract
import bootstrap
import gateway_reconciler
import render_nftables
import secret_loader


def key(seed: int) -> str:
    return base64.b64encode(bytes([seed]) * 32).decode("ascii")


def manifest(interface_name: str = "wg-nodes") -> dict:
    third_octet = {
        "wg-users": 0,
        "wg-personal": 2,
        "wg-nodes": 3,
    }[interface_name]
    peer = {
        "peer_id": "peer-1",
        "public_key": key(1),
        "address": f"10.100.{third_octet}.10/32",
        "health_policy": "required",
    }
    if interface_name == "wg-users":
        peer["permissions"] = ["egress"]
    return {
        "schema_version": 1,
        "interface": interface_name,
        "generation": 1,
        "generated_at": "2026-07-27T12:00:00Z",
        "peers": [peer],
    }


class EffectiveContractTests(unittest.TestCase):
    def test_exactly_three_current_interfaces(self):
        self.assertEqual(
            set(contract.INTERFACES),
            {"wg-users", "wg-personal", "wg-nodes"},
        )
        self.assertNotIn("wg-cluster", contract.INTERFACES)
        self.assertNotIn("wg-egress", contract.INTERFACES)

    def test_interface_ports_and_subnets_are_fixed(self):
        expected = {
            "wg-users": (51820, "10.100.0.0/24"),
            "wg-personal": (51822, "10.100.2.0/24"),
            "wg-nodes": (51823, "10.100.3.0/24"),
        }
        for name, (port, subnet) in expected.items():
            self.assertEqual(contract.INTERFACES[name].port, port)
            self.assertEqual(str(contract.INTERFACES[name].subnet), subnet)

    def test_runtime_environment_accepts_only_complete_identifiers(self):
        environment = {
            "AWS_REGION": "eu-west-2",
            "WIREGUARD_SECRET_ID": "wireguard-secret",
            "ADGUARD_SECRET_ID": "adguard-secret",
            "PUBLIC_KEY_PARAMETER_PREFIX": "/gateway/public",
            "CLOUDWATCH_NAMESPACE": "RSPlatform/Gateway",
            "WAN_INTERFACE": "ens5",
            "BUILD_VERSION": "build-1",
        }
        self.assertEqual(secret_loader.required_environment(environment), environment)
        environment["AWS_REGION"] = "us-east-1"
        with self.assertRaises(contract.ContractError):
            secret_loader.required_environment(environment)

    def test_wireguard_secret_has_exact_interface_set(self):
        value = {name: key(index + 1) for index, name in enumerate(contract.INTERFACES)}
        self.assertEqual(secret_loader.validate_wireguard_secret(value), value)
        value["wg-cluster"] = key(9)
        with self.assertRaises(contract.ContractError):
            secret_loader.validate_wireguard_secret(value)

    def test_adguard_secret_requires_only_recoverable_credential_material(self):
        valid = {
            "username": "admin",
            "password": "A-secure-runtime-password-0123456789",
        }
        self.assertEqual(secret_loader.validate_adguard_secret(valid), valid)
        invalid = {**valid, "password_hash": "$2y$12$" + "A" * 53}
        with self.assertRaises(contract.ContractError):
            secret_loader.validate_adguard_secret(invalid)

    def test_loader_hashes_password_over_stdin_not_argv_or_output(self):
        calls = []
        original_run = secret_loader.run

        def fake_run(command, *, stdin=None):
            calls.append((command, stdin))
            return "admin:$2y$12$" + "A" * 53 + "\n"

        secret_loader.run = fake_run
        try:
            secret_value = {
                "username": "admin",
                "password": "A-secure-runtime-password-0123456789",
            }
            credentials = secret_loader.hash_adguard_credentials(secret_value)
        finally:
            secret_loader.run = original_run
        command, password_stdin = calls[0]
        self.assertEqual(command, ["htpasswd", "-niBC", "12", "admin"])
        self.assertIsNotNone(password_stdin)
        plaintext = password_stdin.rstrip("\n")
        self.assertNotIn(plaintext, command)
        self.assertNotIn(plaintext, json.dumps(credentials))
        self.assertEqual(set(credentials), {"username", "password_hash"})

    def test_bootstrap_writes_secret_through_stdin_not_argv(self):
        calls = []
        original_run = bootstrap.run

        def fake_run(command, *, stdin=None):
            calls.append((command, stdin))
            return ""

        bootstrap.run = fake_run
        try:
            value = {
                "username": "admin",
                "password": "A-secure-runtime-password-0123456789",
            }
            bootstrap.put_first_version("exact-secret-id", "eu-west-2", value)
        finally:
            bootstrap.run = original_run
        command, secret_stdin = calls[0]
        self.assertEqual(command[-1], "file:///dev/stdin")
        self.assertNotIn(value["password"], command)
        self.assertEqual(json.loads(secret_stdin), value)


class ManifestValidationTests(unittest.TestCase):
    def test_validates_each_interface(self):
        for interface_name in contract.INTERFACES:
            value = manifest(interface_name)
            self.assertEqual(
                gateway_reconciler.validate_manifest(value, interface_name),
                value,
            )

    def test_rejects_unknown_fields_and_wrong_file_authority(self):
        value = manifest()
        value["allowed_ips"] = ["0.0.0.0/0"]
        with self.assertRaises(contract.ContractError):
            gateway_reconciler.validate_manifest(value, "wg-nodes")
        with self.assertRaises(contract.ContractError):
            gateway_reconciler.validate_manifest(manifest(), "wg-personal")

    def test_rejects_wide_out_of_subnet_and_reserved_addresses(self):
        for address in ("10.100.3.10/24", "10.100.2.10/32", "10.100.3.1/32"):
            value = manifest()
            value["peers"][0]["address"] = address
            with self.assertRaises(contract.ContractError):
                gateway_reconciler.validate_manifest(value, "wg-nodes")

    def test_rejects_duplicate_identity_and_address(self):
        value = manifest()
        value["peers"].append(copy.deepcopy(value["peers"][0]))
        with self.assertRaises(contract.ContractError):
            gateway_reconciler.validate_manifest(value, "wg-nodes")

    def test_rejects_malformed_key_and_timestamp(self):
        value = manifest()
        value["peers"][0]["public_key"] = "not-a-wireguard-key"
        with self.assertRaises(contract.ContractError):
            gateway_reconciler.validate_manifest(value, "wg-nodes")
        value = manifest()
        value["generated_at"] = "2026-07-27T12:00:00+03:00"
        with self.assertRaises(contract.ContractError):
            gateway_reconciler.validate_manifest(value, "wg-nodes")

    def test_rejects_stale_and_repeated_generations(self):
        gateway_reconciler.require_generation(2, 1)
        for candidate in (1, 0):
            with self.assertRaises(contract.ContractError):
                gateway_reconciler.require_generation(candidate, 1)
        gateway_reconciler.require_generation(1, 1, restore=True)
        with self.assertRaises(contract.ContractError):
            gateway_reconciler.require_generation(0, 1, restore=True)

    def test_users_require_egress_and_only_known_additive_permission(self):
        value = manifest("wg-users")
        for permissions in ([], ["games"], ["egress", "admin"], ["egress", "egress"]):
            candidate = copy.deepcopy(value)
            candidate["peers"][0]["permissions"] = permissions
            with self.assertRaises(contract.ContractError):
                gateway_reconciler.validate_manifest(candidate, "wg-users")
        value["peers"][0]["permissions"] = ["egress", "games"]
        self.assertEqual(
            gateway_reconciler.validate_manifest(value, "wg-users"),
            value,
        )

    def test_game_policy_uses_only_separate_reviewed_target(self):
        value = manifest("wg-users")
        value["peers"][0]["permissions"] = ["egress", "games"]
        target = {
            "schema_version": 1,
            "destination": "10.20.30.40/32",
            "protocol": "tcp",
            "port": 25565,
        }
        policy = gateway_reconciler.user_policy(value, target)
        self.assertIn("ip saddr 10.100.0.10", policy)
        self.assertIn("ip daddr 10.20.30.40 tcp dport 25565 accept", policy)
        self.assertNotIn("masquerade", policy)


class FirewallTests(unittest.TestCase):
    def test_baseline_is_default_drop_with_only_current_public_ports(self):
        policy = render_nftables.render("ens5")
        self.assertGreaterEqual(policy.count("policy drop"), 2)
        self.assertIn("51820, 51822, 51823", policy)
        self.assertNotIn("51821", policy)
        self.assertIn('iifname "wg-users" jump users_authorize', policy)
        self.assertIn('iifname "wg-personal" oifname "ens5" drop', policy)
        self.assertIn('iifname "wg-nodes" oifname "ens5" drop', policy)
        self.assertIn('iifname "wg-users" oifname "ens5" masquerade', policy)

    def test_baseline_includes_private_role_and_talos_nat_contracts(self):
        policy = render_nftables.render("ens5")
        self.assertIn('iifname "wg-personal" ip daddr', policy)
        self.assertIn('iifname "wg-personal" oifname "ens5" drop', policy)
        self.assertIn('iifname "ens5" ip saddr', policy)
        self.assertIn('oifname "ens5" masquerade', policy)
        self.assertNotIn('iifname "wg-nodes" oifname "ens5" accept', policy)

    def test_wan_interface_is_not_shell_or_nft_injectable(self):
        for value in ('ens5"; accept', "ens5\nflush ruleset", ""):
            with self.assertRaises(ValueError):
                render_nftables.render(value)


class ImageLayoutTests(unittest.TestCase):
    def test_bootstrap_unit_is_disabled_and_separate(self):
        bootstrap = (
            ROOT
            / "rootfs/etc/systemd/system/rs-gateway-bootstrap.service"
        ).read_text(encoding="utf-8")
        runtime = (
            ROOT
            / "rootfs/etc/systemd/system/rs-gateway-secret-loader.service"
        ).read_text(encoding="utf-8")
        target = (
            ROOT / "rootfs/etc/systemd/system/rs-gateway.target"
        ).read_text(encoding="utf-8")
        self.assertIn("ConditionPathExists=/etc/rs-gateway/bootstrap-enabled", bootstrap)
        self.assertNotIn("Requires=rs-gateway-bootstrap.service", target)
        self.assertNotIn("Wants=rs-gateway-bootstrap.service", target)
        self.assertIn("fail-closed", runtime)

    def test_runtime_waits_for_cloud_final_and_bootstrap_blocks_runtime(self):
        target = (
            ROOT / "rootfs/etc/systemd/system/rs-gateway.target"
        ).read_text(encoding="utf-8")
        loader = (
            ROOT
            / "rootfs/etc/systemd/system/rs-gateway-secret-loader.service"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "ConditionPathExists=!/etc/rs-gateway/bootstrap-enabled",
            target,
        )
        self.assertIn("After=network-online.target cloud-final.service", target)
        self.assertIn("After=cloud-final.service network-online.target", loader)

    def test_runtime_telemetry_is_value_free_and_scheduled(self):
        loader = (
            ROOT / "rootfs/usr/lib/rs-gateway/secret_loader.py"
        ).read_text(encoding="utf-8")
        heartbeat = (
            ROOT / "rootfs/usr/lib/rs-gateway/publish-heartbeat.py"
        ).read_text(encoding="utf-8")
        timer = (
            ROOT
            / "rootfs/etc/systemd/system/rs-gateway-heartbeat.timer"
        ).read_text(encoding="utf-8")
        self.assertIn('"SecretLoadFailure"', loader)
        self.assertIn('"PublicKeyPublicationFailure"', loader)
        self.assertIn('"GatewayHeartbeat"', heartbeat)
        self.assertIn("OnUnitActiveSec=1min", timer)
        for forbidden_label in ("peer_id", "public_key", "VersionId"):
            self.assertNotIn(forbidden_label, heartbeat)

    def test_json_schemas_parse_and_forbid_unknown_properties(self):
        schemas = ROOT / "rootfs/usr/lib/rs-gateway/schemas"
        for path in schemas.glob("*.json"):
            document = json.loads(path.read_text(encoding="utf-8"))
            self.assertFalse(document["additionalProperties"])


if __name__ == "__main__":
    unittest.main()
