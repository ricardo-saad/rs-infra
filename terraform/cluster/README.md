# Cluster stack

Independent Terraform stack reserved for the AWS-local Talos provisioner,
three logical node-slot envelopes, private DNS, and service-account federation.

It is scaffold-only. Terraform must never render Talos machine configuration,
create a Talos instance directly, or create a recovery-secret version. The
backend block is deliberately partial and must be configured at init time.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Additional tags merged with the required platform tags. | `map(string)` | `{}` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for cluster-envelope resources. | `string` | `"eu-west-2"` | no |
| <a name="input_cost_center"></a> [cost\_center](#input\_cost\_center) | CostCenter tag applied to supported AWS resources. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag applied to supported AWS resources. | `string` | `"production"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Owner tag applied to supported AWS resources. | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to supported AWS resources. | `string` | `"rs-platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_stack"></a> [stack](#output\_stack) | Stable identifier for this independent Terraform stack. |
<!-- END_TF_DOCS -->
