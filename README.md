# `RS Platform · Infrastructure`

Infrastructure as code for RS Platform.

> **Status:** Repository scaffold complete. The infrastructure described below
> is planned and has not been implemented in this repository yet.

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

## Planned layout

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
Plans and applies run per stack, and a pull request touching multiple stacks
receives a separate plan for each one.

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
- The Cloudflare provider token is the recorded long-lived exception: it is
  zone-scoped, expiring, and held in the `apply` environment.
- Image publication uses a dedicated role limited to image and artifact
  publication.

## Planned CI gates

| Check | Trigger |
|---|---|
| `terraform fmt -check` | Pull request |
| Terraform validation per changed stack | Pull request |
| `tflint` | Pull request |
| `trivy config` | Pull request |
| `terraform-docs` drift | Pull request |
| `gitleaks` | Pull request |
| `actionlint` | Pull request |
| Cloud plan per changed stack | Trusted same-repository pull request |
| Fork safety gate | Fork pull request |
| Infracost diff | Pull request |
| Apply the reviewed plan | Merge to `main`, through `apply` |
| Image build and QEMU boot test | Changes under `images/` |
| Provisioner tests | Changes under `provisioner/` |
| Secret-tool safety tests | Changes under `tools/secret/` |
| Talos-seed safety tests | Changes under `tools/talos-seed/` |
| Signed image publication | Tag |

Third-party actions will be pinned to full commit SHAs. An apply must consume
the exact plan that was reviewed. Untrusted forks never receive an OIDC token,
provider credentials, or Terraform-state access.

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
