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

data "aws_iam_policy_document" "image_build_assume_role" {
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
      values = [
        "${var.github_owner}/${var.github_repository_name}/.github/workflows/_reusable-image-gateway-build.yml@refs/pull/*/merge",
      ]
    }
  }
}

data "aws_iam_policy_document" "packer_builder_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
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

resource "aws_iam_role" "image_build" {
  name               = "rs-infra-image-build"
  description        = "Gateway AMI build role, assumable only by trusted same-repository image pull requests."
  assume_role_policy = data.aws_iam_policy_document.image_build_assume_role.json

  tags = {
    Name = "rs-infra-image-build"
  }
}

resource "aws_iam_role" "packer_builder" {
  name               = "rs-infra-image-builder"
  description        = "Build-only EC2 profile used by Packer through SSM Session Manager."
  assume_role_policy = data.aws_iam_policy_document.packer_builder_assume_role.json

  tags = {
    Name = "rs-infra-image-builder"
  }
}

resource "aws_iam_instance_profile" "packer_builder" {
  name = "rs-infra-image-builder"
  role = aws_iam_role.packer_builder.name
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

# --- rs-infra-image-build: bounded Packer EC2/AMI lifecycle ---

data "aws_iam_policy_document" "packer_builder_permissions" {
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

resource "aws_iam_role_policy" "packer_builder" {
  name   = "rs-infra-image-builder"
  role   = aws_iam_role.packer_builder.id
  policy = data.aws_iam_policy_document.packer_builder_permissions.json
}

data "aws_iam_policy_document" "image_build_permissions" {
  statement {
    sid = "ReadEc2BuildSurface"
    actions = [
      "ec2:Describe*",
      "ec2:GetPasswordData",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid = "BuildGatewayAmi"
    actions = [
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateImage",
      "ec2:CreateKeyPair",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSnapshot",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteKeyPair",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSnapshot",
      "ec2:DeleteTags",
      "ec2:DeleteVolume",
      "ec2:DeregisterImage",
      "ec2:DetachVolume",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifySnapshotAttribute",
      "ec2:RegisterImage",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "LaunchExactBuilderSize"
    actions   = ["ec2:RunInstances"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:InstanceType"
      values   = ["t4g.small"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/rs:component"
      values   = ["gateway-image-build"]
    }
  }

  statement {
    sid = "ReadExactBuilderProfile"
    actions = [
      "iam:GetInstanceProfile",
      "iam:GetRole",
    ]
    resources = [
      aws_iam_instance_profile.packer_builder.arn,
      aws_iam_role.packer_builder.arn,
    ]
  }

  statement {
    sid       = "StartSessionOnTaggedBuilder"
    actions   = ["ssm:StartSession"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/rs:component"
      values   = ["gateway-image-build"]
    }
  }

  statement {
    sid       = "UsePortForwardingSessionDocument"
    actions   = ["ssm:StartSession"]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::document/AWS-StartPortForwardingSession"]
  }

  statement {
    sid       = "TerminateOwnBuilderSessions"
    actions   = ["ssm:TerminateSession"]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:session/gha-gateway-image-pr-*"]
  }

  statement {
    sid       = "PassExactBuilderRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.packer_builder.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

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
}

resource "aws_iam_role_policy" "image_build" {
  name   = "rs-infra-image-build"
  role   = aws_iam_role.image_build.id
  policy = data.aws_iam_policy_document.image_build_permissions.json
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

  # The apply role must never be able to widen any CI/build role's trust or
  # permissions, tamper with the OIDC provider that authenticates them, or
  # weaken the backend buckets' governance controls.
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
    resources = [
      aws_iam_role.plan.arn,
      aws_iam_role.apply.arn,
      aws_iam_role.image_build.arn,
      aws_iam_role.packer_builder.arn,
    ]
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
