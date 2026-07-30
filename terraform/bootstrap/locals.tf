locals {
  name_prefix = "${var.project}-${var.environment}-bootstrap"

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

  # The four independent deployable stacks whose state this backend hosts and
  # whose CI identities this stack trusts. `bootstrap` itself is intentionally
  # excluded: it is operator-applied, per README.md and CLAUDE.md.
  deployable_stacks = ["network", "gateway", "cluster", "dns"]

  state_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.state.id}"
  plan_bucket_arn  = "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.plan.id}"

  # Native S3 state locking (`use_lockfile = true`) takes its lock via a
  # conditional write to "<key>.tflock" in the same bucket; no DynamoDB table
  # is used.
  state_object_arns = {
    for stack, key in var.state_object_keys :
    stack => "${local.state_bucket_arn}/${key}"
  }
  state_lock_object_arns = {
    for stack, key in var.state_object_keys :
    stack => "${local.state_bucket_arn}/${key}.tflock"
  }

  # Reviewed-plan bundles are immutable once written; bundle_object_key layout
  # is fixed by terraform-plan.sh: plans/{repo_id}/{stack}/pull-request/{pr}/
  # {head_sha}/{run_id}-{run_attempt}/reviewed-plan.tgz. The mutable pointer,
  # apply logs, and application receipts share the same per-stack prefix.
  plan_bucket_repository_prefix  = "plans/${var.github_repository_id}"
  plan_bundle_immutable_resource = "${local.plan_bucket_arn}/${local.plan_bucket_repository_prefix}/*/pull-request/*/*/*/reviewed-plan.tgz"
  plan_bucket_stack_prefix_arns = {
    for stack in local.deployable_stacks :
    stack => "${local.plan_bucket_arn}/${local.plan_bucket_repository_prefix}/${stack}/*"
  }
  application_bucket_stack_prefix_arns = {
    for stack in local.deployable_stacks :
    stack => "${local.plan_bucket_arn}/applications/${var.github_repository_id}/${stack}/*"
  }

  # job_workflow_ref is path-based, not an immutable ID; it is combined with
  # the StringEquals repository_id/repository_owner_id conditions below so
  # that trust is bound to the immutable repository, not its current name.
  plan_workflow_refs = [
    for stack in local.deployable_stacks :
    "${var.github_owner}/${var.github_repository_name}/.github/workflows/terraform-${stack}.yml@refs/pull/*/merge"
  ]
  apply_workflow_refs = [
    for stack in local.deployable_stacks :
    "${var.github_owner}/${var.github_repository_name}/.github/workflows/terraform-${stack}.yml@refs/heads/main"
  ]
}
