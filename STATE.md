# Implementation handoff

Snapshot: 2026-07-31
Base: `main` at `37fb557`

This file records the current implementation boundary and the shortest safe
path to resume work. It contains no deployed inventory or secret values.

## Completed in the pending change

### Terraform delivery

- Added one path-filtered caller for each deployable stack plus IAM-bound
  reusable plan/apply workflows. Credential-bearing steps cannot live in the
  stack-specific callers.
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
- Added a path-filtered gateway image workflow. Trusted same-repository pull
  requests build a real AMI and publish its manifest; forks remain
  credential-free.
- Added a dedicated OIDC image-build role and a separate SSM-only EC2 builder
  profile. The build role may pass only that profile and cannot read or write
  gateway secret values.

The shared workflow implementations are:

- `.github/workflows/_reusable-terraform-plan.yml`
- `.github/workflows/_reusable-terraform-apply.yml`
- `.github/workflows/_reusable-image-gateway-build.yml`
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

### Gateway host access and appliance

- ADR-0034 selects official Canonical Ubuntu Server 26.04 LTS ARM64 and
  `t4g.small` for the initial gateway.
- Gateway TCP/22 is absent from the EC2 security group and host nftables.
- The runtime instance has no EC2 key pair and the final AMI contains no
  OpenSSH server.
- SSM Session Manager is the sole operating-system administration path.
- Packer tunnels its temporary SSH communicator through Session Manager,
  verifies the approved SSM Agent snap revision, and purges OpenSSH before
  snapshotting the final AMI.

## Deployment prerequisites

No AWS, Cloudflare, WireGuard, or GitHub configuration has been applied by
this change.

Before cloud workflows can succeed, configure:

1. The versioned S3 state bucket, native state locking, state KMS key, private
   reviewed-plan bucket, and plan KMS key.
2. Immutable-ID-bound GitHub OIDC trust and least-privilege plan, apply, and
   image-build roles plus the build-only instance profile.
3. Repository variables, image pins, and per-stack tfvars secrets listed in
   `README.md`, including the applied network stack's public build subnet.
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
- A trusted PR that changes `images/gateway/` triggers a billable AMI build and
  requires the image role, builder profile, build subnet, and complete pin set.
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
- Run the first CI AMI build and add the SSM-only boot/acceptance test required
  before promotion.

## Validation completed

- Terraform formatting, generated bootstrap/gateway documentation, and
  bootstrap/gateway TFLint pass for the current change.
- Gateway Python contract tests pass: 34 passed.
- Gateway shell syntax checks pass.
- Packer formatting and syntax-only validation pass.
- The gateway image workflow passes `actionlint`, and every referenced action
  remains pinned to a full commit SHA.
- Bootstrap/gateway Terraform validation and gateway tests still need a
  successful provider registry initialization in the current environment.
- `git diff --check` passes.

An AMI build, boot testing, cloud plans, and cloud applies were not run.

## Recommended resume order

1. Settle the mTLS issuer plus signed envelope contracts.
2. Bootstrap the Terraform backend and GitHub OIDC roles.
3. Configure GitHub variables, secrets, environment protection, and required
   checks.
4. Select the exact Ubuntu source AMI, archive snapshot, package pins, and SSM
   Agent revision; then build the gateway AMI and run an SSM-only boot test.
5. Open a reviewed infrastructure PR, apply `network`, then `gateway`, then
   `dns`, and complete the gateway bootstrap-to-runtime role transition.
6. Implement the console device enrollment state machine and browser setup
   client against the checked-in gateway delivery/acknowledgement schemas.
