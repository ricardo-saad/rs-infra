# Implementation handoff

Snapshot: 2026-07-28  
Base: `main` at `2376ef2`

This file records the current implementation boundary and the shortest safe
path to resume work. It contains no deployed inventory or secret values.

## Completed in the pending change

### Terraform delivery

- Added one GitHub Actions workflow for each deployable stack: `network`,
  `gateway`, `cluster`, and `dns`.
- Trusted same-repository pull requests create a saved Terraform plan. The
  complete plan and text rendering remain private in an SSE-KMS S3 object;
  GitHub receives only change counts and its SHA-256 digest.
- The protected `apply` job retrieves and applies that exact plan after
  checking the merged PR, head SHA, stack tree, workflow path, state key,
  archive members, Terraform version, and digest.
- Forks receive no OIDC identity, state access, or repository secrets.
- Provider lock files are present for all four stacks:
  - AWS provider `6.56.0` for `network`, `gateway`, and `cluster`.
  - Cloudflare provider `5.22.0` for `dns`.
- Cloudflare authentication now uses `CLOUDFLARE_API_TOKEN` rather than a
  Terraform variable, so credentials are not captured in saved plans.

The shared workflow implementations are:

- `.github/scripts/terraform-plan.sh`
- `.github/scripts/terraform-apply.sh`

### Gateway device and control-plane contract

- A `wg-users` peer is explicitly one device, not one person. Each device has
  an opaque `peer_id`, unique WireGuard public key, and unique `/32`.
- Manifests have a canonical SHA-256 digest.
- Equal generation and equal digest is an idempotent retry; equal generation
  with a different digest is a conflict; lower generation is stale.
- Live verification reads back the exact WireGuard peer set, device `/32`
  routes, and `wg-users` authorization rules. Stale routes or rules fail the
  transaction.
- Failure to persist the applied generation rolls the live candidate back.
- Added versioned delivery, applied-state, and exact-acknowledgement schemas.
- Added an optional outbound-only TLS 1.3/mTLS agent for console-owned
  `wg-users` and `wg-nodes`. It has no inbound listener and never accepts
  console authority over `wg-personal`.
- IPv6 forwarding is explicitly disabled. A future client profile should use
  `AllowedIPs = 0.0.0.0/0, ::/0`; IPv6 then fails closed instead of escaping
  through a native client route.

The agent is inactive unless `/etc/rs-gateway/control-plane.env` exists.
`images/gateway/rootfs/etc/rs-gateway/control-plane.env.example` is the current
non-secret configuration contract.

### Operator SSH

- Gateway TCP/22 is admitted only from one to eight explicit operator IPv4
  `/32`s. Wider prefixes and `0.0.0.0/0` are rejected.
- The same allowlist is enforced by both the EC2 security group and host
  nftables.
- Terraform requires an existing EC2 key-pair name and installs only its
  public key through EC2. Terraform never manages the private key.
- The image installs a pinned OpenSSH server and permits key-only access as
  `ubuntu`. Root login, passwords, interactive authentication, agent/X11/TCP
  forwarding, tunnelling, and user environment injection are disabled.

Required gateway inputs:

```hcl
gateway_ssh_key_pair_name = "existing-operator-key-pair"
ssh_ingress_ipv4_cidrs    = ["operator-public-ip/32"]
```

Required image build input:

```sh
export RS_GATEWAY_OPENSSH_SERVER_VERSION='<exact-apt-version>'
```

Changing the SSH `/32` changes instance user data. With
`user_data_replace_on_change = true`, Terraform replaces the gateway so the
host firewall and security group cannot diverge.

## Deployment prerequisites

No AWS, Cloudflare, WireGuard, or GitHub configuration has been applied by
this change.

Before cloud workflows can succeed, configure:

1. The versioned S3 state bucket, native state locking, state KMS key, private
   reviewed-plan bucket, and plan KMS key.
2. Immutable-ID-bound GitHub OIDC trust and least-privilege plan/apply roles.
3. Repository variables and per-stack tfvars secrets listed in `README.md`.
4. A protected `apply` environment restricted to `main` with an operator
   reviewer and the DNS write token.
