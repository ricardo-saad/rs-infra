# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Structure

`rs-infra` is Infrastructure as Code for RS Platform: Terraform for AWS and Cloudflare, Packer-built immutable machine images, a Talos/Kubernetes node provisioner, operator-only secret tools, and a one-time Argo CD bootstrap. It provisions infrastructure and deploys no application workloads.

**Status:** early-stage. `terraform/gateway/`, `terraform/bootstrap/`, and `images/gateway/` contain real implementation; neither has been applied to a real account. Every other `terraform/` stack is a scaffold (variables/outputs/provider wiring but no resources). `argocd/`, `provisioner/`, `tools/secret/`, `tools/talos-seed/`, and `images/home/` are README-only placeholders with no code yet. Per-stack cloud plan/apply and gateway AMI build CI are scaffolded but cannot run until an operator applies `terraform/bootstrap/` (see its README) and configures the resulting GitHub OIDC identities, state/plan buckets, build subnet/profile, provider locks, and image pins.

### Key Directories

- `terraform/bootstrap/` — the versioned S3 state backend (native locking, no DynamoDB table), the private Object-Lock-protected plan bucket, the GitHub OIDC provider, the `rs-infra-plan`/`rs-infra-apply`/`rs-infra-image-build` CI roles, and the build-only SSM instance profile. Implemented, but operator-applied by design: it is deliberately excluded from `terraform-plan.sh`/`terraform-apply.sh`'s `network|gateway|cluster|dns` stack allowlist and has no GitHub Actions workflow of its own, so it cannot depend on the CI identity it creates.
- `terraform/network/` — the single-AZ gateway VPC: public gateway subnet, private Talos subnet, private game subnet, route tables, IGW, S3 gateway endpoint. Implemented.
- `terraform/cluster/` — reserved for the AWS-local Talos provisioner, three logical node-slot envelopes, private DNS, and service-account federation. Scaffold only.
- `terraform/gateway/` — the replaceable EC2 hybrid gateway: instance, Elastic IP, WireGuard security group rules, IAM bootstrap/runtime roles, KMS key, two Secrets Manager containers, CloudWatch alarms. The only fully implemented AWS stack.
- `terraform/dns/` — Cloudflare zone/records/tunnel. Only the WireGuard A records (DNS-only, unproxied) are implemented; other zone resources are scaffold-only.
- `images/gateway/` — Packer build for the disposable ARM64 EC2 gateway appliance (WireGuard + AdGuard + nftables + a Python reconciler). Implemented and the most detailed part of the repo.
- `images/home/` — reserved for the signed Ubuntu Core image for home nodes. README placeholder only.
- `provisioner/` — reserved for the AWS-local Talos node lifecycle state machine. README placeholder only.
- `tools/secret/` — reserved for the operator-only Parameter Store create/rotate tool. README placeholder only.
- `tools/talos-seed/` — reserved for the one-time in-memory Talos recovery-bundle creation tool. README placeholder only.
- `argocd/bootstrap/` — reserved for the one-time Argo CD install and root application. README placeholder only.
- `.github/workflows/static-validation.yml` — fork-safe checks for every pull request.
- `.github/workflows/terraform-{network,gateway,cluster,dns}.yml` — path-filtered, credential-free callers for the reusable Terraform workflows.
- `.github/workflows/_reusable-terraform-{plan,apply}.yml` — the only Terraform workflows allowed to assume AWS roles; their exact `job_workflow_ref` paths are IAM-bound.
- `.github/workflows/image-gateway.yml` — path-filtered, fork-safe image caller; `_reusable-image-gateway-build.yml` owns the OIDC-backed build.

### Architecture Notes

