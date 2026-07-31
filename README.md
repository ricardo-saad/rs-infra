# `RS Platform · Infrastructure`

Infrastructure as code for RS Platform.

> **Status:** Initial repository scaffold complete. The EC2 gateway Terraform,
> immutable-image source, and the bootstrap state/OIDC/CI-role stack are
> implemented but have not been applied to a real account. All other
> components remain contract-only scaffolds. Per-stack cloud plan and apply
> workflows are scaffolded but remain inactive until bootstrap has been
> applied by an operator and the resulting GitHub variables and secrets
> described below are configured.

Repository scope, accountability, review duties, and cross-repository
boundaries are defined in the [ownership contract](OWNERSHIP.md). Security
issues must follow the private reporting process in [SECURITY.md](SECURITY.md).

## Purpose

This repository owns:

- Terraform for AWS and Cloudflare, using a single S3 state backend;
- AWS IAM, KMS, secret containers, and workload-secret access paths;
- the private Talos cluster envelope, AWS-local node provisioner, and
  service-account federation;
- signed machine images for the EC2 gateway and Ubuntu Core home nodes;
- operator tools for the one-time Talos recovery seed and workload-secret
  rotation; and
- the one-time Argo CD bootstrap.

It provisions infrastructure and deploys no application workloads. Stable
platform architecture, ADRs, and cross-repository runbooks remain in the
private `rs-platform` repository.

## Boundaries

This repository never contains:

- Kubernetes workload manifests; those belong in `rs-cloud`;
- application source; that belongs in the relevant application repository;
- edge desired state; that belongs in `rs-edge`;
- secret values or versions, generated keys, Talos PKI, or WireGuard key
  material, including in Terraform state; or
- private inventory or reusable authority.

Terraform creates secret containers, policies, KMS keys, and references only.
It never creates a secret version, renders Talos machine configuration, or
places secret material in state.

## Repository layout

```text
rs-infra/
├── terraform/
│   ├── bootstrap/         # State backend, OIDC providers, and CI roles
│   ├── network/           # VPC, subnets, routing, and firewall rules
│   ├── cluster/           # Provisioner, node slots, DNS, and federation
│   ├── gateway/           # Gateway host, NAT, secret metadata, and IAM
│   └── dns/               # Cloudflare zone, records, and tunnel config
├── images/
│   ├── gateway/           # Packer-built, versioned gateway image
│   └── home/              # Ubuntu Core model, image build, and QEMU tests
├── provisioner/           # Talos node lifecycle state machine
├── tools/
│   ├── secret/            # Operator-only Parameter Store create/rotate tool
│   └── talos-seed/        # One-time in-memory recovery-bundle creation
├── argocd/
│   └── bootstrap/         # One-time Argo CD install and root application
├── .github/
│   ├── workflows/         # Checks, plans, applies, and image builds
│   └── CODEOWNERS
├── LICENSE
├── SECURITY.md
└── README.md
```

Each directory under `terraform/` is an independent stack with its own state.
Backend coordinates remain external GitHub variables and are passed to the
partial S3 backend during `terraform init`; no bucket, region, or key is
hard-coded in a stack.

## Identity model

- `rs-infra-plan` has read-only provider access and state read access. It is
  assumable only by trusted branches in this repository. Fork pull requests
  receive static validation only.
- `rs-infra-apply` has mutating provider access. It is assumable only from
  protected `main` through the `apply` environment.
- `rs-infra-image-build` can create gateway AMI candidates and pass only the
  build-only `rs-infra-image-builder` instance profile. It is assumable only
  by trusted same-repository pull requests changing the gateway image.
- AWS trust binds immutable GitHub owner and repository IDs, audience,
  workflow purpose, and the exact ref or environment.
- CI has no access to the Kubernetes or Talos APIs. A bounded AWS-local
  provisioner performs ordinary Talos genesis, replacement, and upgrades.
- The operator-only Talos seed role is MFA-backed, can write one exact recovery
  secret for initial genesis, and is disabled after verification.
- Cloudflare uses two zone-scoped, expiring token exceptions: a read-only token
  for trusted DNS plans and a write token held in the `apply` environment.
  Both are supplied through `CLOUDFLARE_API_TOKEN`, never as Terraform input.
- Image publication uses a dedicated role limited to image and artifact
  publication.

## CI gates

The static pull-request workflow is fork-safe:

