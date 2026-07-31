import base64
import copy
import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
LIB = ROOT / "rootfs/usr/lib/rs-gateway"
sys.path.insert(0, str(LIB))

import contract
import bootstrap
import control_plane_agent
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

    def test_generation_retries_require_the_exact_digest(self):
        gateway_reconciler.require_generation(2, 1)
        gateway_reconciler.require_generation(
            1,
            1,
            candidate_digest="a" * 64,
            current_digest="a" * 64,
        )
        with self.assertRaises(contract.ContractError):
            gateway_reconciler.require_generation(
                1,
                1,
                candidate_digest="b" * 64,
                current_digest="a" * 64,
            )
        with self.assertRaises(contract.ContractError):
            gateway_reconciler.require_generation(0, 1)
        gateway_reconciler.require_generation(1, 1, restore=True)
        with self.assertRaises(contract.ContractError):
            gateway_reconciler.require_generation(0, 1, restore=True)

    def test_manifest_digest_is_canonical_and_payload_sensitive(self):
        value = manifest("wg-users")
        reordered = {name: value[name] for name in reversed(list(value))}
        self.assertEqual(
            gateway_reconciler.manifest_digest(value),
            gateway_reconciler.manifest_digest(reordered),
        )
        changed = copy.deepcopy(value)
        changed["peers"][0]["public_key"] = key(2)
        self.assertNotEqual(
            gateway_reconciler.manifest_digest(value),
            gateway_reconciler.manifest_digest(changed),
        )

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

    def test_applied_cache_failure_rolls_back_live_candidate(self):
        original_applied = gateway_reconciler.APPLIED_ROOT
        original_runtime = gateway_reconciler.RUNTIME_ROOT
        original_run = gateway_reconciler.run
        original_persist = gateway_reconciler.atomic_persist
        calls = []

        def fake_run(command, *, stdin=None, check=True):
            calls.append(command)
            if command[:2] == ["wg", "showconf"]:
                return "[Interface]\nListenPort = 51823\n"
            if command[:2] == ["wg-quick", "strip"]:
                return "[Interface]\nListenPort = 51823\n"
            if command[:3] == ["wg", "show", "wg-nodes"]:
                return key(1) + "\n"
            if command[:3] == ["ip", "-json", "route"]:
                return json.dumps([{"dst": "10.100.3.10/32", "dev": "wg-nodes"}])
            return ""

        def fail_persist(path, value):
            raise OSError("test-only applied-cache failure")

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            gateway_reconciler.APPLIED_ROOT = root / "applied"
            gateway_reconciler.RUNTIME_ROOT = root / "run"
            gateway_reconciler.run = fake_run
            gateway_reconciler.atomic_persist = fail_persist
            try:
                with self.assertRaises(OSError):
                    gateway_reconciler.apply_manifest(manifest())
            finally:
                gateway_reconciler.APPLIED_ROOT = original_applied
                gateway_reconciler.RUNTIME_ROOT = original_runtime
                gateway_reconciler.run = original_run
                gateway_reconciler.atomic_persist = original_persist

        sync_calls = [command for command in calls if command[:2] == ["wg", "syncconf"]]
        self.assertEqual(len(sync_calls), 2)
        self.assertTrue(any(command[:3] == ["ip", "route", "del"] for command in calls))

    def test_live_verification_rejects_stale_routes_and_user_rules(self):
        value = manifest("wg-users")
        original_run = gateway_reconciler.run
        stale_route = False
        stale_rule = False

        def fake_run(command, *, stdin=None, check=True):
            if command[:2] == ["wg", "show"]:
                return key(1) + "\n"
            if command[:3] == ["ip", "-json", "route"]:
                routes = [{"dst": "10.100.0.10/32"}]
                if stale_route:
                    routes.append({"dst": "10.100.0.11/32"})
                return json.dumps(routes)
            if command[:3] == ["nft", "-a", "list"]:
                if stale_rule:
                    return (
                        "table inet rs_gateway {\n"
                        " chain users_authorize {\n"
                        "  ip saddr 10.100.0.11 ip daddr 10.20.30.40 "
                        "tcp dport 25565 accept # handle 9\n"
                        " }\n}\n"
                    )
                return "table inet rs_gateway {\n chain users_authorize {\n }\n}\n"
            return ""

        gateway_reconciler.run = fake_run
        try:
            gateway_reconciler.verify(value)
            stale_route = True
            with self.assertRaises(RuntimeError):
                gateway_reconciler.verify(value)
            stale_route = False
            stale_rule = True
            with self.assertRaises(RuntimeError):
                gateway_reconciler.verify(value)
        finally:
            gateway_reconciler.run = original_run


