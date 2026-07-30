# --- Trust: immutable-ID-bound GitHub Actions OIDC federation ---

data "aws_iam_policy_document" "plan_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository_owner_id"
      values   = [var.github_repository_owner_id]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository_id"
      values   = [var.github_repository_id]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = local.plan_workflow_refs
    }
  }
}

data "aws_iam_policy_document" "apply_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository_owner_id"
      values   = [var.github_repository_owner_id]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository_id"
      values   = [var.github_repository_id]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = local.apply_workflow_refs
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:environment"
      values   = ["apply"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name               = "rs-infra-plan"
  description        = "Read-only Terraform plan role, assumable only by trusted same-repository pull requests."
  assume_role_policy = data.aws_iam_policy_document.plan_assume_role.json

  tags = {
    Name = "rs-infra-plan"
  }
}

resource "aws_iam_role" "apply" {
  name               = "rs-infra-apply"
  description        = "Mutating Terraform apply role, assumable only from protected main through the apply environment."
  assume_role_policy = data.aws_iam_policy_document.apply_assume_role.json

  tags = {
    Name = "rs-infra-apply"
  }
}

# --- rs-infra-plan: read-only provider surface, state read, lock take/release, plan-bucket write ---

data "aws_iam_policy_document" "plan_permissions" {
  statement {
    sid = "ReadOnlyProviderSurface"
    actions = [
      "ec2:Describe*",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:GetInstanceProfile",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRoleTags",
      "iam:ListInstanceProfileTags",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "kms:ListResourceTags",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
      "secretsmanager:GetResourcePolicy",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadExactStateObjects"
    actions   = ["s3:GetObject"]
    resources = values(local.state_object_arns)
  }

  statement {
    sid = "TakeAndReleaseNativeStateLocks"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = values(local.state_lock_object_arns)
  }

  statement {
    sid = "UseStateKmsKeyForReadAndLock"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.state.arn]
  }

  statement {
    sid       = "WriteOwnStackPlanArtifacts"
    actions   = ["s3:PutObject"]
    resources = values(local.plan_bucket_stack_prefix_arns)
  }

  statement {
    sid = "UsePlanKmsKeyWriteOnly"
    actions = [
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.plan.arn]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "rs-infra-plan"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_permissions.json
}

# --- rs-infra-apply: mutating provider surface, state read/write, plan-bucket read/write ---

data "aws_iam_policy_document" "apply_permissions" {
  statement {
    sid = "ReadOnlyProviderSurface"
    actions = [
      "ec2:Describe*",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:GetInstanceProfile",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRoleTags",
      "iam:ListInstanceProfileTags",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "kms:ListResourceTags",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
      "secretsmanager:GetResourcePolicy",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid = "NetworkVpcLifecycle"
    actions = [
      "ec2:CreateVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:DeleteVpc",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:CreateInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:CreateSubnet",
      "ec2:ModifySubnetAttribute",
      "ec2:DeleteSubnet",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:CreateRoute",
      "ec2:ReplaceRoute",
      "ec2:DeleteRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:CreateVpcEndpoint",
      "ec2:ModifyVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
    ]
    resources = ["*"]
  }

  statement {
    sid = "GatewayComputeLifecycle"
    actions = [
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StopInstances",
      "ec2:StartInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:MonitorInstances",
      "ec2:UnmonitorInstances",
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
    ]
    resources = ["*"]
  }

  statement {
    sid = "GatewayIamRoleLifecycle"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*",
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.project}-*",
    ]
  }

  statement {
    sid       = "GatewayInstanceProfilePassRole"
    actions   = ["iam:PassRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid = "SecretContainerLifecycle"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:UpdateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:PutResourcePolicy",
      "secretsmanager:DeleteResourcePolicy",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/*"]
  }

  statement {
    sid = "SecretsKmsKeyLifecycle"
    actions = [
      "kms:CreateKey",
      "kms:PutKeyPolicy",
      "kms:EnableKeyRotation",
      "kms:DisableKey",
      "kms:EnableKey",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateKeyDescription",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateAlias",
    ]
    # KMS key and alias IDs do not exist before creation, so resource-level
    # scoping is not possible for these lifecycle actions.
    resources = ["*"]
  }

  statement {
    sid = "ObservabilityLifecycle"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:TagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "MutateExactStateObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = values(local.state_object_arns)
  }

  statement {
    sid = "TakeAndReleaseNativeStateLocks"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = values(local.state_lock_object_arns)
  }

  statement {
    sid = "UseStateKmsKey"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.state.arn]
  }

  statement {
    sid       = "ReadReviewedPlanArtifacts"
    actions   = ["s3:GetObject"]
    resources = values(local.plan_bucket_stack_prefix_arns)
  }

  statement {
    sid       = "WriteApplyReceipts"
    actions   = ["s3:PutObject"]
    resources = values(local.application_bucket_stack_prefix_arns)
  }

  statement {
    sid = "UsePlanKmsKey"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.plan.arn]
  }

  # Terraform creates secret containers only; it must never read or write a
  # secret value. This turns that convention into a boundary CI cannot cross,
  # even if a future statement above is accidentally broadened.
  statement {
    sid    = "DenySecretValueAccess"
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "ssm:PutParameter",
    ]
    resources = ["*"]
  }

  # The apply role must never be able to widen its own or the plan role's
  # trust or permissions, tamper with the OIDC provider that authenticates
  # both, or weaken the backend buckets' governance controls.
  statement {
    sid    = "DenySelfEscalation"
    effect = "Deny"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
      "iam:TagRole",
      "iam:UntagRole",
    ]
    resources = [aws_iam_role.plan.arn, aws_iam_role.apply.arn]
  }

  statement {
    sid    = "DenyOidcProviderTamper"
    effect = "Deny"
    actions = [
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
    ]
    resources = [aws_iam_openid_connect_provider.github_actions.arn]
  }

  statement {
    sid    = "DenyBackendGovernanceTamper"
    effect = "Deny"
    actions = [
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketVersioning",
      "s3:PutBucketOwnershipControls",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketObjectLockConfiguration",
      "s3:PutBucketAcl",
    ]
    resources = [
      local.state_bucket_arn,
      local.plan_bucket_arn,
      "${local.state_bucket_arn}/*",
      "${local.plan_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "rs-infra-apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_permissions.json
}
