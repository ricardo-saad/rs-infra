data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runtime" {
  name               = "${local.name_prefix}-runtime"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "runtime" {
  statement {
    sid = "ReadExactGatewaySecrets"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      aws_secretsmanager_secret.wireguard.arn,
      aws_secretsmanager_secret.adguard.arn,
    ]
  }

  statement {
    sid = "DecryptGatewaySecrets"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.gateway.arn]
  }

  statement {
    sid = "PublishExactPublicKeys"
    actions = [
      "ssm:PutParameter",
    ]
    resources = local.public_key_parameter_arns
  }

  statement {
    sid = "PublishGatewayMetrics"
    actions = [
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.metrics_namespace]
    }
  }

  statement {
    sid = "WriteGatewayLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.gateway.arn}:*"]
  }

  statement {
    sid = "SessionManagerControl"
    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "runtime" {
  name   = "${local.name_prefix}-runtime"
  role   = aws_iam_role.runtime.id
  policy = data.aws_iam_policy_document.runtime.json
}

resource "aws_iam_instance_profile" "runtime" {
  name = "${local.name_prefix}-runtime"
  role = aws_iam_role.runtime.name
}

resource "aws_iam_role" "bootstrap" {
  count = var.gateway_profile_mode == "bootstrap" ? 1 : 0

  name               = "${local.name_prefix}-bootstrap"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "bootstrap" {
  count = var.gateway_profile_mode == "bootstrap" ? 1 : 0

  statement {
    sid = "BootstrapExactGatewaySecrets"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:PutSecretValue",
    ]
    resources = [
      aws_secretsmanager_secret.wireguard.arn,
      aws_secretsmanager_secret.adguard.arn,
    ]
  }

  statement {
    sid = "EncryptGatewaySecrets"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.gateway.arn]
  }

  statement {
    sid = "PublishExactPublicKeys"
    actions = [
      "ssm:PutParameter",
    ]
    resources = local.public_key_parameter_arns
  }

  statement {
    sid       = "ReportBootstrapCompletion"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.metrics_namespace]
    }
  }

  statement {
    sid = "WriteGatewayLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.gateway.arn}:*"]
  }

  statement {
    sid = "SessionManagerControl"
    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "bootstrap" {
  count = var.gateway_profile_mode == "bootstrap" ? 1 : 0

  name   = "${local.name_prefix}-bootstrap"
  role   = aws_iam_role.bootstrap[0].id
  policy = data.aws_iam_policy_document.bootstrap[0].json
}

resource "aws_iam_instance_profile" "bootstrap" {
  count = var.gateway_profile_mode == "bootstrap" ? 1 : 0

  name = "${local.name_prefix}-bootstrap"
  role = aws_iam_role.bootstrap[0].name
}