- Every directory under `terraform/` is an **independent Terraform stack** with its own state (`backend "s3" {}` block, deliberately left partial — configured only at `terraform init` time, never hardcoded).
- Stacks consume each other's outputs as plain variables, not remote-state data sources in code shown so far: `terraform/gateway` takes `vpc_id`, `public_subnet_id`, `private_route_table_id`, `private_subnet_cidr`, `game_route_table_id` as inputs (values exported by `terraform/network`), and `terraform/dns` takes `gateway_elastic_ip` as an input (exported by `terraform/gateway`). Wire these by hand via tfvars/CI plan wiring, not by adding `terraform_remote_state` blocks unless asked.
- Implementation order per `README.md`: bootstrap (state/OIDC) → network/cluster/gateway/dns foundations → gateway + home images → gateway secret bootstrap → Talos seed → Talos genesis via provisioner → workload secrets via the secret tool → one-time Argo CD bootstrap (ArgoCD then hands off to `rs-cloud` for ongoing workload reconciliation).
- The gateway is a three-interface WireGuard hybrid NAT + DNS appliance: `wg-users` (51820, human egress + optional game access), `wg-personal` (51822, operator-only private access), `wg-nodes` (51823, enrolled home nodes). This exact set is load-bearing — tests and Terraform both assert there is no `wg-cluster` or `wg-egress` interface. Do not add a fourth interface without updating `terraform/gateway/locals.tf`, `images/gateway/rootfs/usr/lib/rs-gateway/contract.py`, and `images/gateway/tests/test_contract.py` together.
- The gateway has two IAM postures gated by `gateway_profile_mode` (`bootstrap` | `runtime`, default `runtime`): bootstrap can write the two recovery secrets once; runtime can only read/decrypt them. Promotion from bootstrap to runtime is a Terraform variable flip that replaces the instance and profile — Terraform never manages a secret *value*, only the container/KMS/IAM.
- Cross-repo boundaries (`OWNERSHIP.md`): Kubernetes workload manifests live in `rs-cloud`; application source lives in its own repo; edge desired state lives in `rs-edge`; stable architecture/ADRs/cross-repo runbooks live in the private `rs-platform` repo. This repo must never contain secret values/versions, generated keys, Talos PKI, WireGuard key material (including in state), or private inventory.

## Quick Start

There is no "run the app" here — the fastest way to prove a change is sound is to reproduce what CI does, locally, for the stack(s) or component you touched:

1. `terraform fmt -recursive terraform` — fix formatting before anything else.
2. `terraform -chdir=terraform/<stack> init -backend=false -input=false && terraform -chdir=terraform/<stack> validate -no-color` — for every stack you touched.
3. `tflint --chdir=terraform/<stack> --format=compact` — needs tflint `v0.64.0` installed locally to match CI exactly.
4. If you changed `variables.tf`/`outputs.tf`/resources in a stack, regenerate its README's `terraform-docs` block with `terraform-docs markdown table --indent 2 --output-file README.md --output-mode inject terraform/<stack>`, or expect CI to fail the diff.
5. If you touched `images/gateway/`, run `python3 -m unittest discover -s images/gateway/tests -v` — this needs only stdlib Python, no AWS credentials or Packer.

## Where Things Go

