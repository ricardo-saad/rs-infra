# Cluster stack

Independent Terraform stack for the AWS-local Talos envelope and workload
infrastructure contracts. The ADR-0037 slice creates:

- a narrowly scoped private Route53 zone and split-horizon A record for
  `platform-api.ricardosaad.com`;
- a versioned, KMS-encrypted, public-blocked S3 bucket for CloudNativePG
  PostgreSQL base backups and WAL archives;
- one OIDC-federated IAM role bound to the exact console backup Kubernetes
  service account and exact backup object prefix; and
- stable Parameter Store name/ARN outputs for console database and runtime
  values.

Terraform deliberately creates no `aws_ssm_parameter` resources because SSM
has no value-less secure-parameter container: creating one would place secret
material in Terraform configuration and state. An operator-owned secret tool
must populate and rotate the output paths. Likewise, certificate issuance and
private-key custody belong to `rs-cloud`/cert-manager; this stack outputs only
the platform API hostname and DNS contract for private Traefik.

Dynamic Talos machines, rendered Talos machine configuration, PostgreSQL,
Traefik, cloudflared, and other Kubernetes workloads remain outside this
stack. The partial backend must be configured at init time. ADR-0036/0038
configuration-delivery gates still block production remote plan/apply; source
and static validation here do not bypass them.

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
| [aws_iam_role.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kms_alias.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_route53_record.platform_api_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_zone.platform_api_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_s3_bucket.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.console_backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.console_backup_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.console_backup_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Additional tags merged with the required platform tags. | `map(string)` | `{}` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for cluster-envelope resources. | `string` | `"eu-west-2"` | no |
| <a name="input_cluster_oidc_issuer_url"></a> [cluster\_oidc\_issuer\_url](#input\_cluster\_oidc\_issuer\_url) | HTTPS issuer URL corresponding exactly to cluster\_oidc\_provider\_arn. | `string` | n/a | yes |
| <a name="input_cluster_oidc_provider_arn"></a> [cluster\_oidc\_provider\_arn](#input\_cluster\_oidc\_provider\_arn) | IAM OIDC provider ARN for the private Talos cluster service-account issuer. | `string` | n/a | yes |
| <a name="input_console_backup_abort_multipart_days"></a> [console\_backup\_abort\_multipart\_days](#input\_console\_backup\_abort\_multipart\_days) | Days before incomplete console backup multipart uploads are aborted. | `number` | `7` | no |
| <a name="input_console_backup_expiration_days"></a> [console\_backup\_expiration\_days](#input\_console\_backup\_expiration\_days) | Days before current console backup objects expire through bucket lifecycle. | `number` | `90` | no |
| <a name="input_console_backup_kms_deletion_window_days"></a> [console\_backup\_kms\_deletion\_window\_days](#input\_console\_backup\_kms\_deletion\_window\_days) | Deletion window for the KMS key protecting console PostgreSQL backups. | `number` | `30` | no |
| <a name="input_console_backup_noncurrent_expiration_days"></a> [console\_backup\_noncurrent\_expiration\_days](#input\_console\_backup\_noncurrent\_expiration\_days) | Days before noncurrent console backup object versions expire. | `number` | `30` | no |
| <a name="input_console_backup_object_prefix"></a> [console\_backup\_object\_prefix](#input\_console\_backup\_object\_prefix) | Exclusive S3 object prefix available to the console backup service account. | `string` | `"postgresql/"` | no |
| <a name="input_console_backup_service_account_name"></a> [console\_backup\_service\_account\_name](#input\_console\_backup\_service\_account\_name) | Kubernetes service account federated to the console backup IAM role. | `string` | `"console-backup"` | no |
| <a name="input_console_backup_service_account_namespace"></a> [console\_backup\_service\_account\_namespace](#input\_console\_backup\_service\_account\_namespace) | Kubernetes namespace containing the service account permitted to access console PostgreSQL backups. | `string` | `"rs-console"` | no |
| <a name="input_console_parameter_prefix"></a> [console\_parameter\_prefix](#input\_console\_parameter\_prefix) | Pre-agreed Parameter Store prefix for externally populated console database and runtime secret values. | `string` | `"/rs-platform/production/console"` | no |
| <a name="input_cost_center"></a> [cost\_center](#input\_cost\_center) | CostCenter tag applied to supported AWS resources. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag applied to supported AWS resources. | `string` | `"production"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Owner tag applied to supported AWS resources. | `string` | n/a | yes |
| <a name="input_platform_api_hostname"></a> [platform\_api\_hostname](#input\_platform\_api\_hostname) | Canonical console API hostname shared by public Cloudflare DNS, private Route53 DNS, WebAuthn, and TLS. | `string` | `"platform-api.ricardosaad.com"` | no |
| <a name="input_platform_api_private_ipv4_addresses"></a> [platform\_api\_private\_ipv4\_addresses](#input\_platform\_api\_private\_ipv4\_addresses) | Private Traefik IPv4 addresses published by the split-horizon platform API record. | `set(string)` | n/a | yes |
| <a name="input_platform_api_private_record_ttl"></a> [platform\_api\_private\_record\_ttl](#input\_platform\_api\_private\_record\_ttl) | TTL in seconds for the private platform API A record. | `number` | `60` | no |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to supported AWS resources. | `string` | `"rs-platform"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID exported by the network stack and associated with the platform API private hosted zone. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_console_backup_bucket"></a> [console\_backup\_bucket](#output\_console\_backup\_bucket) | Encrypted, versioned S3 destination contract for CloudNativePG backups. |
| <a name="output_console_backup_iam_scope"></a> [console\_backup\_iam\_scope](#output\_console\_backup\_iam\_scope) | Auditable least-privilege action and resource contract used by the console backup role. |
| <a name="output_console_backup_service_account_federation"></a> [console\_backup\_service\_account\_federation](#output\_console\_backup\_service\_account\_federation) | Exact Kubernetes service-account federation contract consumed by rs-cloud. |
| <a name="output_console_secret_parameter_contract"></a> [console\_secret\_parameter\_contract](#output\_console\_secret\_parameter\_contract) | Parameter Store names and ARNs populated outside Terraform; no aws\_ssm\_parameter values are created by this stack. |
| <a name="output_platform_api_private_dns"></a> [platform\_api\_private\_dns](#output\_platform\_api\_private\_dns) | Split-horizon Route53 contract consumed by private Traefik and cluster workloads. |
| <a name="output_platform_api_tls_contract"></a> [platform\_api\_tls\_contract](#output\_platform\_api\_tls\_contract) | Hostname-only TLS contract for private Traefik; certificate issuance and private-key custody remain in rs-cloud/cert-manager. |
| <a name="output_stack"></a> [stack](#output\_stack) | Stable identifier for this independent Terraform stack. |
<!-- END_TF_DOCS -->
