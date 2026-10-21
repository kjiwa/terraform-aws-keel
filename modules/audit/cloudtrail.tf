# Multi-region management-event trail. The durable copy lands in the
# Object-Locked bucket (trail_bucket.tf); a parallel copy goes to CloudWatch
# Logs, where the metric filters in monitor.tf turn it into alarms. Data events
# are omitted because they bill per event.
resource "aws_cloudtrail" "main" {
  name           = var.name_prefix
  s3_bucket_name = aws_s3_bucket.trail.id
  s3_key_prefix  = "cloudtrail"

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = local.kms_key_arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail_to_logs.arn

  # CloudTrail validates write access to both at create time.
  depends_on = [aws_s3_bucket_policy.trail, aws_iam_role_policy.trail_to_logs]
}
