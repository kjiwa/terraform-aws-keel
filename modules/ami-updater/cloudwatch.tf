# The updater publishes once a day, so one daily period holds one datapoint;
# a group with no instances publishes nothing, which is not a breach.
resource "aws_cloudwatch_metric_alarm" "age" {
  alarm_name          = "${local.function_name}-age"
  alarm_description   = "A running instance of ${var.asg_name} has an AMI over 21 days old: the updater is failing, held back, or the newest AMI is itself old."
  namespace           = local.metric_namespace
  metric_name         = "AmiAgeDays"
  dimensions          = { AutoScalingGroupName = var.asg_name }
  statistic           = "Maximum"
  period              = 86400
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 21
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
}
