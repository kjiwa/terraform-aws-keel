mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix = "demo-app"
  alert_email = "alerts@example.com"
}

run "names_carry_prefix" {
  command = plan

  assert {
    condition     = aws_cloudtrail.main.name == "demo-app" && aws_accessanalyzer_analyzer.account.analyzer_name == "demo-app-account"
    error_message = "The trail must be named <name_prefix> and the analyzer <name_prefix>-account."
  }

  assert {
    condition     = aws_s3_bucket.logs.bucket == "demo-app-logs-123456789012" && aws_s3_bucket.trail.bucket == "demo-app-trail-123456789012"
    error_message = "Buckets must be <name_prefix>-logs-<account> and <name_prefix>-trail-<account>."
  }

  assert {
    condition     = aws_sns_topic.audit.name == "demo-app-audit" && aws_iam_role.trail_to_logs.name == "demo-app-cloudtrail-logs"
    error_message = "The topic must be <name_prefix>-audit and the role <name_prefix>-cloudtrail-logs."
  }

  assert {
    condition     = aws_cloudwatch_log_group.trail.name == "/aws/cloudtrail/demo-app" && aws_cloudwatch_event_rule.access_analyzer.name == "demo-app-access-analyzer-findings"
    error_message = "The log group and event rule names must carry name_prefix."
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.audit : a.alarm_name == "demo-app-audit-${k}"])
    error_message = "Every alarm must be named <name_prefix>-audit-<filter>."
  }

  assert {
    condition     = aws_kms_alias.audit[0].name == "alias/demo-app-audit" && aws_kms_key.audit[0].tags["Name"] == "demo-app-audit"
    error_message = "The KMS alias and key tag must carry name_prefix."
  }
}

run "default_resource_shape" {
  command = plan

  assert {
    condition     = toset(keys(aws_cloudwatch_metric_alarm.audit)) == toset(["root-account-used", "iam-policy-change", "cloudtrail-change"]) && toset(keys(aws_cloudwatch_log_metric_filter.audit)) == toset(["root-account-used", "iam-policy-change", "cloudtrail-change"])
    error_message = "The metric filters and alarms must be keyed by the three tamper-detection classes."
  }

  assert {
    condition     = aws_s3_bucket.trail.object_lock_enabled && one(one(aws_s3_bucket_object_lock_configuration.trail.rule).default_retention).mode == "GOVERNANCE" && one(one(aws_s3_bucket_object_lock_configuration.trail.rule).default_retention).days == 365
    error_message = "The trail bucket must be Object-Locked in GOVERNANCE mode for log_retention_days (default 365)."
  }

  assert {
    condition     = aws_cloudwatch_log_group.trail.retention_in_days == 365
    error_message = "The log group retention must follow log_retention_days (default 365)."
  }

  assert {
    condition     = length(aws_accessanalyzer_archive_rule.backup_account_cmk) == 0 && length(aws_s3_bucket_logging.source) == 0
    error_message = "With defaults there is no archive rule and no access logging."
  }

  assert {
    condition     = aws_iam_account_password_policy.strict.minimum_password_length == 14
    error_message = "The password policy must be created with its 14-character minimum."
  }
}

run "kms_on_by_default" {
  command = apply

  assert {
    condition     = length(aws_kms_key.audit) == 1 && length(aws_kms_alias.audit) == 1
    error_message = "The audit CMK and alias must exist by default."
  }

  assert {
    condition     = aws_kms_key.audit[0].enable_key_rotation && aws_kms_key.audit[0].deletion_window_in_days == 30
    error_message = "The CMK must rotate and use a 30-day deletion window."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.trail.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms" && one(aws_s3_bucket_server_side_encryption_configuration.trail.rule).bucket_key_enabled
    error_message = "The trail bucket must use the CMK with bucket keys."
  }

  assert {
    condition     = aws_cloudtrail.main.kms_key_id == aws_kms_key.audit[0].arn && aws_cloudwatch_log_group.trail.kms_key_id == aws_kms_key.audit[0].arn
    error_message = "The trail and its log group must be encrypted with the CMK."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.logs.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "The access-log bucket must stay SSE-S3 so S3 logging can deliver."
  }
}

