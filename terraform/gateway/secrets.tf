resource "aws_kms_key" "gateway" {
  description             = "Encrypts the two RS Platform gateway recovery secrets"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid       = "AccountAdministration"
          Effect    = "Allow"
          Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
          Action    = "kms:*"
          Resource  = "*"
        },
        {
          Sid       = "RuntimeDecrypt"
          Effect    = "Allow"
          Principal = { AWS = aws_iam_role.runtime.arn }
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey",
          ]
          Resource = "*"
        },
      ],
      var.gateway_profile_mode == "bootstrap" ? [
        {
          Sid       = "BootstrapSecretMaterial"
          Effect    = "Allow"
          Principal = { AWS = aws_iam_role.bootstrap[0].arn }
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey",
            "kms:Encrypt",
            "kms:GenerateDataKey",
          ]
          Resource = "*"
        },
      ] : [],
    )
  })

  tags = {
    Name = "${local.name_prefix}-secrets"
  }
}

resource "aws_kms_alias" "gateway" {
  name          = "alias/${local.name_prefix}-secrets"
  target_key_id = aws_kms_key.gateway.key_id
}

resource "aws_secretsmanager_secret" "wireguard" {
  name                    = "rs-platform/gateway/wireguard"
  description             = "Recovery container for the three gateway WireGuard interface private keys"
  kms_key_id              = aws_kms_key.gateway.arn
  recovery_window_in_days = var.secret_recovery_window_days

  tags = {
    Name = "${local.name_prefix}-wireguard"
  }
}

resource "aws_secretsmanager_secret" "adguard" {
  name                    = "rs-platform/gateway/adguard"
  description             = "Recovery container for gateway AdGuard administrative credential material"
  kms_key_id              = aws_kms_key.gateway.arn
  recovery_window_in_days = var.secret_recovery_window_days

  tags = {
    Name = "${local.name_prefix}-adguard"
  }
}