- **New Terraform stack** → new top-level directory under `terraform/`, following the file layout in "Terraform Conventions" below. Add it to `terraform/<name>/README.md` with `<!-- BEGIN_TF_DOCS -->`/`<!-- END_TF_DOCS -->` markers (terraform-docs injects the rest) and a `terraform.tfvars.example` if the stack takes non-trivial inputs.
- **New variable/output on an existing stack** → `variables.tf` / `outputs.tf` in that stack directory, alphabetized by convention (see any existing file). Tag-related variables (`project`, `environment`, `owner`, `cost_center`, `additional_tags`) already exist in every stack — reuse them, don't reinvent tagging.
- **New AWS resource** → the most specific existing `.tf` file by concern (e.g. `iam.tf` for roles/policies, `network.tf` for routes/SGs/EIPs, `secrets.tf` for KMS/Secrets Manager, `observability.tf` for CloudWatch, `compute.tf` for the instance). Only `terraform/gateway/` currently needs this split; smaller stacks keep everything in `main.tf` until they grow enough to justify splitting.
- **New shared computed value** → `locals.tf` (only `terraform/gateway/` has one so far; other stacks keep their one `required_tags` local inline in `variables.tf`).
- **New gateway runtime behavior** (a script that runs on the live instance) → `images/gateway/rootfs/usr/lib/rs-gateway/*.py` or `*.sh`, mirroring where it lands on the real filesystem (`rootfs/` is copied to `/` verbatim by `scripts/install.sh`).
- **New systemd unit** → `images/gateway/rootfs/etc/systemd/system/rs-gateway-*.{service,path,timer,target}`. Every gateway unit is named `rs-gateway-*`; never introduce an unprefixed unit name.
- **New/changed on-disk contract format** (peer manifest, game target, etc.) → add or version the JSON Schema in `images/gateway/rootfs/usr/lib/rs-gateway/schemas/`, keep `additionalProperties: false`, and add a matching case to `images/gateway/tests/test_contract.py`. The schema and the Python validators in `contract.py`/`gateway_reconciler.py`/`secret_loader.py` must stay in lockstep — schema is documentation, Python is the actual enforcement at runtime.
- **New non-secret runtime input for the gateway** → add the key to `images/gateway/runtime.env.example` (the allowlist) and to `ALLOWED_ENV` in `secret_loader.py`, and template it through `terraform/gateway/templates/runtime-env.sh.tftpl` + `compute.tf` user_data. Never add a value that could be secret to this path — it is written by Terraform user data, which must stay secret-free.
- **New per-directory README** → required for any placeholder directory (`argocd/bootstrap/`, `images/home/`, `provisioner/`, `tools/secret/`, `tools/talos-seed/`) — CI's `repository` job fails if these five are missing or empty (`static-validation.yml`). Terraform stack READMEs are generated/injected by `terraform-docs`; only hand-edit the prose above the `BEGIN_TF_DOCS` marker.
- **New tool** (operator CLI, one-off script) → `tools/<name>/`, with its own README describing what it must and must not do (see `tools/secret/README.md` and `tools/talos-seed/README.md` for the register of hard constraints these must satisfy before any code lands).
- **Docs about stable cross-repo architecture, ADRs, or runbooks** → do NOT put these here; they belong in the private `rs-platform` repo per `OWNERSHIP.md`. This repo only holds repository-local operational documentation needed to change or recover its own components.

## Terraform Conventions

- File layout within a stack, by convention observed across all five stacks:
  - `versions.tf` — `terraform { required_version, backend "s3" {}, required_providers }`. Backend block is always empty/partial; never hardcode a bucket/key/region here.
  - `providers.tf` — provider blocks (`default_tags` sourced from `local.required_tags`) plus any account/partition data sources the stack needs.
  - `variables.tf` — all inputs, including the standard tagging variables; validation blocks (`validation { condition ... }`) are used liberally for region pinning, CIDR shape, ID shape, and enum-like strings — follow this pattern for new variables that have an obviously-wrong-value class.
  - `main.tf` — resources, for scaffold stacks currently just a comment explaining why nothing exists yet.
  - `outputs.tf` — outputs, every scaffold stack exports at minimum `output "stack" { value = "<stack-name>" }` as a stable placeholder identifier.
  - `locals.tf` — only present once a stack has enough derived values to warrant it (currently only `terraform/gateway`); otherwise `required_tags`/`name_prefix` locals live inline at the bottom of `variables.tf`.
  - Once a stack grows past a handful of resources, split `main.tf` by concern (`compute.tf`, `network.tf`, `iam.tf`, `secrets.tf`, `observability.tf`) as `terraform/gateway/` does — do this instead of letting `main.tf` sprawl.
