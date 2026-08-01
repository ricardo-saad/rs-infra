# Bootstrap stack

Independent Terraform stack that creates the versioned S3 state foundation,
the GitHub Actions OIDC provider, the `rs-infra-plan`/`rs-infra-apply` CI
roles consumed by the other four deployable stacks (`network`, `gateway`,
`cluster`, `dns`), and the dedicated gateway image-build role and profile.

This stack is **operator-applied by design**, not through GitHub Actions. There
is nowhere else for its own state to live before it exists, and the roles it
creates must not be able to modify the identity and governance controls that
constrain them (see
`DenySelfEscalation`, `DenyOidcProviderTamper`, and `DenyBackendGovernanceTamper`
in [`iam.tf`](iam.tf)).

## What this creates

- A versioned, SSE-KMS-encrypted, public-access-blocked S3 bucket for the
  other four stacks' Terraform state, using native S3 state locking
  (`use_lockfile = true`; no DynamoDB table).
- A private, SSE-KMS-encrypted, Object-Lock-enabled (`GOVERNANCE` mode) S3
  bucket for reviewed plan bundles, apply logs, and application receipts. A
  bucket-policy condition additionally denies any `PutObject` to a reviewed
  bundle's exact key unless the request includes `If-None-Match`, so a bundle
  a reviewer already approved can never be silently replaced.
- One GitHub Actions OIDC provider (`token.actions.githubusercontent.com`),
  trusted by the three CI roles.
- `rs-infra-plan`: dormant read-only provider access, `s3:GetObject` on the
  four exact state keys, take/release of native lock objects, and write access
  to its own stack's plan-bucket prefix. It can also read the exact
  ADR-0037 cluster backup-bucket configuration and private Route53 resources.
  Its former workflow was removed with the rejected whole-file GitHub secret
  transport. Do not recreate it until every replacement remote-configuration
  delivery gate is implemented and passing.
- `rs-infra-apply`: dormant corresponding mutating provider access for what
  `network`, `gateway`, and the ADR-0037 `cluster` foundations provision,
  full state read/write, and reviewed-plan read plus apply-log write. Its
  cluster permissions are bounded to the deterministic backup bucket,
  project-prefixed IAM resources, KMS lifecycle, and private Route53 lifecycle.
  Trusted only from
  `refs/heads/main` through the `apply` environment claim. Carries explicit
  `Deny` statements for `secretsmanager:GetSecretValue`,
  `secretsmanager:PutSecretValue`, and `ssm:PutParameter` (Terraform creates
  secret containers only, never a value) and for modifying any CI/build role,
  the OIDC provider, or the two backend buckets' governance controls. Its
  workflow is removed for the same reason as the plan workflow.
- `rs-infra-image-build`: bounded EC2 and AMI lifecycle permissions, with
  `iam:PassRole` limited to the exact `rs-infra-image-builder` role and
  explicit denial of secret-value writes and reads. Trusted only from
  pull-request merge refs in the private `rs-gateway` repository through its
  exact `.github/workflows/_reusable-image-build.yml` path and immutable
  repository ID.
- `rs-infra-image-builder`: an EC2-assumable instance profile containing only
  the SSM control/data-channel permissions required by Packer's temporary
  builder. It has no gateway runtime secret or Parameter Store permissions.

As the remaining stack scaffolds grow real resources, extend
`apply_permissions` in [`iam.tf`](iam.tf) to match — this policy is scoped to
what is provisioned today, not a forecast of the finished platform.

## Bootstrap sequence

`.gitignore` already ignores `override.tf`/`*_override.tf`, which makes this
possible without ever committing a local backend:

1. As a documented, MFA'd operator identity, create an untracked
   `terraform/bootstrap/backend_override.tf` containing
   `terraform { backend "local" {} }`.
2. `terraform init && terraform apply` with real `owner`, `cost_center`,
   `github_owner`, `github_repository_id`, `github_repository_owner_id`,
   `gateway_github_repository_id`, and `state_object_keys` values (see
   `terraform.tfvars.example`). This produces local state and every resource
   above.
