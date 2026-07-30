# --- Terraform state: versioned bucket, native S3 locking, dedicated KMS key ---

resource "aws_kms_key" "state" {
  description             = "Encrypts the RS Platform Terraform state bucket"
  deletion_window_in_days = var.state_kms_deletion_window_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "TerraformCiStateAccess"
        Effect = "Allow"
        Principal = {
          AWS = [aws_iam_role.plan.arn, aws_iam_role.apply.arn]
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name = "${local.name_prefix}-state"
  }
}

resource "aws_kms_alias" "state" {
  name          = "alias/${local.name_prefix}-state"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  bucket = "${local.name_prefix}-state-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-state"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.state_versioning_noncurrent_expiration_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json
}

# --- Private reviewed-plan bucket: Object Lock, immutable bundles, dedicated KMS key ---

resource "aws_kms_key" "plan" {
  description             = "Encrypts the RS Platform private Terraform plan bucket"
  deletion_window_in_days = var.plan_kms_deletion_window_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "PlanRoleWriteOnly"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.plan.arn }
        Action = [
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
        ]
        Resource = "*"
      },
      {
        Sid       = "ApplyRoleReadWrite"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.apply.arn }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name = "${local.name_prefix}-plan"
  }
}

resource "aws_kms_alias" "plan" {
  name          = "alias/${local.name_prefix}-plan"
  target_key_id = aws_kms_key.plan.key_id
}

resource "aws_s3_bucket" "plan" {
  bucket              = "${local.name_prefix}-plans-${data.aws_caller_identity.current.account_id}"
  object_lock_enabled = true

  tags = {
    Name = "${local.name_prefix}-plans"
  }
}

resource "aws_s3_bucket_versioning" "plan" {
  bucket = aws_s3_bucket.plan.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "plan" {
  bucket = aws_s3_bucket.plan.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.plan_object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.plan]
}

resource "aws_s3_bucket_ownership_controls" "plan" {
  bucket = aws_s3_bucket.plan.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "plan" {
  bucket = aws_s3_bucket.plan.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "plan" {
  bucket = aws_s3_bucket.plan.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.plan.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "plan" {
  bucket = aws_s3_bucket.plan.id

  rule {
    id     = "expire-plan-artifacts"
    status = "Enabled"

    expiration {
      days = var.plan_bucket_lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.plan_bucket_lifecycle_expiration_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.plan]
}

data "aws_iam_policy_document" "plan_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [local.plan_bucket_arn, "${local.plan_bucket_arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyBypassGovernanceRetention"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:BypassGovernanceRetention"]
    resources = ["${local.plan_bucket_arn}/*"]
  }

  # Reviewed-plan bundles are written once per workflow run at a unique key;
  # this forces every write to that exact path to prove non-existence via
  # If-None-Match, so a bug or operator action can never silently replace a
  # bundle a reviewer already approved. Object Lock above additionally stops
  # a locked version from being deleted. The mutable per-PR pointer is
  # outside this resource pattern and is not restricted here.
  statement {
    sid    = "DenyReviewedPlanBundleOverwrite"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = [local.plan_bundle_immutable_resource]

    condition {
      test     = "Null"
      variable = "s3:if-none-match"
      values   = ["true"]
    }
  }
}

resource "aws_s3_bucket_policy" "plan" {
  bucket = aws_s3_bucket.plan.id
  policy = data.aws_iam_policy_document.plan_bucket.json
}
