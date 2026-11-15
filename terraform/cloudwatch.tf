# ---------------- CloudWatch: logs, metric filter, alarms, dashboard ----------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/medicart/app"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/medicart/nginx"
  retention_in_days = 7
}

# Count every "ERROR" line written by the app -> custom metric
resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "medicart-app-errors"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "ERROR"
  metric_transformation {
    name      = "AppErrors"
    namespace = "MediCart"
    value     = "1"
  }
}

resource "aws_sns_topic" "alerts" {
  name = "medicart-alerts-${random_id.suffix.hex}"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "medicart-high-cpu"
  alarm_description   = "EC2 CPU above 70% for 10 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.web.id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "medicart-status-check-failed"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.web.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "app_errors" {
  alarm_name          = "medicart-app-errors"
  alarm_description   = "5 or more application errors in 5 minutes"
  namespace           = "MediCart"
  metric_name         = "AppErrors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "MediCart-Dashboard"
  dashboard_body = jsonencode({
    widgets = [
      { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = {
          title = "EC2 CPU Utilization", region = var.region, stat = "Average", period = 300,
          metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.web.id]] } },
      { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = {
          title = "Network In/Out", region = var.region, stat = "Sum", period = 300,
          metrics = [["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.web.id],
                     ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.web.id]] } },
      { type = "metric", x = 0, y = 6, width = 12, height = 6, properties = {
          title = "Application Errors", region = var.region, stat = "Sum", period = 300,
          metrics = [["MediCart", "AppErrors"]] } },
      { type = "log", x = 12, y = 6, width = 12, height = 6, properties = {
          title = "Recent app logs", region = var.region,
          query = "SOURCE '/medicart/app' | fields @timestamp, @message | sort @timestamp desc | limit 20" } }
    ]
  })
}