| Check | Trigger | Status |
|---|---|---|
| Repository scaffold and immutable action pins | Pull request | Implemented |
| `terraform fmt -check` | Pull request | Implemented |
| Terraform validation per stack, without backend | Pull request | Implemented |
| `tflint` | Pull request | Implemented |
| `trivy config` | Pull request | Implemented |
| `terraform-docs` drift | Pull request | Implemented |
| `gitleaks` | Pull request | Implemented |
| `actionlint` | Pull request | Implemented |
| Gateway image contract unit tests | Pull request | Implemented |
| Gateway AMI build | Trusted same-repository pull request changing `images/gateway/` | Implemented; configuration required |
| Cloud plan per changed stack | Trusted same-repository pull request | Implemented; configuration required |
| Apply exact reviewed plan | Merge to `main`, through `apply` | Implemented; configuration required |

The remaining gates are deferred, not silently omitted:

| Check | Intended trigger |
|---|---|
| Infracost diff | Pull request |
| Gateway AMI SSM boot and acceptance test | Gateway image candidate |
| Provisioner tests | Changes under `provisioner/` |
| Secret-tool safety tests | Changes under `tools/secret/` |
| Talos-seed safety tests | Changes under `tools/talos-seed/` |
| Signed image publication | Tag |

Third-party actions are pinned to full commit SHAs. The static workflow grants
only `contents: read`; it has no OIDC, provider, state, Talos, or Kubernetes
access. Each deployment workflow is isolated to one stack. A trusted
same-repository pull request assumes the plan role and stores the complete plan
as an SSE-KMS-encrypted private S3 object. GitHub receives only aggregate
change counts and the plan digest. On merge, the protected `apply` environment
assumes the apply role and consumes that exact plan only after verifying its
digest, PR head, stack tree, state key, and Terraform version. Untrusted forks
never receive an OIDC token, provider credentials, secrets, or state access.
Trusted gateway-image pull requests assume a separate, secret-blind image role
and publish the Packer manifest as a workflow artifact.

### Cloud workflow configuration

Create these repository variables before enabling the deployment and image
workflows:

| Variable | Purpose |
|---|---|
| `AWS_REGION` | Region containing the backend and AWS resources |
| `AWS_ACCOUNT_ID` | Expected account for OIDC role assumption |
| `TF_PLAN_ROLE_ARN` | Trusted-PR planning role |
| `TF_APPLY_ROLE_ARN` | Protected-environment apply role |
| `IMAGE_BUILD_ROLE_ARN` | Trusted-PR gateway AMI build role |
| `IMAGE_BUILDER_INSTANCE_PROFILE` | Build-only SSM instance profile name |
| `IMAGE_BUILD_SUBNET_ID` | Public subnet used only by the temporary Packer builder |
| `TF_STATE_BUCKET` | Versioned Terraform state bucket |
| `TF_STATE_KMS_KEY_ID` | State-bucket KMS key ID or ARN |
| `TF_PLAN_BUCKET` | Private reviewed-plan and apply-log bucket |
| `TF_PLAN_KMS_KEY_ID` | Reviewed-plan bucket KMS key ID or ARN |
| `TF_NETWORK_STATE_KEY` | Network stack state object key |
| `TF_GATEWAY_STATE_KEY` | Gateway stack state object key |
| `TF_CLUSTER_STATE_KEY` | Cluster stack state object key |
| `TF_DNS_STATE_KEY` | DNS stack state object key |
| `PACKER_AMAZON_PLUGIN_VERSION` | Exact Packer Amazon plugin version |
| `RS_GATEWAY_PACKER_VERSION` | Exact Packer CLI version |
| `RS_GATEWAY_SESSION_MANAGER_PLUGIN_VERSION` | Exact AWS Session Manager plugin version |
| `RS_GATEWAY_SESSION_MANAGER_PLUGIN_SHA256` | SHA-256 of the versioned Session Manager plugin package |
| `RS_GATEWAY_SOURCE_AMI` | Reviewed immutable Ubuntu Server 26.04 ARM64 source AMI |
| `RS_GATEWAY_SOURCE_AMI_OWNER` | Canonical AWS account ID `099720109477` |
| `RS_GATEWAY_ROOT_VOLUME_SIZE` | Gateway image root volume size in GiB |
| `RS_GATEWAY_WIREGUARD_VERSION` | Exact `wireguard-tools` package version |
| `RS_GATEWAY_NFTABLES_VERSION` | Exact `nftables` package version |
| `RS_GATEWAY_APT_REPOSITORY` | Approved signed Ubuntu snapshot repository line |
| `RS_GATEWAY_ADGUARD_ARCHIVE_URL` | Versioned ARM64 AdGuard Home archive URL |
| `RS_GATEWAY_ADGUARD_ARCHIVE_SHA256` | AdGuard Home archive SHA-256 |
| `RS_GATEWAY_ADGUARD_SCHEMA_VERSION` | Schema supported by the pinned AdGuard release |
| `RS_GATEWAY_ADGUARD_UPSTREAM_DNS` | Approved upstream resolver |
| `RS_GATEWAY_ADGUARD_FILTER_NAME` | Reviewed filter name |
| `RS_GATEWAY_ADGUARD_FILTER_URL` | Versioned or reviewed filter URL |
| `RS_GATEWAY_AWSCLI_VERSION` | Exact `awscli` package version |
| `RS_GATEWAY_APACHE2_UTILS_VERSION` | Exact `apache2-utils` package version |
| `RS_GATEWAY_CURL_VERSION` | Exact `curl` package version |
| `RS_GATEWAY_CA_CERTIFICATES_VERSION` | Exact `ca-certificates` package version |
| `RS_GATEWAY_PYTHON3_VERSION` | Exact `python3` package version |
| `RS_GATEWAY_SSM_AGENT_REVISION` | Approved preinstalled SSM Agent snap revision |

