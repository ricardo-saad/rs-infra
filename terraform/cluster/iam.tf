data "aws_iam_policy_document" "console_backup_assume_role" {
  statement {
    sid     = "AssumeFromExactConsoleBackupServiceAccount"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_condition_prefix}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_condition_prefix}:sub"
      values   = ["system:serviceaccount:${var.console_backup_service_account_namespace}:${var.console_backup_service_account_name}"]
    }
  }
}

resource "aws_iam_role" "console_backup" {
  name               = "${local.name_prefix}-console-backup"
  description        = "Federated access for the exact console PostgreSQL backup service account."
  assume_role_policy = data.aws_iam_policy_document.console_backup_assume_role.json

  tags = {
    Name = "${local.name_prefix}-console-backup"
  }
}

data "aws_iam_policy_document" "console_backup" {
  statement {
    sid       = "ReadExactBackupBucketMetadata"
    actions   = local.console_backup_bucket_metadata_actions
    resources = [local.console_backup_bucket_arn]
  }

  statement {
    sid       = "ListExactBackupPrefix"
    actions   = local.console_backup_bucket_list_actions
    resources = [local.console_backup_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.console_backup_object_prefix}*"]
    }
  }

  statement {
    sid       = "ReadWriteExactBackupPrefix"
    actions   = local.console_backup_object_actions
    resources = [local.console_backup_object_arn]
  }

  statement {
    sid       = "UseExactBackupKmsKey"
    actions   = local.console_backup_kms_actions
    resources = [aws_kms_key.console_backup.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "console_backup" {
  name   = "${local.name_prefix}-console-backup"
  role   = aws_iam_role.console_backup.id
  policy = data.aws_iam_policy_document.console_backup.json
}
