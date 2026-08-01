variable "aws_region" {
  description = "AWS region for cluster-envelope resources."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = var.aws_region == "eu-west-2"
    error_message = "The accepted cluster envelope is fixed to eu-west-2."
  }
}

variable "vpc_id" {
  description = "VPC ID exported by the network stack and associated with the platform API private hosted zone."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be an EC2 VPC ID."
  }
}

variable "platform_api_hostname" {
  description = "Canonical console API hostname shared by public Cloudflare DNS, private Route53 DNS, WebAuthn, and TLS."
  type        = string
  default     = "platform-api.ricardosaad.com"

  validation {
    condition     = var.platform_api_hostname == "platform-api.ricardosaad.com"
    error_message = "ADR-0037 fixes platform_api_hostname to platform-api.ricardosaad.com."
  }
}

variable "platform_api_private_ipv4_addresses" {
  description = "Private Traefik IPv4 addresses published by the split-horizon platform API record."
  type        = set(string)

  validation {
    condition = length(var.platform_api_private_ipv4_addresses) > 0 && alltrue([
      for address in var.platform_api_private_ipv4_addresses :
      can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", address)) &&
      can(regex("^(?:10\\.|192\\.168\\.|172\\.(?:1[6-9]|2[0-9]|3[01])\\.)", address)) &&
      can(cidrhost("${address}/32", 0))
    ])
    error_message = "platform_api_private_ipv4_addresses must contain at least one valid RFC1918 IPv4 address."
  }
}

variable "platform_api_private_record_ttl" {
  description = "TTL in seconds for the private platform API A record."
  type        = number
  default     = 60

  validation {
    condition     = var.platform_api_private_record_ttl >= 30 && var.platform_api_private_record_ttl <= 300
    error_message = "platform_api_private_record_ttl must be between 30 and 300 seconds."
  }
}

variable "cluster_oidc_provider_arn" {
  description = "IAM OIDC provider ARN for the private Talos cluster service-account issuer."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:oidc-provider/.+$", var.cluster_oidc_provider_arn))
    error_message = "cluster_oidc_provider_arn must be an IAM OIDC provider ARN."
  }
}

variable "cluster_oidc_issuer_url" {
  description = "HTTPS issuer URL corresponding exactly to cluster_oidc_provider_arn."
  type        = string

  validation {
    condition     = can(regex("^https://[^/]+(?:/.+)?[^/]$", var.cluster_oidc_issuer_url))
    error_message = "cluster_oidc_issuer_url must be an HTTPS URL without a trailing slash."
  }
}

variable "console_backup_service_account_namespace" {
  description = "Kubernetes namespace containing the service account permitted to access console PostgreSQL backups."
  type        = string
  default     = "rs-console"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.console_backup_service_account_namespace))
    error_message = "console_backup_service_account_namespace must be a valid Kubernetes namespace."
  }
}

variable "console_backup_service_account_name" {
  description = "Kubernetes service account federated to the console backup IAM role."
  type        = string
  default     = "console-backup"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.console_backup_service_account_name))
    error_message = "console_backup_service_account_name must be a valid Kubernetes service account name."
  }
}

variable "console_backup_object_prefix" {
  description = "Exclusive S3 object prefix available to the console backup service account."
  type        = string
  default     = "postgresql/"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]*/$", var.console_backup_object_prefix)) && !strcontains(var.console_backup_object_prefix, "..")
    error_message = "console_backup_object_prefix must be a safe, non-empty relative prefix ending in a slash."
  }
}

variable "console_backup_expiration_days" {
  description = "Days before current console backup objects expire through bucket lifecycle."
  type        = number
  default     = 90

  validation {
    condition     = var.console_backup_expiration_days >= 30
    error_message = "console_backup_expiration_days must retain backups for at least 30 days."
  }
}

variable "console_backup_noncurrent_expiration_days" {
  description = "Days before noncurrent console backup object versions expire."
  type        = number
  default     = 30

  validation {
    condition     = var.console_backup_noncurrent_expiration_days >= 7
    error_message = "console_backup_noncurrent_expiration_days must be at least 7 days."
  }
}

variable "console_backup_abort_multipart_days" {
  description = "Days before incomplete console backup multipart uploads are aborted."
  type        = number
  default     = 7

  validation {
    condition     = var.console_backup_abort_multipart_days >= 1
    error_message = "console_backup_abort_multipart_days must be at least 1."
  }
}

variable "console_backup_kms_deletion_window_days" {
  description = "Deletion window for the KMS key protecting console PostgreSQL backups."
  type        = number
  default     = 30

  validation {
    condition     = var.console_backup_kms_deletion_window_days >= 7 && var.console_backup_kms_deletion_window_days <= 30
    error_message = "console_backup_kms_deletion_window_days must be between 7 and 30 days."
  }
}

variable "console_parameter_prefix" {
  description = "Pre-agreed Parameter Store prefix for externally populated console database and runtime secret values."
  type        = string
  default     = "/rs-platform/production/console"

  validation {
    condition     = can(regex("^/[A-Za-z0-9_./-]+[A-Za-z0-9_-]$", var.console_parameter_prefix))
    error_message = "console_parameter_prefix must be a safe absolute Parameter Store path without a trailing slash."
  }
}

variable "project" {
  description = "Project tag applied to supported AWS resources."
  type        = string
  default     = "rs-platform"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$", var.project))
    error_message = "project must be a lowercase DNS-compatible name."
  }
}

variable "environment" {
  description = "Environment tag applied to supported AWS resources."
  type        = string
  default     = "production"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$", var.environment))
    error_message = "environment must be a lowercase DNS-compatible name."
  }
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
  name_prefix = "${var.project}-${var.environment}-cluster"

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

  platform_api_private_zone_name = var.platform_api_hostname
  oidc_issuer_condition_prefix   = trimprefix(var.cluster_oidc_issuer_url, "https://")
  console_backup_bucket_name     = "${local.name_prefix}-console-backups-${data.aws_caller_identity.current.account_id}"
  console_backup_bucket_arn      = "arn:${data.aws_partition.current.partition}:s3:::${local.console_backup_bucket_name}"
  console_backup_object_arn      = "${local.console_backup_bucket_arn}/${var.console_backup_object_prefix}*"

  console_secret_parameter_paths = {
    database_url   = "${var.console_parameter_prefix}/database-url"
    runtime_secret = "${var.console_parameter_prefix}/runtime-secret"
  }
  console_secret_parameter_arns = {
    for name, path in local.console_secret_parameter_paths :
    name => "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${path}"
  }

  console_backup_bucket_metadata_actions = [
    "s3:GetBucketLocation",
  ]
  console_backup_bucket_list_actions = [
    "s3:ListBucket",
    "s3:ListBucketMultipartUploads",
  ]
  console_backup_bucket_actions = concat(
    local.console_backup_bucket_metadata_actions,
    local.console_backup_bucket_list_actions,
  )
  console_backup_object_actions = [
    "s3:AbortMultipartUpload",
    "s3:GetObject",
    "s3:ListMultipartUploadParts",
    "s3:PutObject",
  ]
  console_backup_kms_actions = [
    "kms:Decrypt",
    "kms:DescribeKey",
    "kms:Encrypt",
    "kms:GenerateDataKey",
  ]
}
