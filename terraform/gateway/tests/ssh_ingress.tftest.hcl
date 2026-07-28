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
  vpc_id                    = "vpc-0123456789abcdef0"
  public_subnet_id          = "subnet-0123456789abcdef0"
  private_route_table_id    = "rtb-0123456789abcdef0"
  private_subnet_cidr       = "10.0.1.0/24"
  game_route_table_id       = "rtb-0123456789abcdef1"
  gateway_ami_id            = "ami-0123456789abcdef0"
  gateway_build_version     = "test-build"
  gateway_ssh_key_pair_name = "operator-test-key"
  root_volume_size_gib      = 16
  ssh_ingress_ipv4_cidrs    = ["198.51.100.10/32"]
  ssm_public_key_prefix     = "/example/gateway/public-keys"
  owner                     = "test-owner"
  cost_center               = "test-cost-center"
}

run "operator_scoped_ssh" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.ssh) == 1
    error_message = "Exactly one SSH ingress rule should be planned for one operator CIDR."
  }

  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.ssh :
      rule.ip_protocol == "tcp" &&
      rule.from_port == 22 &&
      rule.to_port == 22 &&
      rule.cidr_ipv4 == "198.51.100.10/32"
    ])
    error_message = "SSH ingress must be TCP/22 and retain the exact operator CIDR."
  }

  assert {
    condition     = aws_instance.gateway.key_name == "operator-test-key"
    error_message = "The gateway must install the explicitly selected existing EC2 key pair."
  }

  assert {
    condition = (
      strcontains(aws_instance.gateway.user_data, "SSH_INGRESS_IPV4_CIDRS") &&
      strcontains(aws_instance.gateway.user_data, base64encode("198.51.100.10/32"))
    )
    error_message = "Gateway user data must mirror the exact SSH /32 allowlist into the host firewall."
  }
}

run "reject_world_open_ssh" {
  command = plan

  variables {
    ssh_ingress_ipv4_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [
    var.ssh_ingress_ipv4_cidrs,
  ]
}
