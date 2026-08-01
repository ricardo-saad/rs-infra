data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

check "platform_api_private_zone_is_narrow" {
  assert {
    condition     = local.platform_api_private_zone_name == var.platform_api_hostname
    error_message = "The private hosted zone must be scoped to the platform API hostname so unrelated public names continue resolving."
  }
}

check "cluster_oidc_inputs_match" {
  assert {
    condition     = endswith(var.cluster_oidc_provider_arn, "oidc-provider/${local.oidc_issuer_condition_prefix}")
    error_message = "cluster_oidc_provider_arn and cluster_oidc_issuer_url must identify the same issuer."
  }
}

check "console_backup_bucket_name_is_valid" {
  assert {
    condition     = length(local.console_backup_bucket_name) <= 63
    error_message = "The derived console backup bucket name must not exceed S3's 63-character limit."
  }
}

check "console_backup_iam_is_prefix_scoped" {
  assert {
    condition = alltrue([
      for action in concat(
        local.console_backup_bucket_actions,
        local.console_backup_object_actions,
        local.console_backup_kms_actions,
      ) : action != "*" && !endswith(action, ":*")
    ])
    error_message = "The console backup IAM contract must enumerate actions and may not contain wildcard actions."
  }
}
