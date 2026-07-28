# `RS Platform · Infrastructure`

Infrastructure as code for RS Platform.

> **Status:** Initial repository scaffold complete. The EC2 gateway Terraform
> and immutable-image source are implemented but have not been built or
> applied. All other components remain contract-only scaffolds. Per-stack
> cloud plan and apply workflows are scaffolded but remain inactive until the
> backend, OIDC roles, GitHub variables, secrets, and provider lock files
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
| Cloud plan per changed stack | Trusted same-repository pull request | Implemented; configuration required |
| Apply exact reviewed plan | Merge to `main`, through `apply` | Implemented; configuration required |

The remaining gates are deferred, not silently omitted:

| Check | Intended trigger |
|---|---|
| Infracost diff | Pull request |
| Image build and QEMU boot test | Changes under `images/` |
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

### Deployment workflow configuration

Create these repository variables before enabling the four deployment
workflows:

| Variable | Purpose |
|---|---|
| `AWS_REGION` | Region containing the backend and AWS resources |
| `AWS_ACCOUNT_ID` | Expected account for OIDC role assumption |
| `TF_PLAN_ROLE_ARN` | Trusted-PR planning role |
| `TF_APPLY_ROLE_ARN` | Protected-environment apply role |
| `TF_STATE_BUCKET` | Versioned Terraform state bucket |
| `TF_STATE_KMS_KEY_ID` | State-bucket KMS key ID or ARN |
| `TF_PLAN_BUCKET` | Private reviewed-plan and apply-log bucket |
| `TF_PLAN_KMS_KEY_ID` | Reviewed-plan bucket KMS key ID or ARN |
| `TF_NETWORK_STATE_KEY` | Network stack state object key |
| `TF_GATEWAY_STATE_KEY` | Gateway stack state object key |
| `TF_CLUSTER_STATE_KEY` | Cluster stack state object key |
| `TF_DNS_STATE_KEY` | DNS stack state object key |

Create repository secrets `TF_NETWORK_VARS`, `TF_GATEWAY_VARS`,
`TF_CLUSTER_VARS`, and `TF_DNS_VARS`, each containing the complete HCL
`tfvars` for its stack. Create `CLOUDFLARE_PLAN_API_TOKEN` as an expiring,
zone-scoped DNS read token. In the protected `apply` environment, create the
expiring, zone-scoped DNS write secret `CLOUDFLARE_API_TOKEN`, restrict
deployment to `main`, and require an operator reviewer.

Before the first plan:

1. Bootstrap the versioned, public-access-blocked state and plan buckets and
   their KMS keys outside these four stacks.
2. Configure native S3 state locking and commit a generated
   `.terraform.lock.hcl` in each deployable stack.
3. Configure immutable-ID-bound GitHub OIDC trust for the exact workflow path
   and event/environment. The plan role needs provider read access, state read
   plus native lock-object access, KMS use, and write access to its private
   plan prefix. The apply role needs the corresponding state/provider mutation
   access and read/write access to reviewed plans and private apply logs.
4. Enable S3 versioning, retention/lifecycle, bucket-owner enforcement,
   SSE-KMS, and block public access on the plan bucket. Deny overwrites of
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
