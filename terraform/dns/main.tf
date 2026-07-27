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
