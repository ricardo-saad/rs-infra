# Gateway image

This directory builds the disposable ARM64 EC2 gateway appliance described by
the platform gateway contract. The image contains the host implementation; it
does not contain credentials, peer inventory, private topology, or Terraform
configuration.

The effective interface contract is deliberately fixed:

| Interface | UDP | Gateway address | Purpose |
|---|---:|---|---|
| `wg-users` | 51820 | `10.100.0.1/24` | Human internet egress and optional game access |
| `wg-personal` | 51822 | `10.100.2.1/24` | Operator-only private access |
| `wg-nodes` | 51823 | `10.100.3.1/24` | Enrolled home nodes |

There is no `wg-cluster` or `wg-egress` interface. Cluster attachment is VPC
routing and belongs to the gateway Terraform/network policy integration.

## Build

All provider and package pins are explicit inputs because their approved
values are not yet recorded in the architecture repository:

```sh
export PACKER_AMAZON_PLUGIN_VERSION='<exact-version>'
export RS_GATEWAY_PACKER_VERSION='<exact-version>'
export RS_GATEWAY_SOURCE_AMI='ami-...'
export RS_GATEWAY_SOURCE_AMI_OWNER='123456789012'
export RS_GATEWAY_ROOT_VOLUME_SIZE='<approved-gib>'
export RS_GATEWAY_WIREGUARD_VERSION='<apt-version>'
export RS_GATEWAY_NFTABLES_VERSION='<apt-version>'
export RS_GATEWAY_APT_REPOSITORY='<approved signed snapshot deb line>'
export RS_GATEWAY_ADGUARD_ARCHIVE_URL='<versioned-arm64-archive-url>'
export RS_GATEWAY_ADGUARD_ARCHIVE_SHA256='<64-hex-digest>'
export RS_GATEWAY_ADGUARD_SCHEMA_VERSION='<schema-for-pinned-version>'
export RS_GATEWAY_ADGUARD_UPSTREAM_DNS='<approved-upstream>'
export RS_GATEWAY_ADGUARD_FILTER_NAME='<approved-filter-name>'
export RS_GATEWAY_ADGUARD_FILTER_URL='<versioned-or-reviewed-filter-url>'
export RS_GATEWAY_AWSCLI_VERSION='<apt-version>'
export RS_GATEWAY_APACHE2_UTILS_VERSION='<apt-version>'
export RS_GATEWAY_CURL_VERSION='<apt-version>'
export RS_GATEWAY_CA_CERTIFICATES_VERSION='<apt-version>'
export RS_GATEWAY_PYTHON3_VERSION='<apt-version>'
export RS_GATEWAY_OPENSSH_SERVER_VERSION='<apt-version>'
export RS_GATEWAY_BUILD_VERSION='<immutable-release-id>'
./scripts/build.sh
```

`scripts/build.sh` verifies that the immutable source AMI is ARM64 and owned
by the declared account before invoking Packer. The build identity therefore
needs only AMI build/publication permissions. No runtime secret permission is
used while building.

## Runtime input

Terraform/user data writes `/etc/rs-gateway/runtime.env` using
`runtime.env.example` as its allowlist. These are non-secret identifiers only:
region, the two exact Secrets Manager identifiers, the public-key Parameter
Store prefix, CloudWatch namespace, WAN device, operator SSH `/32` allowlist,
and immutable build version.

The normal boot target runs the fail-closed loader. It retrieves both
`AWSCURRENT` values, validates them in memory, writes derived configuration
only beneath `/run/rs-gateway`, republishes all three public keys, and then
allows networking to start. A missing or malformed value leaves WireGuard,
nftables, reconciliation, and AdGuard stopped.

The baseline firewall gives `wg-users` public egress with private destinations
denied, gives `wg-personal` private-range and enrolled-node access without
internet egress, and masquerades public egress arriving from the Talos subnet.
It admits TCP/22 on the WAN only from the same one-to-eight operator `/32`s
enforced by the EC2 security group. The image installs an explicitly pinned
OpenSSH server with key-only `ubuntu` access; root login, passwords,
agent/X11/TCP forwarding, tunnels, and user environment injection are
disabled.
The gateway security group scopes that same-interface NAT path to the declared
Talos CIDR. `wg-nodes` has no WAN or node-to-node path, and named relays remain
default-denied until the separately versioned routing policy installs them.

The loader emits value-free `SecretLoadFailure` or
`PublicKeyPublicationFailure` metrics for the distinguishable failure phase.
After a successful load, a systemd timer publishes `GatewayHeartbeat` once per
minute. Metrics have no secret version, peer, or client labels.

