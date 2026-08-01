resource "aws_route53_zone" "platform_api_private" {
  name    = local.platform_api_private_zone_name
  comment = "Split-horizon private DNS for the RS Platform console API"

  vpc {
    vpc_id     = var.vpc_id
    vpc_region = var.aws_region
  }

  tags = {
    Name = "${local.name_prefix}-platform-api-private"
  }
}

resource "aws_route53_record" "platform_api_private" {
  zone_id = aws_route53_zone.platform_api_private.zone_id
  name    = var.platform_api_hostname
  type    = "A"
  ttl     = var.platform_api_private_record_ttl
  records = sort(tolist(var.platform_api_private_ipv4_addresses))
}
