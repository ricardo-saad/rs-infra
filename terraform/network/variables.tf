variable "aws_region" {
  description = "AWS region for the gateway VPC."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = var.aws_region == "eu-west-2"
    error_message = "The accepted gateway VPC design is fixed to eu-west-2."
  }
}

variable "availability_zone" {
  description = "Single availability zone used by the gateway and private platform subnets."
  type        = string

  validation {
    condition     = can(regex("^eu-west-2[a-z]$", var.availability_zone))
    error_message = "availability_zone must belong to eu-west-2."
  }
}

variable "vpc_cidr" {
  description = "CIDR assigned to the gateway VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR for the public gateway subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr must be a valid CIDR."
  }
}

variable "private_subnet_cidr" {
  description = "CIDR for the private Talos subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "private_subnet_cidr must be a valid CIDR."
  }
}

variable "game_subnet_cidr" {
  description = "CIDR for the private on-demand game subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.game_subnet_cidr, 0))
    error_message = "game_subnet_cidr must be a valid CIDR."
  }
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

locals {
  name_prefix = "${var.project}-${var.environment}"
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
}