5. The read-only, expiring `CLOUDFLARE_PLAN_API_TOKEN`.
6. Applicable `Reviewed plan` required checks and squash-only merges.

Important first-merge behavior:

- The new workflows are fail-closed. A direct push to `main` has no reviewed
  PR plan and will not apply Terraform.
- A PR that changes the shared plan/apply scripts triggers all four plan
  workflows and therefore requires all four stack tfvars and backend/OIDC
  configuration.
- If the GitHub prerequisites are intentionally not ready, merge only with
  the expectation that the cloud-plan/apply checks will fail or remain
  environment-gated. Nothing falls back to an unreviewed plan.

## Remaining architecture and application work

### Required before profile enrollment works

- Build the `rs-console` user/device datastore and state machine:
  request, private approval, `/32` allocation, token issue, public-key
  submission, pending gateway apply, exact acknowledgement, active,
  revocation pending, and revoked.
- Implement transactional address allocation, delayed reuse/quarantine,
  capacity alarms, enrollment epochs, token hashes, expiration, one-time
  consumption, and value-free audit events.
- Build the minimal first-party browser setup client. It must generate the
  private key locally, submit only the public key, and assemble the `.conf`
  and QR locally. There is no existing-profile recovery route.
- Define supported-client kill-switch behavior. Portable WireGuard
  `AllowedIPs` cannot prevent every more-specific local-LAN route on every OS.
- Implement the first/recovery `wg-personal` enrollment path without relying
  on the private console that the profile is needed to reach.

These belong to the console/client repositories, not Terraform or the gateway
image.

### Gateway promotion blockers

- Define and implement mTLS identity bootstrap, certificate issuance,
  renewal, revocation, replacement, and trust-root rotation. The current agent
  accepts file paths but does not invent a third durable gateway secret.
- Define the signed-generation envelope upstream: canonical format, algorithm,
  gateway audience, signer key ID, pinned verification keys, overlap/rotation,
  issued/expiry semantics, and recovery behavior. Current delivery is mTLS and
  digest-bound but does not satisfy the signed-generation promotion gate.
- Establish enforceable writer isolation for the console transport rather
  than relying only on the agent's code-level `wg-users`/`wg-nodes` authority.
- Add network-namespace/end-to-end tests for IPv4 egress, dual-stack leak
  prevention, DNS, private-path denial, games-only authorization, revocation,
  gateway replacement, and tunnel-down behavior.
- Build and boot-test the AMI. Packer was not installed in the local validation
  environment.

### Documentation conflict

The accepted `rs-platform` gateway documentation currently describes
SSM-only administration with no public inbound TCP. The requested
operator-restricted TCP/22 implementation intentionally changes that
contract. Amend the upstream ADR and gateway architecture before promoting
this image.

## Validation completed

- Terraform format and generated documentation checks pass.
- Terraform validate and TFLint pass for `network`, `gateway`, `cluster`, and
  `dns`.
- Gateway Terraform tests pass: 2 passed, 0 failed.
- Gateway Python contract tests pass: 34 passed.
- Python compilation and shell syntax checks pass.
- Trivy reports zero high/critical configuration findings.
- Workflow YAML parses and all third-party Action references use full commit
  SHAs.
- `git diff --check` passes.

Packer validation, an AMI build, boot testing, cloud plans, and cloud applies
were not run.

## Recommended resume order

1. Amend the upstream SSH decision and settle the mTLS issuer plus signed
   envelope contracts.
2. Bootstrap the Terraform backend and GitHub OIDC roles.
3. Configure GitHub variables, secrets, environment protection, and required
   checks.
4. Select the exact OpenSSH package pin, build the gateway AMI, and run a boot
   test.
5. Open a reviewed infrastructure PR, apply `network`, then `gateway`, then
   `dns`, and complete the gateway bootstrap-to-runtime role transition.
6. Implement the console device enrollment state machine and browser setup
   client against the checked-in gateway delivery/acknowledgement schemas.
