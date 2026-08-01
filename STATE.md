# Implementation handoff

Snapshot: 2026-08-01

## Current boundary

- `rs-infra` owns gateway AWS/Terraform infrastructure.
- Private `rs-gateway` owns the gateway appliance, Packer source, runtime code,
  contract tests, build configuration, and AMI workflow.
- The `rs-infra-image-build` role and `rs-infra-image-builder` profile keep
  their physical names to avoid replacement, but the role's OIDC trust now
  targets the immutable private `rs-gateway` repository ID and exact
  `_reusable-image-build.yml` path.
- The local bootstrap `.terraform`, failed state, and real `terraform.tfvars`
  remain ignored operator data. They were not copied or modified during the
  repository split.

## Deployment status

No AWS resource, AMI, secret version, GitHub variable, GitHub environment, or
repository setting was changed by the ownership migration.

All complete-stack GitHub secrets were deleted by the operator. Do not
recreate `TF_NETWORK_VARS`, `TF_GATEWAY_VARS`, `TF_CLUSTER_VARS`, or
`TF_DNS_VARS`. The Terraform cloud callers and scripts that consumed them were
removed. Existing plan/apply IAM roles remain dormant until a reviewed remote
configuration authority replaces whole-file secret delivery.

The gateway cannot be promoted yet. Required external work includes:

1. obtain the immutable numeric GitHub repository ID for private `rs-gateway`;
2. set `gateway_github_repository_id` in the ignored bootstrap input;
3. review and apply the bootstrap trust-policy change locally;
4. configure only non-secret image build inputs in private `rs-gateway`;
5. select and record exact source AMI, package snapshot/versions, archive
   digests, Packer version, and Session Manager plugin version/digest;
6. build the first AMI candidate and add SSM-only boot/acceptance testing;
7. supply the accepted AMI ID/build version to `terraform/gateway` through the
   future remote Terraform configuration path;
8. apply bootstrap mode, create the first two secret versions on the gateway,
   replace it with runtime mode, and prove write denial.

GitHub CLI authentication was expired during this migration, so repository
IDs, variables, settings, and remote workflow status were not inspected or
changed.

## Validation expectations

For `rs-infra`:

```sh
terraform fmt -check -diff -recursive terraform
terraform -chdir=terraform/bootstrap init -backend=false -input=false
terraform -chdir=terraform/bootstrap validate -no-color
terraform -chdir=terraform/gateway init -backend=false -input=false
terraform -chdir=terraform/gateway validate -no-color
```

For private `rs-gateway`:

```sh
find image -type f -name '*.sh' -print0 | xargs -0 -r -n 20 sh -n
python3 -m unittest discover -s image/tests -v
packer fmt -check -diff image/gateway.pkr.hcl
```

Static validation is not an AMI build, boot test, cloud plan, apply, or
production-readiness proof.
