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
