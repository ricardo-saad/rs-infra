resource "aws_security_group" "gateway" {
  name        = local.name_prefix
  description = "Public WireGuard UDP, operator-scoped SSH, and private routed traffic"
  vpc_id      = var.vpc_id

  tags = {
    Name = local.name_prefix
  }
}

resource "aws_vpc_security_group_ingress_rule" "wireguard" {
  for_each = {
    for pair in setproduct(keys(local.wireguard_interfaces), var.wireguard_ingress_ipv4_cidrs) :
    "${pair[0]}:${pair[1]}" => {
      interface_name = pair[0]
      cidr           = pair[1]
    }
  }

  security_group_id = aws_security_group.gateway.id
  description       = "${each.value.interface_name} WireGuard"
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "udp"
  from_port         = local.wireguard_interfaces[each.value.interface_name].port
  to_port           = local.wireguard_interfaces[each.value.interface_name].port
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = var.ssh_ingress_ipv4_cidrs

  security_group_id = aws_security_group.gateway.id
  description       = "Operator-scoped SSH"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "private_routed_traffic" {
  security_group_id = aws_security_group.gateway.id
  description       = "Talos subnet routed NAT and enumerated relay traffic"
  cidr_ipv4         = var.private_subnet_cidr
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.gateway.id
  description       = "Gateway appliance, routed NAT, AWS APIs, and outbound control-plane traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_eip" "gateway" {
  domain = "vpc"

  tags = {
    Name = local.name_prefix
  }
}

resource "aws_eip_association" "gateway" {
  allocation_id = aws_eip.gateway.id
  instance_id   = aws_instance.gateway.id
}

resource "aws_route" "private_internet" {
  route_table_id         = var.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.gateway.primary_network_interface_id
}

resource "aws_route" "game_user_overlay_return" {
  route_table_id         = var.game_route_table_id
  destination_cidr_block = local.wireguard_interfaces["wg-users"].overlay_subnet
  network_interface_id   = aws_instance.gateway.primary_network_interface_id
}