3. Delete `backend_override.tf`, then run
   `terraform init -migrate-state -backend-config="bucket=<state_bucket_name output>" -backend-config="key=bootstrap/terraform.tfstate" -backend-config="region=eu-west-2" -backend-config="encrypt=true" -backend-config="kms_key_id=<state_kms_key_arn output>" -backend-config="use_lockfile=true"`
   to move state into the bucket this stack just created. `bootstrap`'s own
   state now lives in the bucket it manages; bucket versioning is its recovery
   path, not a second stack.
4. Verify with `terraform plan` showing no changes.
5. Record the Terraform delivery outputs as the non-secret repository
   variables listed in the top-level
   [`README.md`](../../README.md#cloud-workflow-configuration):
   `TF_STATE_BUCKET`, `TF_STATE_KMS_KEY_ID`, `TF_PLAN_BUCKET`,
   `TF_PLAN_KMS_KEY_ID`, `TF_PLAN_ROLE_ARN`, `TF_APPLY_ROLE_ARN`, and the four
   `TF_<STACK>_STATE_KEY` variables. Configure `IMAGE_BUILD_ROLE_ARN` and
   `IMAGE_BUILDER_INSTANCE_PROFILE` only in private `rs-gateway`; never copy
   gateway build configuration into GitHub Actions secrets.

Re-running this stack later (e.g. to add a new deployable stack's mutate
permissions) is an ordinary local `terraform plan`/`apply` against the
already-migrated backend — only the very first apply needs the override.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.56.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_instance_profile.packer_builder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_openid_connect_provider.github_actions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.image_build](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.packer_builder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.image_build](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.packer_builder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kms_alias.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_object_lock_configuration.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration) | resource |
| [aws_s3_bucket_ownership_controls.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_ownership_controls.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.apply_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.apply_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.image_build_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.image_build_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.packer_builder_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.packer_builder_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.plan_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.plan_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.plan_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.state_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Additional tags merged with the required platform tags. | `map(string)` | `{}` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for the state backend, plan bucket, and CI roles. | `string` | `"eu-west-2"` | no |
| <a name="input_cost_center"></a> [cost\_center](#input\_cost\_center) | CostCenter tag applied to supported AWS resources. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag applied to supported AWS resources. | `string` | `"production"` | no |
| <a name="input_gateway_github_repository_id"></a> [gateway\_github\_repository\_id](#input\_gateway\_github\_repository\_id) | Immutable numeric ID of the private gateway repository trusted to build AMIs. | `string` | n/a | yes |
| <a name="input_gateway_github_repository_name"></a> [gateway\_github\_repository\_name](#input\_gateway\_github\_repository\_name) | Private gateway repository name used to bind the image-build workflow identity. | `string` | `"rs-gateway"` | no |
| <a name="input_github_owner"></a> [github\_owner](#input\_github\_owner) | GitHub organization or user that owns this repository. | `string` | n/a | yes |
| <a name="input_github_repository_id"></a> [github\_repository\_id](#input\_github\_repository\_id) | Immutable numeric GitHub repository ID, bound in the OIDC trust policy so a rename or transfer cannot silently change trust. | `string` | n/a | yes |
| <a name="input_github_repository_name"></a> [github\_repository\_name](#input\_github\_repository\_name) | GitHub repository name, used only to build the job\_workflow\_ref path pattern. | `string` | `"rs-infra"` | no |
| <a name="input_github_repository_owner_id"></a> [github\_repository\_owner\_id](#input\_github\_repository\_owner\_id) | Immutable numeric GitHub owner (org or user) ID, bound in the OIDC trust policy. | `string` | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Owner tag applied to supported AWS resources. | `string` | n/a | yes |
| <a name="input_plan_bucket_lifecycle_expiration_days"></a> [plan\_bucket\_lifecycle\_expiration\_days](#input\_plan\_bucket\_lifecycle\_expiration\_days) | Days after which objects in the private plan bucket expire; must exceed plan\_object\_lock\_retention\_days. | `number` | `400` | no |
| <a name="input_plan_kms_deletion_window_days"></a> [plan\_kms\_deletion\_window\_days](#input\_plan\_kms\_deletion\_window\_days) | Deletion window for the reviewed-plan bucket KMS key. | `number` | `30` | no |
| <a name="input_plan_object_lock_retention_days"></a> [plan\_object\_lock\_retention\_days](#input\_plan\_object\_lock\_retention\_days) | GOVERNANCE-mode Object Lock default retention applied to every object written to the private plan bucket. | `number` | `90` | no |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to supported AWS resources. | `string` | `"rs-platform"` | no |
| <a name="input_state_kms_deletion_window_days"></a> [state\_kms\_deletion\_window\_days](#input\_state\_kms\_deletion\_window\_days) | Deletion window for the Terraform state KMS key. | `number` | `30` | no |
| <a name="input_state_object_keys"></a> [state\_object\_keys](#input\_state\_object\_keys) | Exact state object key for each deployable stack, keyed by stack name. These become the TF\_<STACK>\_STATE\_KEY repository variables. | `map(string)` | n/a | yes |
| <a name="input_state_versioning_noncurrent_expiration_days"></a> [state\_versioning\_noncurrent\_expiration\_days](#input\_state\_versioning\_noncurrent\_expiration\_days) | Days a noncurrent state object version is retained before expiring; bucket versioning is the state recovery path. | `number` | `365` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_apply_role_arn"></a> [apply\_role\_arn](#output\_apply\_role\_arn) | Mutating Terraform apply role; set as the TF\_APPLY\_ROLE\_ARN repository variable. |
| <a name="output_cluster_state_key"></a> [cluster\_state\_key](#output\_cluster\_state\_key) | Cluster stack state object key; set as the TF\_CLUSTER\_STATE\_KEY repository variable. |
| <a name="output_dns_state_key"></a> [dns\_state\_key](#output\_dns\_state\_key) | DNS stack state object key; set as the TF\_DNS\_STATE\_KEY repository variable. |
| <a name="output_gateway_state_key"></a> [gateway\_state\_key](#output\_gateway\_state\_key) | Gateway stack state object key; set as the TF\_GATEWAY\_STATE\_KEY repository variable. |
| <a name="output_github_oidc_provider_arn"></a> [github\_oidc\_provider\_arn](#output\_github\_oidc\_provider\_arn) | GitHub Actions OIDC provider trusted by the plan, apply, and image-build CI roles. |
| <a name="output_image_build_role_arn"></a> [image\_build\_role\_arn](#output\_image\_build\_role\_arn) | Gateway AMI build role; configure as IMAGE\_BUILD\_ROLE\_ARN in the private rs-gateway repository. |
| <a name="output_image_builder_instance_profile_name"></a> [image\_builder\_instance\_profile\_name](#output\_image\_builder\_instance\_profile\_name) | Build-only SSM instance profile; configure as IMAGE\_BUILDER\_INSTANCE\_PROFILE in private rs-gateway. |
| <a name="output_network_state_key"></a> [network\_state\_key](#output\_network\_state\_key) | Network stack state object key; set as the TF\_NETWORK\_STATE\_KEY repository variable. |
| <a name="output_plan_bucket_name"></a> [plan\_bucket\_name](#output\_plan\_bucket\_name) | Private reviewed-plan and apply-log bucket; set as the TF\_PLAN\_BUCKET repository variable. |
| <a name="output_plan_kms_key_arn"></a> [plan\_kms\_key\_arn](#output\_plan\_kms\_key\_arn) | Reviewed-plan bucket KMS key ARN; set as the TF\_PLAN\_KMS\_KEY\_ID repository variable. |
| <a name="output_plan_role_arn"></a> [plan\_role\_arn](#output\_plan\_role\_arn) | Read-only Terraform plan role; set as the TF\_PLAN\_ROLE\_ARN repository variable. |
| <a name="output_state_bucket_name"></a> [state\_bucket\_name](#output\_state\_bucket\_name) | Versioned Terraform state bucket; set as the TF\_STATE\_BUCKET repository variable. |
| <a name="output_state_kms_key_arn"></a> [state\_kms\_key\_arn](#output\_state\_kms\_key\_arn) | State-bucket KMS key ARN; set as the TF\_STATE\_KMS\_KEY\_ID repository variable. |
<!-- END_TF_DOCS -->