Create repository secrets `TF_NETWORK_VARS`, `TF_GATEWAY_VARS`,
`TF_CLUSTER_VARS`, and `TF_DNS_VARS`, each containing the complete HCL
`tfvars` for its stack. Create `CLOUDFLARE_PLAN_API_TOKEN` as an expiring,
zone-scoped DNS read token. In the protected `apply` environment, create the
expiring, zone-scoped DNS write secret `CLOUDFLARE_API_TOKEN`, restrict
deployment to `main`, and require an operator reviewer.

Before the first plan:

1. An operator applies [`terraform/bootstrap/`](terraform/bootstrap/) locally
   (see its README for the exact sequence): the versioned, public-access-
   blocked state bucket and its KMS key; the private, Object-Lock-enabled plan
   bucket and its KMS key; the GitHub OIDC provider; the `rs-infra-plan`,
   `rs-infra-apply`, and `rs-infra-image-build` roles; and the build-only
   `rs-infra-image-builder` profile. `bootstrap` is deliberately excluded from
   the cloud workflows above and has no `terraform-bootstrap.yml`, so this step
   cannot be a pull-request plan/apply.
2. Commit a generated `.terraform.lock.hcl` in each of the four deployable
   stacks (`bootstrap`'s own lock file is committed already).
3. `bootstrap`'s OIDC trust already binds the exact workflow path and
   event/environment to the immutable `repository_id`/`repository_owner_id`
   claims: the plan and image-build roles at their exact
   `refs/pull/*/merge` workflow paths, and the apply role at `refs/heads/main`
   through the `apply` environment. Its `rs-infra-plan` role
   grants provider read access, state read plus native lock-object access, KMS
   use, and write access to each stack's private plan prefix; `rs-infra-apply`
   grants the corresponding state/provider mutation access and read/write
   access to reviewed plans and private apply logs, with explicit denies on
   secret-value access and on modifying its own trust, the OIDC provider, or
   the backend buckets' governance controls.
4. The plan bucket already enables S3 versioning, Object Lock, bucket-owner
   enforcement, SSE-KMS, and blocked public access, and denies overwrites of
   immutable plan bundles; only each PR's `latest.json` pointer is mutable.
5. Require the applicable `Reviewed plan` check before merge and use squash
   merges. A direct push, ambiguous merged-PR association, stale stack tree,
   missing plan, or changed Terraform version fails closed.

Because the four states are deliberately independent and outputs are
hand-wired, merge dependent stack changes in order and re-plan downstream
changes after the upstream apply.

## Implementation order

Implementation proceeds in this order:

1. Create the versioned S3 backend and native state locking with a documented
   local bootstrap identity.
2. Create and test immutable-ID-bound GitHub OIDC trust for plan and apply.
3. Apply shared foundations, networking, secret containers, IAM lanes, and
   the three logical Talos node-slot envelopes.
4. Build and approve the gateway and Ubuntu Core images.
5. Bootstrap gateway recovery secrets, then remove its write authority.
6. Seed the Talos recovery bundle once, then disable the seed role.
7. Run Talos genesis through the AWS-local provisioner.
8. Write workload secrets with the operator-only secret tool.
9. Bootstrap Argo CD once; workload reconciliation then belongs to `rs-cloud`.

Production remains blocked until the platform's failure-injection,
restoration, and coordinated cutover checks pass.
