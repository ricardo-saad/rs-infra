# DNS stack

Independent Terraform stack for Cloudflare DNS records.

The WireGuard A records consume the gateway stack's Elastic IP and remain
DNS-only (`proxied = false`). The public
`platform-api.ricardosaad.com` CNAME points at an explicit
`<tunnel-id>.cfargotunnel.com` target and remains proxied. Terraform creates
neither the Cloudflare Tunnel nor a tunnel token; `rs-cloud` owns the
cloudflared workload and its reference-only secret consumption.

Certificate issuance and private-key custody belong to
`rs-cloud`/cert-manager. This stack exports only the public hostname/DNS
contract for Traefik.

Cloudflare credentials use the provider's `CLOUDFLARE_API_TOKEN` environment
variable so they are not embedded in configuration. No active workflow in
this repository receives that token: ADR-0036/0038 configuration-delivery
gates still block remote production plan/apply.

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
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | 5.22.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_dns_record.platform_api](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record) | resource |
| [cloudflare_dns_record.wireguard](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_gateway_elastic_ip"></a> [gateway\_elastic\_ip](#input\_gateway\_elastic\_ip) | Gateway Elastic IP exported by the gateway stack. | `string` | n/a | yes |
| <a name="input_platform_api_hostname"></a> [platform\_api\_hostname](#input\_platform\_api\_hostname) | Canonical public console API hostname selected by ADR-0037. | `string` | `"platform-api.ricardosaad.com"` | no |
| <a name="input_platform_api_proxied"></a> [platform\_api\_proxied](#input\_platform\_api\_proxied) | Whether Cloudflare proxies the public platform API CNAME. ADR-0037 requires this to remain true. | `bool` | `true` | no |
| <a name="input_platform_api_tunnel_target"></a> [platform\_api\_tunnel\_target](#input\_platform\_api\_tunnel\_target) | Cloudflare Tunnel CNAME target for the public platform API allowlist; this is not a tunnel token. | `string` | n/a | yes |
| <a name="input_wireguard_record_names"></a> [wireguard\_record\_names](#input\_wireguard\_record\_names) | DNS names for the three WireGuard endpoints. Records must remain DNS-only. | <pre>object({<br/>    wg-users    = string<br/>    wg-personal = string<br/>    wg-nodes    = string<br/>  })</pre> | n/a | yes |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Cloudflare zone ID containing the platform API and WireGuard endpoint records. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_platform_api_public_dns"></a> [platform\_api\_public\_dns](#output\_platform\_api\_public\_dns) | Public Cloudflare Tunnel DNS contract for the platform API; no tunnel credential is managed by Terraform. |
| <a name="output_platform_api_tls_dns_contract"></a> [platform\_api\_tls\_dns\_contract](#output\_platform\_api\_tls\_dns\_contract) | Public hostname input for rs-cloud/cert-manager and Traefik certificate configuration. |
| <a name="output_stack"></a> [stack](#output\_stack) | Stable identifier for this independent Terraform stack. |
| <a name="output_wireguard_endpoint_contract"></a> [wireguard\_endpoint\_contract](#output\_wireguard\_endpoint\_contract) | The unproxied WireGuard endpoint inputs reserved by this stack. |
| <a name="output_wireguard_record_hostnames"></a> [wireguard\_record\_hostnames](#output\_wireguard\_record\_hostnames) | DNS-only WireGuard A-record hostnames. |
<!-- END_TF_DOCS -->
