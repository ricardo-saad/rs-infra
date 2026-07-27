output "vpc_id" {
  description = "Gateway VPC ID."
  value       = aws_vpc.platform.id
}

output "vpc_cidr" {
  description = "Gateway VPC CIDR."
  value       = aws_vpc.platform.cidr_block
}

output "public_subnet_id" {
  description = "Public subnet for the gateway appliance."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private Talos subnet."
  value       = aws_subnet.private.id
}

output "private_subnet_cidr" {
  description = "Private Talos subnet CIDR used by gateway forwarding policy."
  value       = aws_subnet.private.cidr_block
}

output "game_subnet_id" {
  description = "Private game subnet."
  value       = aws_subnet.game.id
}

output "game_subnet_cidr" {
  description = "Private game subnet CIDR."
  value       = aws_subnet.game.cidr_block
}

output "public_route_table_id" {
  description = "Public subnet route table ID."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "Private Talos subnet route table ID."
  value       = aws_route_table.private.id
}

output "game_route_table_id" {
  description = "Private game subnet route table ID."
  value       = aws_route_table.game.id
}
