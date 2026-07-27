variable "aws_region" {
  description = "AWS region for the gateway appliance."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = var.aws_region == "eu-west-2"
    error_message = "The accepted gateway design is fixed to eu-west-2."
  }
}

variable "vpc_id" {
  description = "Gateway VPC ID exported by the network stack."
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID exported by the network stack."
  type        = string
}

variable "private_route_table_id" {
  description = "Private Talos route table ID exported by the network stack."
  type        = string
}

variable "private_subnet_cidr" {
  description = "Private Talos subnet CIDR exported by the network stack for routed NAT ingress."
  type        = string

  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "private_subnet_cidr must be a valid CIDR."
  }
}

variable "game_route_table_id" {
  description = "Private game route table ID exported by the network stack."
  type        = string
}

variable "gateway_ami_id" {
  description = "Approved immutable ARM gateway AMI ID."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.gateway_ami_id))
    error_message = "gateway_ami_id must be an EC2 AMI ID."
  }
}

variable "gateway_instance_type" {
  description = "ARM instance type for the gateway appliance."
  type        = string
  default     = "t4g.micro"
}

variable "gateway_profile_mode" {
  description = "Attach the one-time bootstrap profile or the steady-state runtime profile."
  type        = string
  default     = "runtime"

  validation {
    condition     = contains(["bootstrap", "runtime"], var.gateway_profile_mode)
    error_message = "gateway_profile_mode must be bootstrap or runtime."
  }
}

variable "gateway_interface_device" {
  description = "Gateway WAN interface name consumed by the immutable image."
  type        = string
  default     = "ens5"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.:-]{1,15}$", var.gateway_interface_device))
    error_message = "gateway_interface_device must be a valid Linux interface name."
  }
}

variable "gateway_build_version" {
  description = "Approved gateway image build version consumed by boot validation."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.gateway_build_version))
    error_message = "gateway_build_version may contain only letters, digits, dots, underscores, and hyphens."
  }
}

variable "root_volume_size_gib" {
  description = "Disposable encrypted root volume size in GiB."
  type        = number
}

variable "root_volume_type" {
  description = "Disposable encrypted root volume type."
  type        = string
  default     = "gp3"
}

variable "wireguard_ingress_ipv4_cidrs" {
  description = "IPv4 source CIDRs allowed to reach the public WireGuard UDP ports."
  type        = set(string)
  default     = ["0.0.0.0/0"]
}

variable "ssm_public_key_prefix" {
  description = "Pre-agreed Parameter Store prefix used only to publish gateway WireGuard public keys."
  type        = string

  validation {
    condition     = can(regex("^/[A-Za-z0-9_./-]+$", var.ssm_public_key_prefix))
    error_message = "ssm_public_key_prefix must be a safe absolute Parameter Store path."
  }
}

variable "metrics_namespace" {
  description = "CloudWatch namespace used by the gateway image."
  type        = string
  default     = "RSPlatform/Gateway"

  validation {
    condition     = var.metrics_namespace == "RSPlatform/Gateway"
    error_message = "The immutable gateway image publishes only to RSPlatform/Gateway."
  }
}

variable "alarm_actions" {
  description = "SNS topic ARNs invoked by gateway alarms."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Bounded retention for gateway CloudWatch logs."
  type        = number
  default     = 30
}

variable "secret_recovery_window_days" {
  description = "Recovery window for the two gateway secret containers."
  type        = number
  default     = 30
}

variable "kms_deletion_window_days" {
  description = "Deletion window for the gateway secrets KMS key."
  type        = number
  default     = 30
}

variable "project" {
  description = "Project tag applied to supported AWS resources."
  type        = string
  default     = "rs-platform"
}

variable "environment" {
  description = "Environment tag applied to supported AWS resources."
  type        = string
  default     = "production"
}

variable "owner" {
  description = "Owner tag applied to supported AWS resources."
  type        = string
}

variable "cost_center" {
  description = "CostCenter tag applied to supported AWS resources."
  type        = string
}

variable "additional_tags" {
  description = "Additional tags merged with the required platform tags."
  type        = map(string)
  default     = {}
}