class FirewallTests(unittest.TestCase):
    def test_baseline_is_default_drop_with_only_current_public_ports(self):
        policy = render_nftables.render("ens5")
        self.assertGreaterEqual(policy.count("policy drop"), 2)
        self.assertNotIn("tcp dport 22", policy)
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


class ControlPlaneAgentTests(unittest.TestCase):
    def delivery(self, interface_name: str = "wg-users") -> dict:
        value = manifest(interface_name)
        return {
            "schema_version": 1,
            "gateway_id": "gateway-1",
            "delivery_id": "delivery-1",
            "manifest_digest": gateway_reconciler.manifest_digest(value),
            "manifest": value,
        }

    def test_delivery_is_bound_to_gateway_interface_and_digest(self):
        delivery = self.delivery()
        _, validated = control_plane_agent.validate_delivery(delivery, "gateway-1")
        self.assertEqual(validated, delivery["manifest"])
        for field, replacement in (
            ("gateway_id", "gateway-2"),
            ("manifest_digest", "0" * 64),
        ):
            candidate = copy.deepcopy(delivery)
            candidate[field] = replacement
            with self.assertRaises(contract.ContractError):
                control_plane_agent.validate_delivery(candidate, "gateway-1")
        with self.assertRaises(contract.ContractError):
            control_plane_agent.validate_delivery(
                self.delivery("wg-personal"),
                "gateway-1",
            )

    def test_acknowledgement_names_the_exact_applied_manifest(self):
        delivery = self.delivery()
        result = {
            "interface": "wg-users",
            "generation": 1,
            "manifest_digest": delivery["manifest_digest"],
        }
        acknowledgement = control_plane_agent.acknowledgement(delivery, result)
        self.assertEqual(acknowledgement["delivery_id"], "delivery-1")
        self.assertEqual(acknowledgement["interface"], "wg-users")
        self.assertEqual(acknowledgement["generation"], 1)
        self.assertEqual(
            acknowledgement["manifest_digest"],
            delivery["manifest_digest"],
        )
        self.assertEqual(acknowledgement["outcome"], "applied")

    def test_agent_requires_exact_https_mtls_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            private_key = pathlib.Path(directory) / "client.key"
            private_key.write_text("test-only-placeholder\n", encoding="utf-8")
            private_key.chmod(0o600)
            environment = {
                "CONTROL_PLANE_GATEWAY_ID": "gateway-1",
                "CONTROL_PLANE_DESIRED_URL": "https://console.example/v1/desired",
                "CONTROL_PLANE_ACK_URL": "https://console.example/v1/ack",
                "CONTROL_PLANE_CA_FILE": "/run/control-plane/ca.pem",
                "CONTROL_PLANE_CLIENT_CERT_FILE": "/run/control-plane/client.pem",
                "CONTROL_PLANE_CLIENT_KEY_FILE": str(private_key),
                "CONTROL_PLANE_POLL_SECONDS": "15",
            }
            self.assertEqual(
                control_plane_agent.required_configuration(environment),
                environment,
            )
            for name, value in (
                ("CONTROL_PLANE_DESIRED_URL", "http://console.example/v1/desired"),
                ("CONTROL_PLANE_ACK_URL", "https://other.example/v1/ack"),
                ("CONTROL_PLANE_POLL_SECONDS", "1"),
            ):
                candidate = {**environment, name: value}
                with self.assertRaises(contract.ContractError):
                    control_plane_agent.required_configuration(candidate)
            private_key.chmod(0o644)
            with self.assertRaises(contract.ContractError):
                control_plane_agent.required_configuration(environment)

    def test_delivery_writes_and_applies_before_acknowledging(self):
        events = []
        original_persist = control_plane_agent.atomic_persist
        original_apply = control_plane_agent.apply_manifest

        def fake_persist(path, value):
            events.append(("persist", path.name, value["generation"]))

        def fake_apply(value):
            events.append(("apply", value["interface"], value["generation"]))
            return {
                "interface": value["interface"],
                "generation": value["generation"],
                "manifest_digest": gateway_reconciler.manifest_digest(value),
            }

        control_plane_agent.atomic_persist = fake_persist
        control_plane_agent.apply_manifest = fake_apply
        try:
            acknowledgement = control_plane_agent.deliver(
                self.delivery(),
                "gateway-1",
            )
        finally:
            control_plane_agent.atomic_persist = original_persist
            control_plane_agent.apply_manifest = original_apply
        self.assertEqual(events[0][0], "persist")
        self.assertEqual(events[1][0], "apply")
        self.assertEqual(acknowledgement["outcome"], "applied")


