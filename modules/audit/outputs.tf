output "log_bucket_name" {
  description = "Name of the isolated S3 server-access-log bucket (CloudTrail writes to the Object-Locked trail bucket)."
  value       = aws_s3_bucket.logs.id
}

output "cloudtrail_arn" {
  description = "ARN of the management-event CloudTrail."
  value       = aws_cloudtrail.main.arn
}

output "access_analyzer_arn" {
  description = "ARN of the account IAM Access Analyzer."
  value       = aws_accessanalyzer_analyzer.account.arn
}

output "audit_topic_arn" {
  description = "SNS topic for audit alerts (CloudTrail alarms, Access Analyzer findings). Confirm the email subscription after apply."
  value       = aws_sns_topic.audit.arn
}

output "trail_bucket_name" {
  description = "Name of the Object-Locked S3 bucket holding the CloudTrail management-event trail."
  value       = aws_s3_bucket.trail.id
}
