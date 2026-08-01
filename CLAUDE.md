# CLAUDE.md

## Repository boundary

`rs-infra` is Infrastructure as Code for RS Platform. It owns Terraform for
AWS and Cloudflare, remote-state foundations, IAM/KMS/secret containers, the
gateway EC2 infrastructure, the Talos envelope, infrastructure bootstrap, and
future operator tools. It provisions infrastructure and deploys no application
workloads.

The private `rs-gateway` repository owns the gateway appliance source, Packer
build, runtime implementation, contract tests, production image inputs, and
AMI release workflow. Do not add gateway `rootfs`, Packer, appliance runtime
code, or image workflows back to this repository.

Stable architecture, ADRs, and coordinated runbooks live in private
`rs-platform`. Workloads live in `rs-cloud`; edge desired state in `rs-edge`;
dynamic gateway peer/authorization state in `rs-console`.

## Current status

- `terraform/bootstrap`, `terraform/network`, and `terraform/gateway` contain
  implementation.
- `terraform/cluster` and parts of `terraform/dns` remain scaffolds.
- `images/home`, `provisioner`, `tools/secret`, `tools/talos-seed`, and
  `argocd/bootstrap` are placeholders.
- Static CI is active. Terraform plan/apply callers were removed because
  whole-file GitHub secret delivery for production `.tfvars` was rejected.
  Never recreate `TF_NETWORK_VARS`, `TF_GATEWAY_VARS`, `TF_CLUSTER_VARS`, or
  `TF_DNS_VARS`.
- The existing plan/apply IAM roles are dormant until replacement remote
  configuration delivery is accepted. Do not recreate their workflows.
- The image-build IAM role/profile retain their existing AWS physical names,
  but OIDC trust for the role belongs exclusively to private `rs-gateway`.

## Terraform layout and conventions

Every directory under `terraform/` is an independent stack with its own
partial `backend "s3" {}`. Backend bucket, key, region, and KMS coordinates are
supplied only at initialization.

- `terraform/bootstrap`: operator-local creation of S3/KMS/OIDC/CI roles and
  the SSM-only Packer builder profile. It is never run from CI.
- `terraform/network`: VPC, public gateway subnet, private Talos/game subnets,
  routes, IGW, and S3 gateway endpoint.
- `terraform/gateway`: replaceable EC2 gateway, EIP, security groups, NAT
  routes, IAM bootstrap/runtime profiles, KMS, two Secrets Manager containers,
  and CloudWatch alarms.
- `terraform/cluster`: AWS-local Talos provisioner envelope and node slots.
- `terraform/dns`: Cloudflare DNS infrastructure.

Stack files follow `versions.tf`, `providers.tf`, `variables.tf`, `outputs.tf`,
and concern-specific resource files once a stack grows. Standard tags are
`Project`, `Environment`, `Owner`, `ManagedBy`, and `CostCenter`, merged with
`additional_tags` through the AWS provider's `default_tags`.

Terraform may create secret containers, KMS keys, IAM policy, and references.
It never creates secret versions or writes private keys, WireGuard material,
Talos PKI, rendered machine configuration, or other secret values into state.

The gateway Terraform and private appliance share an exact three-interface
contract: `wg-users`/51820/`10.100.0.0/24`,
`wg-personal`/51822/`10.100.2.0/24`, and
`wg-nodes`/51823/`10.100.3.0/24`. A contract change requires coordinated
changes in `rs-platform`, `rs-infra`, and private `rs-gateway`.

## Validation

Run for every affected stack:

```sh
terraform fmt -recursive terraform
terraform -chdir=terraform/<stack> init -backend=false -input=false
terraform -chdir=terraform/<stack> validate -no-color
tflint --chdir=terraform/<stack> --format=compact
```

If variables, outputs, or resources change, regenerate the stack README:

```sh
terraform-docs markdown table --indent 2 --output-file README.md \
  --output-mode inject terraform/<stack>
```

CI also runs `terraform fmt -check`, actionlint, gitleaks, Trivy configuration
scanning, immutable action-pin checks, and terraform-docs drift detection.

## Security

- Never commit `.env`, Terraform state/plan files, `.terraform`, kubeconfig,
  talosconfig, keys, certificates, generated inventory, or real
  `terraform.tfvars`.
- Every third-party GitHub Action is pinned to a full commit SHA.
- Changes to OIDC trust, IAM, KMS, state, plans, secrets, network boundaries,
  protected environments, or ownership are privileged.
- A committed credential is compromised and must be revoked or rotated;
  deleting it or rewriting history is not remediation.
- Runtime administration of the gateway remains SSM-only. Terraform must not
  add an EC2 key pair or inbound TCP/22.

## Commits and review

All persistent changes use pull requests and Conventional Commits:
`<type>(<scope>): <lowercase imperative description>`. Terraform scopes are
`bootstrap`, `network`, `gateway`, `cluster`, and `dns`. Other scopes include
`argocd`, `provisioner`, `secret`, `talos-seed`, `image-home`, `ci`, and `repo`.

A change is ready only when ownership, blast radius, rollback/recovery,
traceability to the reviewed commit, required validation, Code Owner approval,
and operator documentation are complete.
