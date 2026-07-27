variable "aws_region" {
  description = "AWS region for cluster-envelope resources."
  type        = string
  default     = "eu-west-2"
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
