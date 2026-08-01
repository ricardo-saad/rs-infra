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

  mock_resource "aws_kms_key" {
    override_during = plan

    defaults = {
      arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  vpc_id                              = "vpc-0123456789abcdef0"
  platform_api_private_ipv4_addresses = ["10.0.1.20"]
  cluster_oidc_provider_arn           = "arn:aws:iam::123456789012:oidc-provider/oidc.example.invalid"
  cluster_oidc_issuer_url             = "https://oidc.example.invalid"
  owner                               = "test-owner"
  cost_center                         = "test-cost-center"
}

run "auth_foundations_are_bounded" {
  command = plan

  assert {
    condition     = aws_route53_zone.platform_api_private.name == "platform-api.ricardosaad.com"
    error_message = "The private zone must be scoped to the canonical platform API hostname."
  }

  assert {
    condition     = one(aws_route53_zone.platform_api_private.vpc).vpc_id == var.vpc_id
    error_message = "The private zone must be associated only with the supplied platform VPC."
  }

  assert {
    condition     = aws_s3_bucket_versioning.console_backup.versioning_configuration[0].status == "Enabled"
    error_message = "The console backup bucket must keep versioning enabled."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.console_backup.rule).status == "Enabled"
    error_message = "The console backup lifecycle policy must remain enabled."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.console_backup.block_public_acls &&
      aws_s3_bucket_public_access_block.console_backup.block_public_policy &&
      aws_s3_bucket_public_access_block.console_backup.ignore_public_acls &&
      aws_s3_bucket_public_access_block.console_backup.restrict_public_buckets
    )
    error_message = "Every S3 public-access-block control must remain enabled."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.console_backup.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "The console backup bucket must use KMS encryption by default."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.console_backup.rule).apply_server_side_encryption_by_default).kms_master_key_id == aws_kms_key.console_backup.arn
    error_message = "The backup bucket must use its dedicated KMS key."
  }

  assert {
    condition = alltrue([
      for action in concat(
        output.console_backup_iam_scope.bucket_actions,
        output.console_backup_iam_scope.object_actions,
        output.console_backup_iam_scope.kms_actions,
      ) : action != "*" && !endswith(action, ":*")
    ])
    error_message = "The backup role must not contain wildcard actions."
  }

  assert {
    condition     = output.console_backup_iam_scope.object_arn == "arn:aws:s3:::rs-platform-production-cluster-console-backups-123456789012/postgresql/*"
    error_message = "The backup role must remain scoped to the exact PostgreSQL object prefix."
  }

  assert {
    condition     = output.platform_api_tls_contract.terraform_manages_private_key == false
    error_message = "Terraform must never manage the platform API certificate private key."
  }
}

run "reject_noncanonical_platform_api_hostname" {
  command = plan

  variables {
    platform_api_hostname = "other.ricardosaad.com"
  }

  expect_failures = [
    var.platform_api_hostname,
  ]
}
