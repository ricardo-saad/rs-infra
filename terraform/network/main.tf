resource "aws_vpc" "platform" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "platform" {
  vpc_id = aws_vpc.platform.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.platform.id
  availability_zone       = var.availability_zone
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-public"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.platform.id
  availability_zone       = var.availability_zone
  cidr_block              = var.private_subnet_cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private"
    Tier = "private"
  }
}

resource "aws_subnet" "game" {
  vpc_id                  = aws_vpc.platform.id
  availability_zone       = var.availability_zone
  cidr_block              = var.game_subnet_cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-game"
    Tier = "private-game"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.platform.id

  tags = {
    Name = "${local.name_prefix}-public"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.platform.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.platform.id

  tags = {
    Name = "${local.name_prefix}-private"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table" "game" {
  vpc_id = aws_vpc.platform.id

  tags = {
    Name = "${local.name_prefix}-game"
  }
}

resource "aws_route_table_association" "game" {
  subnet_id      = aws_subnet.game.id
  route_table_id = aws_route_table.game.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.platform.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    aws_route_table.private.id,
    aws_route_table.game.id,
  ]

  tags = {
    Name = "${local.name_prefix}-s3"
  }
}
