output "stack" {
  description = "Stable identifier for this independent Terraform stack."
  value       = "cluster"
}

output "platform_api_private_dns" {
  description = "Split-horizon Route53 contract consumed by private Traefik and cluster workloads."
  value = {
    hostname       = aws_route53_record.platform_api_private.fqdn
    hosted_zone_id = aws_route53_zone.platform_api_private.zone_id
    name_servers   = aws_route53_zone.platform_api_private.name_servers
    ipv4_addresses = sort(tolist(var.platform_api_private_ipv4_addresses))
  }
}

output "platform_api_tls_contract" {
  description = "Hostname-only TLS contract for private Traefik; certificate issuance and private-key custody remain in rs-cloud/cert-manager."
  value = {
    hostname                      = var.platform_api_hostname
    dns_names                     = [var.platform_api_hostname]
    certificate_owner             = "rs-cloud/cert-manager"
    termination_owner             = "rs-cloud/Traefik"
    terraform_manages_private_key = false
    terraform_manages_certificate = false
  }
}

output "console_backup_bucket" {
  description = "Encrypted, versioned S3 destination contract for CloudNativePG backups."
  value = {
    name          = aws_s3_bucket.console_backup.id
    arn           = aws_s3_bucket.console_backup.arn
    region        = var.aws_region
    object_prefix = var.console_backup_object_prefix
    kms_key_arn   = aws_kms_key.console_backup.arn
    kms_alias_arn = aws_kms_alias.console_backup.arn
  }
}

output "console_backup_service_account_federation" {
  description = "Exact Kubernetes service-account federation contract consumed by rs-cloud."
  value = {
    namespace       = var.console_backup_service_account_namespace
    service_account = var.console_backup_service_account_name
    subject         = "system:serviceaccount:${var.console_backup_service_account_namespace}:${var.console_backup_service_account_name}"
    role_arn        = aws_iam_role.console_backup.arn
  }
}

output "console_secret_parameter_contract" {
  description = "Parameter Store names and ARNs populated outside Terraform; no aws_ssm_parameter values are created by this stack."
  value = {
    prefix = var.console_parameter_prefix
    paths  = local.console_secret_parameter_paths
    arns   = local.console_secret_parameter_arns
  }
}

output "console_backup_iam_scope" {
  description = "Auditable least-privilege action and resource contract used by the console backup role."
  value = {
    bucket_actions = local.console_backup_bucket_actions
    bucket_arn     = local.console_backup_bucket_arn
    object_actions = local.console_backup_object_actions
    object_arn     = local.console_backup_object_arn
    kms_actions    = local.console_backup_kms_actions
    kms_key_arn    = aws_kms_key.console_backup.arn
  }
}
