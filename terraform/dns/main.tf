resource "cloudflare_dns_record" "wireguard" {
  for_each = var.wireguard_record_names

  zone_id = var.zone_id
  name    = each.value
  content = var.gateway_elastic_ip
  type    = "A"
  ttl     = 1
  proxied = false
  comment = "RS Platform ${each.key} WireGuard endpoint; UDP must remain unproxied"
}

resource "cloudflare_dns_record" "platform_api" {
  zone_id = var.zone_id
  name    = var.platform_api_hostname
  content = var.platform_api_tunnel_target
  type    = "CNAME"
  ttl     = 1
  proxied = var.platform_api_proxied
  comment = "RS Platform public console API through the explicit Cloudflare Tunnel allowlist"
}

check "wireguard_records_remain_unproxied" {
  assert {
    condition     = alltrue([for record in cloudflare_dns_record.wireguard : !record.proxied])
    error_message = "WireGuard UDP records must remain DNS-only."
  }
}

check "platform_api_uses_distinct_proxied_record" {
  assert {
    condition = (
      cloudflare_dns_record.platform_api.proxied &&
      !contains(values(var.wireguard_record_names), var.platform_api_hostname)
    )
    error_message = "The platform API must use a distinct proxied Cloudflare record."
  }
}
