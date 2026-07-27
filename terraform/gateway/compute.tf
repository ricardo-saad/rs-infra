resource "aws_instance" "gateway" {
  ami                         = var.gateway_ami_id
  instance_type               = var.gateway_instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.gateway.id]
  associate_public_ip_address = false
  source_dest_check           = false
  monitoring                  = true
  user_data_replace_on_change = true

  iam_instance_profile = var.gateway_profile_mode == "bootstrap" ? aws_iam_instance_profile.bootstrap[0].name : aws_iam_instance_profile.runtime.name

  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    encrypted             = true
    delete_on_termination = true
    volume_size           = var.root_volume_size_gib
    volume_type           = var.root_volume_type
  }

  user_data = templatefile("${path.module}/templates/runtime-env.sh.tftpl", {
    aws_region_b64                  = base64encode(var.aws_region)
    wireguard_secret_id_b64         = base64encode(aws_secretsmanager_secret.wireguard.name)
    adguard_secret_id_b64           = base64encode(aws_secretsmanager_secret.adguard.name)
    public_key_parameter_prefix_b64 = base64encode(trimsuffix(var.ssm_public_key_prefix, "/"))
    metrics_namespace_b64           = base64encode(var.metrics_namespace)
    wan_interface_b64               = base64encode(var.gateway_interface_device)
    build_version_b64               = base64encode(var.gateway_build_version)
    gateway_profile_mode_b64        = base64encode(var.gateway_profile_mode)
  })

  tags = {
    Name      = local.name_prefix
    Component = "gateway"
  }

  lifecycle {
    precondition {
      condition     = length(local.wireguard_interfaces) == 3 && !contains(keys(local.wireguard_interfaces), "wg-cluster")
      error_message = "The effective gateway schema must contain only wg-users, wg-personal, and wg-nodes."
    }
  }
}
