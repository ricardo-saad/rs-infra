resource "aws_kms_key" "console_backup" {
  description             = "Encrypts RS Platform console PostgreSQL backup objects"
  deletion_window_in_days = var.console_backup_kms_deletion_window_days
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
        Sid       = "ConsoleBackupServiceAccountUse"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.console_backup.arn }
        Action    = local.console_backup_kms_actions
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"
          }
        }
      },
    ]
  })

  tags = {
    Name = "${local.name_prefix}-console-backups"
  }
}

resource "aws_kms_alias" "console_backup" {
  name          = "alias/${local.name_prefix}-console-backups"
  target_key_id = aws_kms_key.console_backup.key_id
}

resource "aws_s3_bucket" "console_backup" {
  bucket = local.console_backup_bucket_name

  tags = {
    Name = "${local.name_prefix}-console-backups"
  }
}

resource "aws_s3_bucket_versioning" "console_backup" {
  bucket = aws_s3_bucket.console_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "console_backup" {
  bucket = aws_s3_bucket.console_backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "console_backup" {
  bucket = aws_s3_bucket.console_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "console_backup" {
  bucket = aws_s3_bucket.console_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.console_backup.arn
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "console_backup" {
  bucket = aws_s3_bucket.console_backup.id

  rule {
    id     = "expire-console-backups"
    status = "Enabled"

    filter {
      prefix = var.console_backup_object_prefix
    }

    expiration {
      days = var.console_backup_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.console_backup_noncurrent_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.console_backup_abort_multipart_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.console_backup]
}

data "aws_iam_policy_document" "console_backup_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [local.console_backup_bucket_arn, "${local.console_backup_bucket_arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyExplicitNonKmsEncryption"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = [local.console_backup_object_arn]

    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["false"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  statement {
    sid    = "DenyExplicitWrongKmsKey"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = [local.console_backup_object_arn]

    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = ["false"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [aws_kms_key.console_backup.arn]
    }
  }

  statement {
    sid    = "DenyCustomerProvidedEncryptionKeys"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = [local.console_backup_object_arn]

    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption-customer-algorithm"
      values   = ["false"]
    }
  }

  statement {
    sid     = "AllowExactBackupBucketMetadata"
    effect  = "Allow"
    actions = local.console_backup_bucket_metadata_actions

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.console_backup.arn]
    }

    resources = [local.console_backup_bucket_arn]
  }

  statement {
    sid     = "AllowExactBackupPrefixListing"
    effect  = "Allow"
    actions = local.console_backup_bucket_list_actions

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.console_backup.arn]
    }

    resources = [local.console_backup_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.console_backup_object_prefix}*"]
    }
  }

  statement {
    sid     = "AllowExactBackupObjectPrefix"
    effect  = "Allow"
    actions = local.console_backup_object_actions

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.console_backup.arn]
    }

    resources = [local.console_backup_object_arn]
  }
}

resource "aws_s3_bucket_policy" "console_backup" {
  bucket = aws_s3_bucket.console_backup.id
  policy = data.aws_iam_policy_document.console_backup_bucket.json
}
