mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  vpc_id                 = "vpc-0123456789abcdef0"
  public_subnet_id       = "subnet-0123456789abcdef0"
  private_route_table_id = "rtb-0123456789abcdef0"
  private_subnet_cidr    = "10.0.1.0/24"
  game_route_table_id    = "rtb-0123456789abcdef1"
  gateway_ami_id         = "ami-0123456789abcdef0"
  gateway_build_version  = "test-build"
  root_volume_size_gib   = 16
  ssm_public_key_prefix  = "/example/gateway/public-keys"
  owner                  = "test-owner"
  cost_center            = "test-cost-center"
}

run "ssm_only_administration" {
  command = plan

  assert {
    condition     = aws_instance.gateway.key_name == null
    error_message = "The gateway must not install an EC2 SSH key pair."
  }

  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.wireguard :
      rule.ip_protocol == "udp" &&
      contains([51820, 51822, 51823], rule.from_port) &&
      rule.from_port == rule.to_port
    ])
    error_message = "Every public gateway ingress rule must be one of the three WireGuard UDP ports."
  }

  assert {
    condition     = !strcontains(aws_instance.gateway.user_data, "SSH")
    error_message = "Gateway user data must contain no SSH configuration."
  }

  assert {
    condition     = aws_instance.gateway.instance_type == "t4g.small"
    error_message = "The accepted initial gateway size must be t4g.small."
  }
}

run "reject_unapproved_instance_size" {
  command = plan

  variables {
    gateway_instance_type = "t4g.micro"
  }

  expect_failures = [
    var.gateway_instance_type,
  ]
}