class ImageLayoutTests(unittest.TestCase):
    def test_final_image_removes_openssh_server(self):
        self.assertFalse(
            (ROOT / "rootfs/etc/ssh/sshd_config.d/90-rs-gateway.conf").exists()
        )
        install = (ROOT / "scripts/install.sh").read_text(encoding="utf-8")
        self.assertIn("apt-get purge -y openssh-server", install)
        self.assertIn("systemctl disable --now ssh.service", install)
        self.assertNotIn('"openssh-server=', install)

    def test_ipv6_forwarding_is_explicitly_disabled(self):
        sysctl = (
            ROOT
            / "rootfs"
            / "etc"
            / "sysctl.d"
            / "90-rs-gateway.conf"
        ).read_text(encoding="utf-8")
        self.assertIn("net.ipv6.conf.all.forwarding = 0", sysctl)
        self.assertIn("net.ipv6.conf.default.forwarding = 0", sysctl)

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

    def test_control_plane_agent_is_outbound_mtls_and_console_scoped(self):
        agent = (
            ROOT / "rootfs/usr/lib/rs-gateway/control_plane_agent.py"
        ).read_text(encoding="utf-8")
        unit = (
            ROOT
            / "rootfs/etc/systemd/system/rs-gateway-control-plane-agent.service"
        ).read_text(encoding="utf-8")
        self.assertIn("http.client.HTTPSConnection", agent)
        self.assertIn("ssl.CERT_REQUIRED", agent)
        self.assertIn("ssl.TLSVersion.TLSv1_3", agent)
        self.assertIn('CONSOLE_INTERFACES = ("wg-users", "wg-nodes")', agent)
        self.assertNotIn("ListenStream=", unit)
        self.assertIn("ConditionPathExists=/etc/rs-gateway/control-plane.env", unit)

    def test_builder_uses_ssm_and_pins_the_runtime_agent(self):
        packer = (ROOT / "gateway.pkr.hcl").read_text(encoding="utf-8")
        build = (ROOT / "scripts/build.sh").read_text(encoding="utf-8")
        install = (ROOT / "scripts/install.sh").read_text(encoding="utf-8")
        self.assertIn('ssh_interface', packer)
        self.assertIn('"session_manager"', packer)
        self.assertIn("iam_instance_profile", packer)
        self.assertIn("RS_GATEWAY_BUILDER_INSTANCE_PROFILE", build)
        self.assertIn("RS_GATEWAY_BUILD_SUBNET_ID", build)
        self.assertIn('default = "t4g.small"', packer)
        self.assertIn("RS_GATEWAY_SESSION_MANAGER_PLUGIN_VERSION", build)
        self.assertIn("RS_GATEWAY_SSM_AGENT_REVISION", build)
        self.assertIn("ubuntu-resolute-26.04-arm64-server-", build)
        self.assertIn("snap refresh --hold=forever amazon-ssm-agent", install)

    def test_image_workflow_is_path_scoped_and_fork_safe(self):
        workflow = (
            ROOT.parents[1] / ".github/workflows/image-gateway.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("- images/gateway/**", workflow)
        self.assertIn("head.repo.full_name == github.repository", workflow)
        self.assertIn("head.repo.full_name != github.repository", workflow)
        self.assertIn("IMAGE_BUILD_ROLE_ARN", workflow)
        self.assertIn("IMAGE_BUILDER_INSTANCE_PROFILE", workflow)
        self.assertNotIn("\n  push:", workflow)

    def test_json_schemas_parse_and_forbid_unknown_properties(self):
        schemas = ROOT / "rootfs/usr/lib/rs-gateway/schemas"
        for path in schemas.glob("*.json"):
            document = json.loads(path.read_text(encoding="utf-8"))
            self.assertFalse(document["additionalProperties"])


if __name__ == "__main__":
    unittest.main()
