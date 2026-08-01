output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider trusted by the plan, apply, and image-build CI roles."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "plan_role_arn" {
  description = "Read-only Terraform plan role; set as the TF_PLAN_ROLE_ARN repository variable."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Mutating Terraform apply role; set as the TF_APPLY_ROLE_ARN repository variable."
  value       = aws_iam_role.apply.arn
}

output "image_build_role_arn" {
  description = "Gateway AMI build role; configure as IMAGE_BUILD_ROLE_ARN in the private rs-gateway repository."
  value       = aws_iam_role.image_build.arn
}

output "image_builder_instance_profile_name" {
  description = "Build-only SSM instance profile; configure as IMAGE_BUILDER_INSTANCE_PROFILE in private rs-gateway."
  value       = aws_iam_instance_profile.packer_builder.name
}

output "state_bucket_name" {
  description = "Versioned Terraform state bucket; set as the TF_STATE_BUCKET repository variable."
  value       = aws_s3_bucket.state.id
}

output "state_kms_key_arn" {
  description = "State-bucket KMS key ARN; set as the TF_STATE_KMS_KEY_ID repository variable."
  value       = aws_kms_key.state.arn
}

output "plan_bucket_name" {
  description = "Private reviewed-plan and apply-log bucket; set as the TF_PLAN_BUCKET repository variable."
  value       = aws_s3_bucket.plan.id
}

output "plan_kms_key_arn" {
  description = "Reviewed-plan bucket KMS key ARN; set as the TF_PLAN_KMS_KEY_ID repository variable."
  value       = aws_kms_key.plan.arn
}

output "network_state_key" {
  description = "Network stack state object key; set as the TF_NETWORK_STATE_KEY repository variable."
  value       = var.state_object_keys["network"]
}

output "gateway_state_key" {
  description = "Gateway stack state object key; set as the TF_GATEWAY_STATE_KEY repository variable."
  value       = var.state_object_keys["gateway"]
}

output "cluster_state_key" {
  description = "Cluster stack state object key; set as the TF_CLUSTER_STATE_KEY repository variable."
  value       = var.state_object_keys["cluster"]
}

output "dns_state_key" {
  description = "DNS stack state object key; set as the TF_DNS_STATE_KEY repository variable."
  value       = var.state_object_keys["dns"]
}
