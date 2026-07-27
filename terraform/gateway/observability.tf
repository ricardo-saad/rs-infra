resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/rs-platform/gateway"
  retention_in_days = var.log_retention_days

  tags = {
    Name = local.name_prefix
  }
}

resource "aws_cloudwatch_metric_alarm" "instance_status" {
  alarm_name          = "${local.name_prefix}-instance-status"
  alarm_description   = "Gateway EC2 instance or system status is unhealthy."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    InstanceId = aws_instance.gateway.id
  }
}

resource "aws_cloudwatch_metric_alarm" "heartbeat" {
  alarm_name          = "${local.name_prefix}-heartbeat"
  alarm_description   = "Gateway service heartbeat is absent."
  namespace           = var.metrics_namespace
  metric_name         = "GatewayHeartbeat"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_actions

}

resource "aws_cloudwatch_metric_alarm" "secret_load_failure" {
  alarm_name          = "${local.name_prefix}-secret-load-failure"
  alarm_description   = "Gateway reported a missing or invalid current recovery secret."
  namespace           = var.metrics_namespace
  metric_name         = "SecretLoadFailure"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

}

resource "aws_cloudwatch_metric_alarm" "public_key_publication_failure" {
  alarm_name          = "${local.name_prefix}-public-key-publication-failure"
  alarm_description   = "Gateway failed to publish one or more WireGuard public keys."
  namespace           = var.metrics_namespace
  metric_name         = "PublicKeyPublicationFailure"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
}
