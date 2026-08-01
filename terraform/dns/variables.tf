variable "zone_id" {
  description = "Cloudflare zone ID containing the platform API and WireGuard endpoint records."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character Cloudflare zone ID."
  }
}

variable "gateway_elastic_ip" {
  description = "Gateway Elastic IP exported by the gateway stack."
  type        = string

  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.gateway_elastic_ip)) && can(cidrhost("${var.gateway_elastic_ip}/32", 0))
    error_message = "gateway_elastic_ip must be a valid IPv4 address."
  }
}

variable "wireguard_record_names" {
  description = "DNS names for the three WireGuard endpoints. Records must remain DNS-only."
  type = object({
    wg-users    = string
    wg-personal = string
    wg-nodes    = string
  })

  validation {
    condition = (
      length(distinct(values(var.wireguard_record_names))) == 3 &&
      alltrue([
        for hostname in values(var.wireguard_record_names) :
        can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$", hostname))
      ])
    )
    error_message = "wireguard_record_names must contain three distinct lowercase DNS hostnames."
  }
}

variable "platform_api_hostname" {
  description = "Canonical public console API hostname selected by ADR-0037."
  type        = string
  default     = "platform-api.ricardosaad.com"

  validation {
    condition     = var.platform_api_hostname == "platform-api.ricardosaad.com"
    error_message = "ADR-0037 fixes platform_api_hostname to platform-api.ricardosaad.com."
  }
}

variable "platform_api_tunnel_target" {
  description = "Cloudflare Tunnel CNAME target for the public platform API allowlist; this is not a tunnel token."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.cfargotunnel\\.com$", var.platform_api_tunnel_target))
    error_message = "platform_api_tunnel_target must be a lower-case <tunnel-uuid>.cfargotunnel.com hostname."
  }
}

variable "platform_api_proxied" {
  description = "Whether Cloudflare proxies the public platform API CNAME. ADR-0037 requires this to remain true."
  type        = bool
  default     = true

  validation {
    condition     = var.platform_api_proxied
    error_message = "The public platform API record must remain proxied through Cloudflare Tunnel."
  }
}
