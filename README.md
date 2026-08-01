# RS Platform Infrastructure

Infrastructure as code for RS Platform.

> **Status:** The bootstrap, network, and gateway Terraform implementations
> exist. The immutable gateway appliance and AMI pipeline have moved to the
> private `rs-gateway` repository. Cloud plan/apply workflows were removed:
> complete stack configuration must not be delivered through GitHub Actions
> secrets, and no replacement configuration authority is active yet.

## Purpose

`rs-infra` owns:

- Terraform for AWS and Cloudflare;
- the versioned, KMS-encrypted S3 state and reviewed-plan foundations;
- GitHub OIDC, plan/apply roles, and shared build infrastructure;
- networking, IAM, KMS, secret containers, EC2 instances, routes, and alarms;
- the Talos cluster envelope and AWS-local provisioner;
- operator-only secret and Talos seed tools; and
- one-time Argo CD bootstrap infrastructure.

It provisions infrastructure and deploys no application workloads. Stable
architecture and coordinated runbooks live in private `rs-platform`.

Private `rs-gateway` owns the gateway appliance source, Packer build, runtime
implementation, contract tests, build inputs, and AMI release workflow.
`rs-infra` creates the infrastructure the appliance runs on and the narrowly
scoped identities its build and runtime use.

## Boundaries

This repository never contains:

- gateway image contents or gateway runtime implementation;
- Kubernetes workloads (`rs-cloud`);
- edge desired state (`rs-edge`);
- application source;
- secret values or versions, generated keys, Talos PKI, or WireGuard key
  material, including in Terraform state; or
- private inventory or reusable authority.

Terraform creates secret containers, policies, KMS keys, and references only.
It never creates a secret version or renders secret-bearing machine
configuration.

## Layout

```text
rs-infra/
├── terraform/
│   ├── bootstrap/         # State, plans, OIDC, CI roles, builder profile
│   ├── network/           # VPC, subnets, routes, and S3 endpoint
│   ├── gateway/           # EC2 gateway, IAM, KMS, secret metadata, alarms
│   ├── cluster/           # Talos provisioner envelope and node slots
│   └── dns/               # Cloudflare DNS infrastructure
├── images/
│   └── home/              # Future Ubuntu Core edge image
├── provisioner/           # Future Talos lifecycle state machine
├── tools/
│   ├── secret/            # Future operator-only secret writer
│   └── talos-seed/        # Future one-time Talos recovery seed
└── argocd/bootstrap/      # Future one-time Argo CD bootstrap
```

Each Terraform directory is an independent stack with a partial S3 backend.
Backend coordinates are supplied at initialization and never hard-coded.

## Identity model

- `rs-infra-plan` has read-only provider/state access and may write only
  reviewed-plan objects for the exact stack it plans.
- `rs-infra-apply` has the corresponding mutating access and is restricted to
  protected `main` through the `apply` environment.
- `rs-infra-image-build` retains its physical AWS name to avoid replacement,
  but its OIDC trust is bound to the immutable repository ID and exact reusable
  workflow path of private `rs-gateway`. No `rs-infra` workflow can assume it.
- `rs-infra-image-builder` is the SSM-only EC2 profile that Packer may pass to
  a temporary builder. It has no gateway runtime secret access.
- The gateway bootstrap role can write only the first versions of two exact
  Secrets Manager containers. The runtime role can read but cannot write them.

AWS trust binds immutable GitHub owner/repository IDs, audience, workflow path,
and exact ref or protected environment. Long-lived AWS credentials are not
used by CI.

## CI and deployment status

Static pull-request validation is active and credential-free:

| Check | Status |
|---|---|
| Repository and immutable action pins | Implemented |
| Terraform formatting and validation | Implemented |
| TFLint | Implemented |
| Trivy configuration scan | Implemented |
| Terraform documentation drift | Implemented |
| Gitleaks | Implemented |
| Actionlint | Implemented |

The Terraform plan/apply workflows and scripts that materialized whole
`.tfvars` secrets have been removed. The existing plan/apply IAM roles remain
dormant to avoid destructive identity churn during the migration. Do not
recreate the deleted `TF_NETWORK_VARS`,
`TF_GATEWAY_VARS`, `TF_CLUSTER_VARS`, or `TF_DNS_VARS` GitHub secrets. The
whole-file secret transport is rejected and will be replaced before any cloud
workflow is enabled.

The following non-secret repository metadata may remain configured, but does
not authorize deployment by itself:

| Variable | Purpose |
|---|---|
| `AWS_REGION` | AWS region containing state and infrastructure |
| `AWS_ACCOUNT_ID` | Expected account for OIDC assumption |
| `TF_PLAN_ROLE_ARN` | Dormant read-only planning role |
| `TF_APPLY_ROLE_ARN` | Dormant protected apply role |
| `TF_STATE_BUCKET` | Versioned Terraform state bucket |
| `TF_STATE_KMS_KEY_ID` | State KMS key |
| `TF_PLAN_BUCKET` | Object-Lock-protected reviewed-plan bucket |
| `TF_PLAN_KMS_KEY_ID` | Reviewed-plan KMS key |
| `TF_NETWORK_STATE_KEY` | Exact network state object key |
| `TF_GATEWAY_STATE_KEY` | Exact gateway state object key |
| `TF_CLUSTER_STATE_KEY` | Exact cluster state object key |
| `TF_DNS_STATE_KEY` | Exact DNS state object key |

Gateway image build variables and the `IMAGE_BUILD_ROLE_ARN` /
`IMAGE_BUILDER_INSTANCE_PROFILE` outputs are configured only in private
`rs-gateway`; they are not `rs-infra` secrets.

## Bootstrap

`terraform/bootstrap` is the only operator-local Terraform stack. Its first
apply creates:

- the state and reviewed-plan buckets and KMS keys;
- native S3 state locking;
- the GitHub OIDC provider;
- plan/apply identities for `rs-infra`;
- image-build trust for private `rs-gateway`; and
- the dedicated SSM-only Packer builder profile.

The bootstrap input must include immutable numeric IDs for both `rs-infra` and
private `rs-gateway`. The image role/profile physical names intentionally stay
`rs-infra-image-build` and `rs-infra-image-builder` during this ownership
migration so an already-created identity is updated in place rather than
replaced.

See [`terraform/bootstrap/README.md`](terraform/bootstrap/README.md) for the
exact local-state-to-S3 migration sequence. Do not apply any other stack
locally.

## Implementation order

1. Bootstrap state, KMS, OIDC, CI roles, and the builder profile locally.
2. Apply shared networking after replacement remote configuration delivery is
   accepted.
3. Build and accept the gateway AMI from private `rs-gateway`.
4. Apply `terraform/gateway` using the approved immutable AMI ID and build
   version.
5. Bootstrap the two gateway recovery secrets, replace the bootstrap instance
   with the runtime profile, and prove write denial.
6. Continue with Talos, workload-secret, DNS, and Argo CD stages only after
   their own configuration and recovery gates are settled.

Production remains blocked until the platform's boot, failure-injection,
restoration, and coordinated cutover checks pass.
