# Gateway stack

Independent Terraform stack for the replaceable EC2 hybrid gateway and its
AWS-local support resources.

The stack provisions the ARM appliance, Elastic IP, three UDP-only WireGuard
security-group rules, VPC route targets, two exact recovery-secret containers,
KMS key, temporary bootstrap or steady-state runtime profile, public-key SSM
path permissions, and bounded CloudWatch logging and alarms.

The effective interface contract is:

| Interface | UDP port | Overlay subnet |
|---|---:|---|
| `wg-users` | 51820 | `10.100.0.0/24` |
| `wg-personal` | 51822 | `10.100.2.0/24` |
| `wg-nodes` | 51823 | `10.100.3.0/24` |

Terraform creates no secret version and no SSM parameter value. Start the first
gateway with `gateway_profile_mode = "bootstrap"`; after value-free completion
is verified, change it to `runtime`. That transition removes the bootstrap role
and replaces the bootstrap instance with a clean instance carrying the
read-only runtime profile; the secret containers and Elastic IP remain.

The backend block is deliberately partial and must be configured at init time.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.heartbeat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.instance_status](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.public_key_publication_failure](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.secret_load_failure](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_eip.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_eip_association.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip_association) | resource |
| [aws_iam_instance_profile.bootstrap](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_instance_profile.runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.bootstrap](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.bootstrap](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_instance.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_kms_alias.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_route.game_user_overlay_return](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.private_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_secretsmanager_secret.adguard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.wireguard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_security_group.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.private_routed_traffic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.wireguard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.bootstrap](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ec2_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Additional tags merged with the required platform tags. | `map(string)` | `{}` | no |
| <a name="input_alarm_actions"></a> [alarm\_actions](#input\_alarm\_actions) | SNS topic ARNs invoked by gateway alarms. | `list(string)` | `[]` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for the gateway appliance. | `string` | `"eu-west-2"` | no |
| <a name="input_cost_center"></a> [cost\_center](#input\_cost\_center) | CostCenter tag applied to supported AWS resources. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag applied to supported AWS resources. | `string` | `"production"` | no |
| <a name="input_game_route_table_id"></a> [game\_route\_table\_id](#input\_game\_route\_table\_id) | Private game route table ID exported by the network stack. | `string` | n/a | yes |
| <a name="input_gateway_ami_id"></a> [gateway\_ami\_id](#input\_gateway\_ami\_id) | Approved immutable ARM gateway AMI ID. | `string` | n/a | yes |
| <a name="input_gateway_build_version"></a> [gateway\_build\_version](#input\_gateway\_build\_version) | Approved gateway image build version consumed by boot validation. | `string` | n/a | yes |
| <a name="input_gateway_instance_type"></a> [gateway\_instance\_type](#input\_gateway\_instance\_type) | ARM instance type for the gateway appliance. | `string` | `"t4g.micro"` | no |
| <a name="input_gateway_interface_device"></a> [gateway\_interface\_device](#input\_gateway\_interface\_device) | Gateway WAN interface name consumed by the immutable image. | `string` | `"ens5"` | no |
| <a name="input_gateway_profile_mode"></a> [gateway\_profile\_mode](#input\_gateway\_profile\_mode) | Attach the one-time bootstrap profile or the steady-state runtime profile. | `string` | `"runtime"` | no |
| <a name="input_kms_deletion_window_days"></a> [kms\_deletion\_window\_days](#input\_kms\_deletion\_window\_days) | Deletion window for the gateway secrets KMS key. | `number` | `30` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Bounded retention for gateway CloudWatch logs. | `number` | `30` | no |
| <a name="input_metrics_namespace"></a> [metrics\_namespace](#input\_metrics\_namespace) | CloudWatch namespace used by the gateway image. | `string` | `"RSPlatform/Gateway"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Owner tag applied to supported AWS resources. | `string` | n/a | yes |
| <a name="input_private_route_table_id"></a> [private\_route\_table\_id](#input\_private\_route\_table\_id) | Private Talos route table ID exported by the network stack. | `string` | n/a | yes |
| <a name="input_private_subnet_cidr"></a> [private\_subnet\_cidr](#input\_private\_subnet\_cidr) | Private Talos subnet CIDR exported by the network stack for routed NAT ingress. | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to supported AWS resources. | `string` | `"rs-platform"` | no |
| <a name="input_public_subnet_id"></a> [public\_subnet\_id](#input\_public\_subnet\_id) | Public subnet ID exported by the network stack. | `string` | n/a | yes |
| <a name="input_root_volume_size_gib"></a> [root\_volume\_size\_gib](#input\_root\_volume\_size\_gib) | Disposable encrypted root volume size in GiB. | `number` | n/a | yes |
| <a name="input_root_volume_type"></a> [root\_volume\_type](#input\_root\_volume\_type) | Disposable encrypted root volume type. | `string` | `"gp3"` | no |
| <a name="input_secret_recovery_window_days"></a> [secret\_recovery\_window\_days](#input\_secret\_recovery\_window\_days) | Recovery window for the two gateway secret containers. | `number` | `30` | no |
| <a name="input_ssm_public_key_prefix"></a> [ssm\_public\_key\_prefix](#input\_ssm\_public\_key\_prefix) | Pre-agreed Parameter Store prefix used only to publish gateway WireGuard public keys. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | Gateway VPC ID exported by the network stack. | `string` | n/a | yes |
| <a name="input_wireguard_ingress_ipv4_cidrs"></a> [wireguard\_ingress\_ipv4\_cidrs](#input\_wireguard\_ingress\_ipv4\_cidrs) | IPv4 source CIDRs allowed to reach the public WireGuard UDP ports. | `set(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_adguard_secret_arn"></a> [adguard\_secret\_arn](#output\_adguard\_secret\_arn) | AdGuard recovery secret container ARN; no secret version is managed by Terraform. |
| <a name="output_bootstrap_instance_profile_name"></a> [bootstrap\_instance\_profile\_name](#output\_bootstrap\_instance\_profile\_name) | Temporary bootstrap profile, present only while gateway\_profile\_mode is bootstrap. |
| <a name="output_gateway_elastic_ip"></a> [gateway\_elastic\_ip](#output\_gateway\_elastic\_ip) | Elastic IP consumed by DNS-only WireGuard endpoint records. |
| <a name="output_gateway_instance_id"></a> [gateway\_instance\_id](#output\_gateway\_instance\_id) | Current gateway EC2 instance ID. |
| <a name="output_gateway_primary_network_interface_id"></a> [gateway\_primary\_network\_interface\_id](#output\_gateway\_primary\_network\_interface\_id) | Primary ENI used as the VPC routing target during replacement. |
| <a name="output_gateway_secrets_kms_key_arn"></a> [gateway\_secrets\_kms\_key\_arn](#output\_gateway\_secrets\_kms\_key\_arn) | KMS key protecting the gateway recovery secret containers. |
| <a name="output_gateway_security_group_id"></a> [gateway\_security\_group\_id](#output\_gateway\_security\_group\_id) | Gateway security group admitting only three public WireGuard UDP ports plus private routed traffic. |
| <a name="output_public_key_parameter_paths"></a> [public\_key\_parameter\_paths](#output\_public\_key\_parameter\_paths) | Exact SSM paths the gateway may overwrite with derived public keys; Terraform creates no parameter values. |
| <a name="output_runtime_instance_profile_name"></a> [runtime\_instance\_profile\_name](#output\_runtime\_instance\_profile\_name) | Steady-state read-only gateway instance profile. |
| <a name="output_wireguard_interfaces"></a> [wireguard\_interfaces](#output\_wireguard\_interfaces) | Effective three-interface WireGuard network contract. |
| <a name="output_wireguard_secret_arn"></a> [wireguard\_secret\_arn](#output\_wireguard\_secret\_arn) | WireGuard recovery secret container ARN; no secret version is managed by Terraform. |
<!-- END_TF_DOCS -->
