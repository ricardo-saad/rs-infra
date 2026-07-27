locals {
  name_prefix = "${var.project}-${var.environment}-gateway"

  required_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "Terraform"
      CostCenter  = var.cost_center
    },
    var.additional_tags,
  )

  wireguard_interfaces = {
    wg-users = {
      port           = 51820
      overlay_subnet = "10.100.0.0/24"
    }
    wg-personal = {
      port           = 51822
      overlay_subnet = "10.100.2.0/24"
    }
    wg-nodes = {
      port           = 51823
      overlay_subnet = "10.100.3.0/24"
    }
  }

  public_key_parameter_paths = {
    for interface_name, _ in local.wireguard_interfaces :
    interface_name => "${trimsuffix(var.ssm_public_key_prefix, "/")}/${interface_name}"
  }

  public_key_parameter_arns = [
    for parameter_path in values(local.public_key_parameter_paths) :
    "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${parameter_path}"
  ]
}
