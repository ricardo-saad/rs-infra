# Network stack

Independent Terraform stack for the single-AZ gateway VPC. It creates one
public gateway subnet, one private Talos subnet, one private game subnet,
isolated route tables, an internet gateway, and the free S3 gateway endpoint.

The private default route and game-overlay return route are owned by the
gateway stack because their target is the replaceable gateway instance. No NAT
Gateway, load balancer, interface endpoint, or public private-subnet address is
created.

The backend block is deliberately partial and must be configured at init time.

## Delivery

Changes to this stack are planned by `.github/workflows/terraform-network.yml`
on trusted pull requests. Merging the reviewed change applies that exact saved
plan through the protected `apply` environment.

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
| [aws_internet_gateway.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.game](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.game](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.game](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Additional tags merged with the required platform tags. | `map(string)` | `{}` | no |
| <a name="input_availability_zone"></a> [availability\_zone](#input\_availability\_zone) | Single availability zone used by the gateway and private platform subnets. | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for the gateway VPC. | `string` | `"eu-west-2"` | no |
| <a name="input_cost_center"></a> [cost\_center](#input\_cost\_center) | CostCenter tag applied to supported AWS resources. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag applied to supported AWS resources. | `string` | `"production"` | no |
| <a name="input_game_subnet_cidr"></a> [game\_subnet\_cidr](#input\_game\_subnet\_cidr) | CIDR for the private on-demand game subnet. | `string` | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Owner tag applied to supported AWS resources. | `string` | n/a | yes |
| <a name="input_private_subnet_cidr"></a> [private\_subnet\_cidr](#input\_private\_subnet\_cidr) | CIDR for the private Talos subnet. | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to supported AWS resources. | `string` | `"rs-platform"` | no |
| <a name="input_public_subnet_cidr"></a> [public\_subnet\_cidr](#input\_public\_subnet\_cidr) | CIDR for the public gateway subnet. | `string` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR assigned to the gateway VPC. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_game_route_table_id"></a> [game\_route\_table\_id](#output\_game\_route\_table\_id) | Private game subnet route table ID. |
| <a name="output_game_subnet_cidr"></a> [game\_subnet\_cidr](#output\_game\_subnet\_cidr) | Private game subnet CIDR. |
| <a name="output_game_subnet_id"></a> [game\_subnet\_id](#output\_game\_subnet\_id) | Private game subnet. |
| <a name="output_private_route_table_id"></a> [private\_route\_table\_id](#output\_private\_route\_table\_id) | Private Talos subnet route table ID. |
| <a name="output_private_subnet_cidr"></a> [private\_subnet\_cidr](#output\_private\_subnet\_cidr) | Private Talos subnet CIDR used by gateway forwarding policy. |
| <a name="output_private_subnet_id"></a> [private\_subnet\_id](#output\_private\_subnet\_id) | Private Talos subnet. |
| <a name="output_public_route_table_id"></a> [public\_route\_table\_id](#output\_public\_route\_table\_id) | Public subnet route table ID. |
| <a name="output_public_subnet_id"></a> [public\_subnet\_id](#output\_public\_subnet\_id) | Public subnet for the gateway appliance. |
| <a name="output_vpc_cidr"></a> [vpc\_cidr](#output\_vpc\_cidr) | Gateway VPC CIDR. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | Gateway VPC ID. |
<!-- END_TF_DOCS -->