run "kms_off_uses_sse_s3" {
  command = apply

  variables {
    kms_encryption_enabled = false
  }

  assert {
    condition     = length(aws_kms_key.audit) == 0 && length(aws_kms_alias.audit) == 0
    error_message = "Disabling KMS must create no key or alias."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.trail.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Without KMS the trail bucket must use AES256."
  }

  assert {
    condition     = aws_cloudtrail.main.kms_key_id == "" && aws_cloudwatch_log_group.trail.kms_key_id == ""
    error_message = "Without KMS neither the trail nor its log group may reference a key."
  }
}

run "metric_namespace_derived_from_prefix" {
  command = plan

  assert {
    condition     = alltrue([for f in aws_cloudwatch_log_metric_filter.audit : one(f.metric_transformation).namespace == "DemoAppAudit"])
    error_message = "The default namespace must be the PascalCase name_prefix plus Audit."
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.audit : a.namespace == "DemoAppAudit"])
    error_message = "Alarms must read the same namespace the filters write."
  }
}

run "metric_namespace_override" {
  command = plan

  variables {
    metric_namespace = "Custom/Audit"
  }

  assert {
    condition     = alltrue([for f in aws_cloudwatch_log_metric_filter.audit : one(f.metric_transformation).namespace == "Custom/Audit"]) && alltrue([for a in aws_cloudwatch_metric_alarm.audit : a.namespace == "Custom/Audit"])
    error_message = "metric_namespace must override the derived namespace on filters and alarms."
  }
}

run "log_group_retention_override" {
  command = plan

  variables {
    log_retention_days       = 90
    log_group_retention_days = 365
  }

  assert {
    condition     = aws_cloudwatch_log_group.trail.retention_in_days == 365 && aws_cloudwatch_log_group.trail.retention_in_days != aws_s3_bucket_lifecycle_configuration.logs.rule[0].expiration[0].days
    error_message = "log_group_retention_days must decouple the log group from log_retention_days."
  }

  assert {
    condition     = one(one(aws_s3_bucket_object_lock_configuration.trail.rule).default_retention).days == 90
    error_message = "log_retention_days must still drive the bucket retention."
  }
}

run "access_logging_per_source_bucket" {
  command = plan

  variables {
    log_source_buckets = [
      { name = "media", arn = "arn:aws:s3:::media" },
      { name = "uploads", arn = "arn:aws:s3:::uploads" },
    ]
  }

  assert {
    condition     = toset(keys(aws_s3_bucket_logging.source)) == toset(["media", "uploads"])
    error_message = "Access logging must be keyed by source bucket name."
  }

  assert {
    condition     = aws_s3_bucket_logging.source["media"].target_prefix == "s3-access/media/"
    error_message = "Each source bucket must log under s3-access/<name>/."
  }
}

run "backup_account_archives_expected_access" {
  command = plan

  variables {
    backup_account_id = "210987654321"
  }

  assert {
    condition     = length(aws_accessanalyzer_archive_rule.backup_account_cmk) == 1
    error_message = "A backup account must create the archive rule."
  }
}

run "rejects_bad_prefix" {
  command = plan

  variables {
    name_prefix = "Not Valid"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_bad_email" {
  command = plan

  variables {
    alert_email = "not-an-address"
  }

  expect_failures = [var.alert_email]
}

run "rejects_bad_backup_account" {
  command = plan

  variables {
    backup_account_id = "1234"
  }

  expect_failures = [var.backup_account_id]
}

run "rejects_nonpositive_retention" {
  command = plan

  variables {
    log_retention_days = 0
  }

  expect_failures = [var.log_retention_days]
}

run "rejects_invalid_log_group_retention" {
  command = plan

  variables {
    log_group_retention_days = 100
  }

  expect_failures = [var.log_group_retention_days]
}

run "rejects_reserved_namespace" {
  command = plan

  variables {
    metric_namespace = "AWS/Audit"
  }

  expect_failures = [var.metric_namespace]
}
