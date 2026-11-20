# The updater publishes once a day, so one daily period holds one datapoint;
# a group with no instances publishes nothing, which is not a breach. The
# threshold sits a week past the refresh limit: a refresh that should have
# run by then did not.
resource "aws_cloudwatch_metric_alarm" "age" {
  alarm_name          = "${local.function_name}-age"
  alarm_description   = "A running instance of ${var.asg_name} has an AMI over ${local.age_alarm_days} days old: the updater is held back, or the newest AMI is itself old. A failing updater is the errors alarm."
  namespace           = local.metric_namespace
  metric_name         = "AmiAgeDays"
  dimensions          = { AutoScalingGroupName = var.asg_name }
  statistic           = "Maximum"
  period              = 86400
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.age_alarm_days
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
}

# The age alarm cannot see a run that fails before it publishes.
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "The ${local.function_name} function failed: launch templates are not being advanced."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.this.function_name }
  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
}
