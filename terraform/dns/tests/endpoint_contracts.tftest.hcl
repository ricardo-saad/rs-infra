mock_provider "cloudflare" {}

variables {
  zone_id            = "00000000000000000000000000000000"
  gateway_elastic_ip = "192.0.2.1"
  wireguard_record_names = {
    wg-users    = "users-vpn.example.invalid"
    wg-personal = "personal-vpn.example.invalid"
    wg-nodes    = "nodes-vpn.example.invalid"
  }
  platform_api_tunnel_target = "00000000-0000-0000-0000-000000000000.cfargotunnel.com"
}

run "endpoint_proxy_boundaries" {
  command = plan

  assert {
    condition     = alltrue([for record in cloudflare_dns_record.wireguard : record.proxied == false])
    error_message = "Every WireGuard endpoint must remain unproxied."
  }

  assert {
    condition     = cloudflare_dns_record.platform_api.proxied
    error_message = "The public platform API must remain proxied."
  }

  assert {
    condition     = cloudflare_dns_record.platform_api.name == "platform-api.ricardosaad.com"
    error_message = "The public platform API hostname must remain the ADR-0037 canonical name."
  }

  assert {
    condition     = cloudflare_dns_record.platform_api.type == "CNAME"
    error_message = "The public platform API must target Cloudflare Tunnel with a CNAME."
  }

  assert {
    condition     = cloudflare_dns_record.platform_api.content == var.platform_api_tunnel_target
    error_message = "The platform API CNAME must use the explicit tunnel target input."
  }
}

run "reject_unproxied_platform_api" {
  command = plan

  variables {
    platform_api_proxied = false
  }

  expect_failures = [
    var.platform_api_proxied,
  ]
}

run "reject_duplicate_wireguard_hostnames" {
  command = plan

  variables {
    wireguard_record_names = {
      wg-users    = "vpn.example.invalid"
      wg-personal = "vpn.example.invalid"
      wg-nodes    = "nodes-vpn.example.invalid"
    }
  }

  expect_failures = [
    var.wireguard_record_names,
  ]
}