- Naming: resource local names are singular and describe the thing, not the type (`aws_instance.gateway`, `aws_vpc.platform`, `aws_secretsmanager_secret.wireguard`); AWS-side `Name` tags and physical names use `local.name_prefix` (`"${var.project}-${var.environment}"`, or `-gateway` suffixed in the gateway stack) so resources are traceable to project/environment by name alone.
- Tagging: every stack merges the same five tags via `local.required_tags`: `Project`, `Environment`, `Owner`, `ManagedBy = "Terraform"`, `CostCenter`, plus caller-supplied `additional_tags`. Apply this via `provider "aws" { default_tags { tags = local.required_tags } }`, not per-resource `tags` blocks, except for the resource-specific `Name` (and sometimes `Tier`/`Component`) tags.
- Version pinning: `terraform >= 1.7.0` in every stack's `versions.tf`; the pinned CLI version for CI/local dev is `.terraform-version` = `1.15.8` (keep these in sync — CI's `static-validation.yml` fails if `.terraform-version` doesn't match its own `TERRAFORM_VERSION` env var). Providers are `~>` pinned to major: `hashicorp/aws ~> 6.0`, `cloudflare/cloudflare ~> 5.0`.
- Backend/state: one S3 backend, one state per stack, backend config supplied only at `init` time (`-backend-config=...`), never committed. State object keys for the four deployable stacks are the `state_object_keys` input to `terraform/bootstrap/` (one authoritative source, echoed back as its per-stack `*_state_key` outputs) — don't invent a separate bucket/key convention elsewhere.
- Secrets: Terraform may create secret **containers** (Secrets Manager secret, KMS key, IAM policy, SSM path permission) and never a secret **version** or value. No `aws_secretsmanager_secret_version`, no rendered Talos machine config, no key material, anywhere in `.tf` files or in state. `terraform.tfvars` (the real, non-example file) must never be committed — only `terraform.tfvars.example` with placeholder/documentation-only values (`.gitignore` doesn't explicitly list `terraform.tfvars`, so be deliberate about never adding it).
- `terraform.tfvars.example` is required for any stack whose variables aren't self-evident from defaults (`network`, `dns`, `gateway` all have one); every value in it must be a documentation-only placeholder, never a real deployed ID.

## Gateway Image Conventions

- Build tool: Packer (`packer { required_version >= 1.10.0 }`), single source `amazon-ebs.gateway`, official Canonical Ubuntu Server 26.04 LTS ARM64 (`t4g.small`), defined in `images/gateway/gateway.pkr.hcl`.
- Every build input is an explicit Packer variable with no default for anything security/version relevant (source AMI, package versions, AdGuard archive URL+SHA256, apt repository line) — the values are not yet recorded anywhere, so `scripts/build.sh` requires ~20 `RS_GATEWAY_*`/`PACKER_*` env vars and fails closed if any are unset. Follow this pattern for any new build input: no silent defaults for anything that affects the supply chain.
- `scripts/build.sh` also verifies Canonical owner `099720109477`, the Ubuntu 26.04 ARM64 image name, architecture, immutable ID, explicit build subnet, and dedicated builder profile before invoking Packer, and pins the installed Packer and Session Manager plugin versions. The temporary SSH communicator is tunneled through SSM Session Manager with no inbound build port. CI may pass only the Terraform-managed `rs-infra-image-builder` profile; do not restore Packer's temporary IAM-role creation.
- `scripts/install.sh` (runs as root inside the Packer builder via `provisioner "shell"`) installs pinned apt packages from a single pinned repository line, downloads+SHA256-verifies the AdGuard Home archive, verifies and holds the approved SSM Agent snap revision, copies `rootfs/` onto `/` with `cp -a`, sets exact permissions (`0755` on `*.py`/`*.sh`, `0644` on schemas, `0600` on `runtime.env`), enables `rs-gateway.target` while disabling `rs-gateway-bootstrap.service` and the stock `wg-quick@*` units, and purges OpenSSH before the final AMI snapshot. Runtime administration is SSM-only; never add an EC2 key pair, TCP/22 security-group rule, host-firewall SSH allow, or OpenSSH server to the final image.
- `rootfs/` mirrors the target filesystem exactly and is copied verbatim — a file at `images/gateway/rootfs/etc/systemd/system/foo.service` lands at `/etc/systemd/system/foo.service` on the built image. Keep this mapping literal; don't add indirection.
  - `rootfs/etc/rs-gateway/` — non-secret runtime config: `runtime.env` (deliberately invalid/empty defaults that Terraform user data must overwrite), `game-target.json.example`.
  - `rootfs/etc/sysctl.d/90-rs-gateway.conf` — IP forwarding + redirect hardening sysctls.
  - `rootfs/etc/systemd/system/` — all `rs-gateway-*` units (see naming rule below).
  - `rootfs/usr/lib/rs-gateway/` — the actual implementation: Python modules (`contract.py`, `secret_loader.py`, `bootstrap.py`, `gateway_reconciler.py`, `render_nftables.py`, `publish-heartbeat.py`) plus POSIX shell helpers (`wireguard-up.sh`, `wireguard-down.sh`, `reconcile-all.sh`, `restore-applied.sh`) and `schemas/*.json`.
- Python module conventions (all files under `rootfs/usr/lib/rs-gateway/`):
  - `#!/usr/bin/env python3` + `from __future__ import annotations`, stdlib only (no third-party deps — the image installs `python3` from apt with nothing else).
  - `contract.py` is the shared, secret-free source of truth for the three `INTERFACES` (port, subnet, gateway IP), regex validators, and the `ContractError` exception. Every other module imports from it rather than redefining ports/subnets/regexes.
  - All subprocess calls go through a local `run(command, *, stdin=None)` helper that passes secrets via **stdin only**, never argv or captured stdout — see `secret_loader.hash_adguard_credentials` and `bootstrap.put_first_version`, and the tests in `test_contract.py` that specifically assert secret material never appears in `command` or JSON-serialized output.
  - Writes to disk use an atomic temp-file-then-`os.replace` helper (`atomic_write` / `atomic_persist`) with `os.fchmod` set before any write and `os.fsync` before rename. Follow this pattern for any new file the gateway writes at runtime.
  - Fail-closed by default: `secret_loader.py` raises before starting networking if a secret is missing/malformed; only telemetry (`publish_metric_safely`) swallows exceptions, and only because "telemetry cannot turn a specific failure into a different failure."
- Systemd unit naming: every unit is `rs-gateway-<purpose>.{service,path,timer,target}` (or the templated `rs-gateway-wireguard@.service`). `rs-gateway.target` is the single enabled entry point; individual units are `Requires=`/`Before=`/`After=`-ordered relative to it and to `cloud-final.service` so Terraform user data has time to replace `runtime.env` before secrets are loaded. Never enable a unit outside this target's dependency graph without a reason documented in the unit file, matching the existing style of `[Unit]` comments.
- JSON Schema ↔ contract-test relationship: `schemas/peer-manifest.schema.json` and `schemas/game-target.schema.json` are the documented/human-facing contract (`additionalProperties: false` is mandatory and is itself asserted by `test_contract.py::test_json_schemas_parse_and_forbid_unknown_properties`); the actual runtime enforcement is hand-written Python in `gateway_reconciler.py` (`validate_manifest`, `game_target_for`). When you change one, change the other and add/adjust a case in `images/gateway/tests/test_contract.py` — the schema and the validator must never silently drift apart.
- `runtime.env` / secret-loading pattern: Terraform user data (`terraform/gateway/templates/runtime-env.sh.tftpl`) writes only the seven allowlisted non-secret identifiers (region, two Secrets Manager IDs, SSM prefix, CloudWatch namespace, WAN interface, build version) to `/etc/rs-gateway/runtime.env`, base64-encoded in transit and written atomically with `umask 077`. `rs-gateway-secret-loader.service` then reads that file, fetches `AWSCURRENT` from both Secrets Manager containers, validates shape in memory, derives config under `/run/rs-gateway/` (tmpfs, never `/var`), republishes public keys to SSM, and only then lets WireGuard/nftables/AdGuard/reconcile units start. A missing or invalid secret leaves the whole target down — there is no degraded-but-up mode.

## Commands

Terraform, per stack (run from the stack directory or with `-chdir`):

```sh
terraform -chdir=terraform/<stack> init -backend=false -input=false   # CI mode: no backend
terraform -chdir=terraform/<stack> init                               # local: needs -backend-config
terraform -chdir=terraform/<stack> validate -no-color
```

Packer, gateway image (from `images/gateway/`, all `RS_GATEWAY_*`/`PACKER_AMAZON_PLUGIN_VERSION`/`RS_GATEWAY_PACKER_VERSION` env vars required — see `images/gateway/README.md` for the full list):

```sh
./scripts/build.sh          # validates env, verifies source AMI, installs the amazon plugin, runs packer build
```

There is no `terraform plan`/`apply` CI automation for any stack yet — the four deployable stacks' backends are unconfigured until an operator applies `terraform/bootstrap/`, and CI has no cloud credentials regardless. `terraform/bootstrap/` itself is the one exception: it is meant to be planned/applied locally by a documented operator identity, per its own README's bootstrap sequence — don't do this against a real account without that context.

## Testing

The only executable test suite in the repo today is `images/gateway/tests/test_contract.py` (stdlib `unittest`, no external dependencies):

```sh
python3 -m unittest discover -s images/gateway/tests -v
```

It covers: the fixed three-interface contract (`wg-users`/`wg-personal`/`wg-nodes`, exact ports/subnets), peer-manifest validation (unknown fields, wrong interface, out-of-subnet/reserved addresses, duplicate identity, malformed keys/timestamps, stale/repeated generations, `wg-users` permission rules), the rendered nftables baseline (default-drop, exact public ports, per-role forwarding rules), that secrets never leak into subprocess argv/output, and that every JSON Schema under `rootfs/usr/lib/rs-gateway/schemas/` forbids unknown properties. When you touch `contract.py`, `secret_loader.py`, `bootstrap.py`, `gateway_reconciler.py`, or `render_nftables.py`, extend this suite rather than hand-verifying behavior.

Shell syntax check on every gateway script (what CI runs before the contract tests):

```sh
find images/gateway -type f -name '*.sh' -print0 | xargs -0 -r -n 20 sh -n
```

Terraform stacks have no unit tests; `terraform validate` plus `tflint` plus `trivy config` (see Linting below) are the only current correctness signal. Provisioner tests, secret-tool safety tests, and Talos-seed safety tests are all listed in `README.md` as deferred gates — there is nothing to run for those directories yet because there is no code there yet.

## Linting & Formatting

```sh
terraform fmt -check -diff -recursive terraform     # CI's exact formatting check, whole tree
tflint --chdir=terraform/<stack> --format=compact    # v0.64.0, run per stack
```

- `.editorconfig` governs whitespace repo-wide: 2-space indent, LF, UTF-8, trailing newline, trailing-whitespace trimmed everywhere except Markdown (`*.md` keeps trailing whitespace since it can be meaningful — hard line breaks).
- `trivy config` scans the whole repo at `HIGH,CRITICAL` severity; there is no local-only trivy command documented here beyond installing `trivy` `v0.72.0` and running `trivy config --severity HIGH,CRITICAL --trivyignores .trivyignore.yaml .`. Any new suppressed finding must go in `.trivyignore.yaml` with an `id`, `paths`, `expired_at`, and an owner-attributed `statement` — follow the existing `AWS-0104` entry's shape.
- No linter is configured for the gateway's Python or shell beyond `sh -n` syntax checking and the contract tests themselves — there is no `ruff`/`black`/`shellcheck` wired into CI, so keep new Python/shell consistent with the stdlib-only, fail-closed, atomic-write style already in `rootfs/usr/lib/rs-gateway/` by hand.

## CI / Static Validation

`.github/workflows/static-validation.yml` runs on every pull request (unfiltered — any target branch, so stacked branches are covered). It holds `permissions: contents: read` only — no OIDC, no provider credentials, no Terraform state, no Talos/Kubernetes access — so it is safe on forked PRs. Jobs:

- **repository** — `.terraform-version` must equal the workflow's own `TERRAFORM_VERSION` (currently `1.15.8`); `renovate.json` must be valid JSON; the five placeholder READMEs (`argocd/bootstrap/README.md`, `images/home/README.md`, `provisioner/README.md`, `tools/secret/README.md`, `tools/talos-seed/README.md`) must exist and be non-empty; every `uses:` step in `.github/workflows/` must be pinned to a full 40-char commit SHA (a `ripgrep` PCRE2 check fails the job otherwise).
- **actionlint** — lints all workflow YAML via `reviewdog/action-actionlint`.
- **secrets (gitleaks)** — full-history scan via `gitleaks/gitleaks-action`, pinned to `GITLEAKS_VERSION: "8.28.0"`.
- **terraform** — `terraform fmt -check -diff -recursive terraform`; for every directory under `terraform/` that contains `*.tf`, `terraform init -backend=false` + `terraform validate`; `tflint` (`v0.64.0`) per stack; `terraform-docs` drift check (`find-dir: terraform`, `output-method: inject`, `output-file: README.md`, `fail-on-diff: true`) — **if you add/remove/rename a variable, output, or resource, you must regenerate the stack's README block or CI fails.**
- **configuration-security (trivy)** — `trivy config` over the whole repo at `HIGH,CRITICAL`, using `.trivyignore.yaml` for accepted exceptions (currently one: `AWS-0104` on `terraform/gateway/network.tf`'s unrestricted egress, owned by `@ricardo-saad`, expiring `2027-01-27` — re-justify or fix before then, don't just re-extend blindly).
- **gateway-image-contract** — `sh -n` syntax-checks every `images/gateway/**/*.sh`, then runs `python3 -m unittest discover -s images/gateway/tests -v`.

All third-party Actions are pinned to commit SHAs already (Renovate, per `renovate.json`, is configured to keep them updated with `pinDigests: true`, 3-day minimum release age, Monday-morning batched PRs). Cloud plan/apply workflows exist per deployable stack and fail closed until the prerequisites in `README.md` are configured. The gateway image workflow builds and records a candidate AMI but does not yet perform the SSM boot/acceptance test required for promotion. Infracost, provisioner tests, and secret/seed-tool safety tests are explicitly **not yet implemented** — see the "remaining gates" table in `README.md`.

## Security & Secrets

- Never commit: `.env`/`.env.*` (except `.env.example`), `kubeconfig*`, `talosconfig*`, `*.key`/`*.pem`/`*.p12`/`*.pfx`, Terraform state/plan files (`*.tfstate*`, `*.tfplan`, `*.plan`), `.terraform/` — all covered by `.gitignore`, but treat it as a floor, not a guarantee; gitleaks in CI is the actual backstop.
- Terraform's hard rule (`OWNERSHIP.md`, `README.md`): create secret **containers** (Secrets Manager secret objects, KMS keys, IAM policies, SSM path grants) — never a secret **version**, never rendered Talos machine configuration, never key material, never in state.
- The gateway's fail-closed loader (`secret_loader.py`) is the only thing that reads secret values, and only into `/run/rs-gateway` (tmpfs); it never logs a secret value and only emits value-free `SecretLoadFailure`/`PublicKeyPublicationFailure` CloudWatch metrics on failure.
- If you find a committed secret: per `SECURITY.md`, treat it as compromised even if since deleted — report privately via GitHub Security Advisory, don't open a public issue/PR, and know that rewriting history alone is not sufficient remediation (the credential must be revoked/rotated).
- Vulnerability reports go through `SECURITY.md`'s private GitHub Security Advisory process, not public issues; general hardening suggestions without concrete impact can be public issues.
- Identity model (`README.md`): `rs-infra-plan` has read-only provider/state access plus narrowly scoped private-plan writes and is assumable only from trusted branches (forks get static validation only); `rs-infra-apply` is mutating, assumable only from protected `main` through the `apply` environment; `rs-infra-image-build` is a separate secret-blind AMI lifecycle role that may pass only the dedicated SSM builder profile from the exact image workflow; AWS trust binds immutable GitHub owner/repo IDs, audience, workflow purpose, and exact ref/environment; the Talos-seed role is MFA-backed, one-time-write, then disabled; Cloudflare has two zone-scoped, expiring token exceptions—read-only for trusted plans and write-only in the `apply` environment.
- `.trivyignore.yaml` exceptions require an owner, a rationale, and an `expired_at` date — follow this format for any new exception, don't add a bare ID.

## Commit & PR Guidelines

This repository follows [Conventional Commits](https://www.conventionalcommits.org/). This is mandatory for every commit and every PR title from the first source-bearing commit onward. The handful of pre-source commits (`README cleanup`, `stage 1 exit critiera completion`, …) predate the convention — do not use them as a template, and do not rewrite them.

### Format

`<type>(<scope>): <description>`

- Description starts lowercase, imperative mood, no trailing period, ≤ 72 chars on the subject line.
- Scope is optional but expected whenever the change is confined to one component. Omit it for genuinely repo-wide changes.
- Breaking changes: append `!` after the scope (`feat(gateway)!: ...`) **and** add a `BREAKING CHANGE:` footer. For this repo, "breaking" includes anything that forces replacement of a live resource, invalidates existing state, changes an on-disk contract format, or requires an operator action to roll forward — say which in the footer.

### Types

| Type | Use for |
|---|---|
| `feat` | new infrastructure, resources, runtime capability |
| `fix` | corrections to broken/incorrect infrastructure or runtime behavior, including security fixes |
| `refactor` | restructuring with no change to the resulting infrastructure or behavior |
| `docs` | READMEs, `CLAUDE.md`, `OWNERSHIP.md`, `SECURITY.md`, terraform-docs regeneration |
| `test` | `images/gateway/tests/`, future component test suites |
| `ci` | `.github/workflows/`, `.trivyignore.yaml`, `renovate.json` |
| `build` | Packer build definition, `scripts/build.sh`, `scripts/install.sh`, version/tool pins |
| `chore` | housekeeping with no production effect (`.editorconfig`, `.gitignore`, dependency bumps) |
| `revert` | reverting a previous commit; reference its hash in the body |

### Scopes

Derived from the directory the change lives in:

- Terraform stacks — `bootstrap`, `network`, `cluster`, `gateway`, `dns` (bare `gateway` always means `terraform/gateway/`)
- Machine images — `image-gateway`, `image-home` (always prefixed, to disambiguate from the Terraform stacks)
- Everything else — `argocd`, `provisioner`, `secret`, `talos-seed`, `ci`, `repo`

Pick the single most relevant scope if a change touches several; omit the scope entirely rather than inventing a compound one.

Examples:

```
feat(network): add private game subnet and route table
feat(image-gateway): publish wireguard public keys to ssm on load
fix(gateway): restrict egress security group to wireguard ports
build(image-gateway): pin adguard archive sha256
ci: pin all third-party actions to commit shas
docs(dns): regenerate terraform-docs block
feat(gateway)!: promote instance profile to runtime mode

BREAKING CHANGE: flipping gateway_profile_mode replaces the EC2 instance
and its IAM profile. Bootstrap-mode secret writes are no longer possible
after this lands; write both recovery secrets before applying.
```

### Review contract

- All persistent changes go through pull requests; the accountable owner is `@ricardo-saad` (`OWNERSHIP.md`, `.github/CODEOWNERS` — a single blanket `* @ricardo-saad` plus explicit paths for governance and each privileged directory).
- The PR title must itself be a valid Conventional Commit line — it is what a squashed merge records.
- Changes to identity, trust policies, state backends, encryption, secret access, network boundaries, protected environments, workflow permissions, or ownership itself are "privileged changes" — treat them with extra care and make sure the blast radius/rollback path is clear in the PR description.
- A change is "ready to merge" per the ownership contract only when: owner/blast-radius/rollback path are clear, generated plans/artifacts are traceable to the reviewed commit, required static checks and affected component tests pass, Code Owners approve, and operator documentation is updated when operational/recovery behavior changes.
- Nothing in CI validates commit or PR-title format today — the convention is enforced by review only.

## Additional Resources

- Terraform CLI pin: `.terraform-version` = `1.15.8` (must match `TERRAFORM_VERSION` in `.github/workflows/static-validation.yml`).
- Terraform provider pins: `hashicorp/aws ~> 6.0`, `cloudflare/cloudflare ~> 5.0`; `terraform >= 1.7.0` required in every stack.
- tflint pin (CI): `v0.64.0`. terraform-docs action pin: `v1.4.1`. trivy-action pin: `v0.36.0` (trivy `v0.72.0`). gitleaks pin: `8.28.0`.
- Packer: `packer >= 1.10.0` required by `images/gateway/gateway.pkr.hcl`; exact Packer CLI version and `hashicorp/amazon` plugin version are supplied at build time via `RS_GATEWAY_PACKER_VERSION`/`PACKER_AMAZON_PLUGIN_VERSION` env vars, not pinned in-repo (values not yet agreed upstream).
- Renovate config (`renovate.json`): groups GitHub Actions / Terraform / Packer+Dockerfile updates separately, pins digests, 3-day minimum release age, runs before 6am Monday Asia/Beirut.
- Ownership and review routing: `OWNERSHIP.md` (mission/boundaries/change contract) and `.github/CODEOWNERS` (routing — branch protection must still require the review, CODEOWNERS alone doesn't enforce it).
- Security process: `SECURITY.md`.
- License: Apache License 2.0 (`LICENSE`).
- Per-directory READMEs are the authoritative detail for each stack/component: `terraform/{bootstrap,network,dns,cluster,gateway}/README.md`, `images/gateway/README.md`, `images/home/README.md`, `argocd/bootstrap/README.md`, `provisioner/README.md`, `tools/secret/README.md`, `tools/talos-seed/README.md`.
