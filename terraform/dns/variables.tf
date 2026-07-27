variable "cloudflare_api_token" {
  description = "Zone-scoped, expiring Cloudflare token supplied only by the apply environment."
  type        = string
  sensitive   = true
}

variable "zone_id" {
  description = "Cloudflare zone ID. DNS resources remain scaffold-only."
  type        = string
}

variable "gateway_elastic_ip" {
  description = "Gateway Elastic IP exported by the gateway stack."
  type        = string
}

variable "wireguard_record_names" {
  description = "DNS names for the three WireGuard endpoints. Records must remain DNS-only."
  type = object({
    wg-users    = string
    wg-personal = string
    wg-nodes    = string
  })
}
