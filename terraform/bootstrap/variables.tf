variable "aws_region" {
  description = "AWS region for the state backend, plan bucket, and CI roles."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = var.aws_region == "eu-west-2"
    error_message = "The accepted platform design is fixed to eu-west-2."
  }
}

variable "github_owner" {
  description = "GitHub organization or user that owns this repository."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,39}$", var.github_owner))
    error_message = "github_owner must be a valid GitHub login."
  }
}

variable "github_repository_name" {
  description = "GitHub repository name, used only to build the job_workflow_ref path pattern."
  type        = string
  default     = "rs-infra"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.github_repository_name))
    error_message = "github_repository_name must be a valid GitHub repository name."
  }
}

variable "github_repository_id" {
  description = "Immutable numeric GitHub repository ID, bound in the OIDC trust policy so a rename or transfer cannot silently change trust."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_repository_id))
    error_message = "github_repository_id must be the repository's immutable numeric ID."
  }
}

variable "github_repository_owner_id" {
  description = "Immutable numeric GitHub owner (org or user) ID, bound in the OIDC trust policy."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id must be the owner's immutable numeric ID."
  }
}

variable "gateway_github_repository_name" {
  description = "Private gateway repository name used to bind the image-build workflow identity."
  type        = string
  default     = "rs-gateway"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.gateway_github_repository_name))
    error_message = "gateway_github_repository_name must be a valid GitHub repository name."
  }
}

variable "gateway_github_repository_id" {
  description = "Immutable numeric ID of the private gateway repository trusted to build AMIs."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.gateway_github_repository_id))
    error_message = "gateway_github_repository_id must be the repository's immutable numeric ID."
  }
}

variable "state_object_keys" {
  description = "Exact state object key for each deployable stack, keyed by stack name. These become the TF_<STACK>_STATE_KEY repository variables."
  type        = map(string)

  validation {
    condition     = toset(keys(var.state_object_keys)) == toset(["network", "gateway", "cluster", "dns"])
    error_message = "state_object_keys must define exactly one key for each of: network, gateway, cluster, dns."
  }

  validation {
    condition = alltrue([
      for key in values(var.state_object_keys) :
      can(regex("^[A-Za-z0-9._/-]+\\.tfstate$", key)) && !can(regex("\\.\\.", key)) && substr(key, 0, 1) != "/"
    ])
    error_message = "Each state object key must be a safe relative path ending in .tfstate, matching the shape enforced by terraform-plan.sh and terraform-apply.sh."
  }
}

variable "state_versioning_noncurrent_expiration_days" {
  description = "Days a noncurrent state object version is retained before expiring; bucket versioning is the state recovery path."
  type        = number
  default     = 365
}

variable "plan_object_lock_retention_days" {
  description = "GOVERNANCE-mode Object Lock default retention applied to every object written to the private plan bucket."
  type        = number
  default     = 90
}

variable "plan_bucket_lifecycle_expiration_days" {
  description = "Days after which objects in the private plan bucket expire; must exceed plan_object_lock_retention_days."
  type        = number
  default     = 400

  validation {
    condition     = var.plan_bucket_lifecycle_expiration_days > var.plan_object_lock_retention_days
    error_message = "plan_bucket_lifecycle_expiration_days must exceed plan_object_lock_retention_days so Object Lock never blocks a scheduled expiration."
  }
}

variable "state_kms_deletion_window_days" {
  description = "Deletion window for the Terraform state KMS key."
  type        = number
  default     = 30
}

variable "plan_kms_deletion_window_days" {
  description = "Deletion window for the reviewed-plan bucket KMS key."
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
