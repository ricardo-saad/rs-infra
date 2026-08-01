output "stack" {
  description = "Stable identifier for this independent Terraform stack."
  value       = "dns"
}

output "wireguard_endpoint_contract" {
  description = "The unproxied WireGuard endpoint inputs reserved by this stack."
  value = {
    names   = var.wireguard_record_names
    address = var.gateway_elastic_ip
    proxied = false
  }
}

output "wireguard_record_hostnames" {
  description = "DNS-only WireGuard A-record hostnames."
  value = {
    for interface_name, record in cloudflare_dns_record.wireguard :
    interface_name => record.hostname
  }
}

output "platform_api_public_dns" {
  description = "Public Cloudflare Tunnel DNS contract for the platform API; no tunnel credential is managed by Terraform."
  value = {
    hostname      = cloudflare_dns_record.platform_api.hostname
    record_type   = cloudflare_dns_record.platform_api.type
    tunnel_target = var.platform_api_tunnel_target
    proxied       = cloudflare_dns_record.platform_api.proxied
  }
}

output "platform_api_tls_dns_contract" {
  description = "Public hostname input for rs-cloud/cert-manager and Traefik certificate configuration."
  value = {
    hostname                      = var.platform_api_hostname
    dns_names                     = [var.platform_api_hostname]
    certificate_owner             = "rs-cloud/cert-manager"
    terraform_manages_private_key = false
  }
}
