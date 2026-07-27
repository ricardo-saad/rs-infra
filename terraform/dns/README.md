# DNS stack

Independent Terraform stack reserved for the Cloudflare zone, DNS records, and
tunnel configuration.

The WireGuard A records consume the gateway stack's Elastic IP and remain
DNS-only (`proxied = false`). Other zone and tunnel resources are scaffold-only.
The zone-scoped, expiring
Cloudflare token is supplied only by the protected apply environment.

The backend block is deliberately partial and must be configured at init time.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | ~> 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_dns_record.wireguard](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cloudflare_api_token"></a> [cloudflare\_api\_token](#input\_cloudflare\_api\_token) | Zone-scoped, expiring Cloudflare token supplied only by the apply environment. | `string` | n/a | yes |
| <a name="input_gateway_elastic_ip"></a> [gateway\_elastic\_ip](#input\_gateway\_elastic\_ip) | Gateway Elastic IP exported by the gateway stack. | `string` | n/a | yes |
| <a name="input_wireguard_record_names"></a> [wireguard\_record\_names](#input\_wireguard\_record\_names) | DNS names for the three WireGuard endpoints. Records must remain DNS-only. | <pre>object({<br/>    wg-users    = string<br/>    wg-personal = string<br/>    wg-nodes    = string<br/>  })</pre> | n/a | yes |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Cloudflare zone ID. DNS resources remain scaffold-only. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_stack"></a> [stack](#output\_stack) | Stable identifier for this independent Terraform stack. |
| <a name="output_wireguard_endpoint_contract"></a> [wireguard\_endpoint\_contract](#output\_wireguard\_endpoint\_contract) | The unproxied WireGuard endpoint inputs reserved by this stack. |
| <a name="output_wireguard_record_hostnames"></a> [wireguard\_record\_hostnames](#output\_wireguard\_record\_hostnames) | DNS-only WireGuard A-record hostnames. |
<!-- END_TF_DOCS -->