`rs-gateway-bootstrap.service` is a separate, disabled, one-time unit for an
instance launched with the temporary bootstrap profile. It refuses either
secret if `AWSCURRENT` already exists, generates the first values locally,
publishes public keys, and emits only a value-free completion metric. It must
not be enabled on a runtime instance. Infrastructure automation must replace
the bootstrap profile, prove secret writes are denied, and disable/remove the
bootstrap role before promotion.

The enabled runtime target is ordered after `cloud-final.service`, giving
user data time to replace `runtime.env`. Bootstrap user data uses this exact
safe trigger sequence:

1. write the allowlisted non-secret `runtime.env`;
2. create root-owned mode `0600`
   `/etc/rs-gateway/bootstrap-enabled`;
3. start `rs-gateway-bootstrap.service` explicitly.

The condition file prevents `rs-gateway.target` from starting and the
bootstrap unit conflicts with that target. After successful bootstrap,
infrastructure automation replaces the instance profile, proves write denial,
removes the condition file, and reboots (or explicitly starts the runtime
target). Runtime user data never creates the condition file.

## Desired peer state

Writers atomically replace exactly one of:

- `/var/lib/rs-gateway/desired/wg-users.json`
- `/var/lib/rs-gateway/desired/wg-personal.json`
- `/var/lib/rs-gateway/desired/wg-nodes.json`

The reconciler rejects unknown fields, wrong interfaces, stale generations,
invalid or duplicate keys, non-`/32`/out-of-subnet addresses, reserved
addresses, unsupported health policies, and excessive peer counts. It holds
an interface lock, snapshots live state into `/run`, applies and verifies the
whole candidate, and restores WireGuard, routes, and user policy on failure.
Verification reads back the exact WireGuard peer set, exact per-device `/32`
routes, and exact `wg-users` authorization rules. The generation is persisted
only after verification; persistence failure also rolls the live candidate
back.

On boot, a distinct restore unit reapplies only the root-owned last-applied
cache before the desired-state watcher starts. That path may reapply the same
generation to empty live interfaces. A transport retry with the same
generation and the same canonical SHA-256 manifest digest is also safe and
reconverges the live state before acknowledging. The same generation with a
different digest is a conflict, and an older generation is stale.

`peer_id` is an opaque per-device identity, not a person, email address, or
other client-identifying label. A person with two devices therefore has two
peers, keys, and `/32`s.

## Outbound control-plane transport

The image includes an optional outbound-only mTLS agent. It is activated only
when `/etc/rs-gateway/control-plane.env` exists; the checked-in
`control-plane.env.example` documents its non-secret endpoint and file-path
contract. TLS 1.3 requires a caller-supplied CA, client certificate, and mode
`0600` client key. The agent rejects plaintext URLs, redirects, cross-origin
desired/acknowledgement endpoints, oversized responses, and deliveries for
`wg-personal`.

The two endpoint paths are configuration rather than product assumptions.
Each poll reports the exact applied generation and canonical manifest digest
for the console-owned `wg-users` and `wg-nodes` interfaces. A returned
delivery is accepted only when its gateway ID, interface authority, manifest,
and digest all validate. The agent writes the desired file atomically,
reconciles it, and posts an acknowledgement containing the exact delivery ID,
interface, generation, and applied digest. If acknowledgement delivery fails,
the control plane may repeat the same generation and digest safely.

The administrator remains the only writer of `wg-personal`. The console
datastore, IP allocation, enrollment capability, approval decision, client
profile rendering, and client-side key generation do not belong in this
image.

The agent does not invent a durable client credential. Provisioning and
renewal of its short-lived mTLS identity remain blocked on the platform issuer
contract; no third gateway recovery secret is added here. Detached desired
state signatures likewise require an agreed signing algorithm and pinned
verification-key lifecycle. Until those contracts are implemented, mTLS is
the delivery authentication boundary and this transport must not be promoted
as satisfying the architecture's signed-generation gate.

`games` is schema-valid only for `wg-users`, but is rejected at apply time
until `/etc/rs-gateway/game-target.json` contains the separately reviewed
exact destination `/32`, protocol, and port. Manifests cannot supply their own
destination.

## Tests

```sh
python3 -m unittest discover -s tests -v
```

Image promotion additionally requires Packer validation, a boot test, and the
gateway acceptance suite from the architecture repository. The unit tests
here do not claim to replace those infrastructure tests.
