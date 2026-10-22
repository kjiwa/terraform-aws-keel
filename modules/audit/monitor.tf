# Routes CloudTrail and Access Analyzer records to a human via SNS.

# One topic for every audit-plane alert, separate from an application's
# operational topic: this one is about account changes, not uptime.
#
# Deliberately NOT KMS-encrypted: a CMK on the topic needs every publisher
# principal in the key policy, and a mistake makes SNS drop messages silently.
# The payloads are alarm names and one-line summaries; the audit records live in
# the Object-Locked bucket.
resource "aws_sns_topic" "audit" {
  name = "${var.name_prefix}-audit"

  tags = {
    Name = "${var.name_prefix}-audit"
  }
}

resource "aws_sns_topic_subscription" "audit_email" {
  topic_arn = aws_sns_topic.audit.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# EventBridge (and CloudWatch alarms) publish to SNS as a service principal, so
# the topic policy has to allow it. Scoped to this account's resources.
data "aws_iam_policy_document" "audit_topic" {
  statement {
    sid     = "AllowServicePublish"
    effect  = "Allow"
    actions = ["sns:Publish"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
    resources = [aws_sns_topic.audit.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "audit" {
  arn    = aws_sns_topic.audit.arn
  policy = data.aws_iam_policy_document.audit_topic.json
}

# --- Access Analyzer findings -> EventBridge -> SNS ------------------------

# Fires on any new or updated ACTIVE external-access finding. Archived/resolved
# findings are filtered out so the mail means "something is exposed right now".
resource "aws_cloudwatch_event_rule" "access_analyzer" {
  name        = "${var.name_prefix}-access-analyzer-findings"
  description = "Route active IAM Access Analyzer external-access findings to SNS."

  event_pattern = jsonencode({
    source      = ["aws.access-analyzer"]
    detail-type = ["Access Analyzer Finding"]
    detail = {
      status = ["ACTIVE"]
    }
  })
}

resource "aws_cloudwatch_event_target" "access_analyzer_sns" {
  rule      = aws_cloudwatch_event_rule.access_analyzer.name
  target_id = "audit-sns"
  arn       = aws_sns_topic.audit.arn

  # Scalar paths only: an array-valued path does not render into the template.
  input_transformer {
    input_paths = {
      resource = "$.detail.resource"
      type     = "$.detail.resourceType"
    }
    input_template = "\"Access Analyzer: <resource> (<type>) is externally accessible.\""
  }
}

# --- CloudTrail management events -> CloudWatch Logs -> metric alarms -------

resource "aws_cloudwatch_log_group" "trail" {
  name              = "/aws/cloudtrail/${var.name_prefix}"
  retention_in_days = local.log_group_retention_days
  kms_key_id        = local.kms_key_arn

  tags = {
    Name = "${var.name_prefix}-cloudtrail"
  }
}

data "aws_iam_policy_document" "trail_to_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

data "aws_iam_policy_document" "trail_to_logs" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.trail.arn}:*"]
  }
}

resource "aws_iam_role" "trail_to_logs" {
  name               = "${var.name_prefix}-cloudtrail-logs"
  assume_role_policy = data.aws_iam_policy_document.trail_to_logs_assume.json

  tags = {
    Name = "${var.name_prefix}-cloudtrail-logs"
  }
}

resource "aws_iam_role_policy" "trail_to_logs" {
  name   = "put-logs"
  role   = aws_iam_role.trail_to_logs.id
  policy = data.aws_iam_policy_document.trail_to_logs.json
}

# A metric filter + alarm per tamper-signalling event class, each publishing to
# the audit topic.
locals {
  # Explicit names, not wildcards: Put*Policy and friends also match unrelated
  # events in other services.
  iam_policy_change_events = [
    "PutUserPolicy", "PutGroupPolicy", "PutRolePolicy", "CreatePolicy", "DeletePolicy",
    "CreatePolicyVersion", "DeletePolicyVersion", "SetDefaultPolicyVersion",
    "AttachRolePolicy", "DetachRolePolicy", "AttachUserPolicy", "DetachUserPolicy",
    "AttachGroupPolicy", "DetachGroupPolicy", "DeleteRolePolicy", "DeleteUserPolicy",
    "DeleteGroupPolicy", "UpdateAssumeRolePolicy", "PutRolePermissionsBoundary",
    "DeleteRolePermissionsBoundary", "PutUserPermissionsBoundary", "DeleteUserPermissionsBoundary",
  ]

  # name -> CloudWatch Logs metric-filter pattern.
  audit_filters = {
    root-account-used = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
    iam-policy-change = "{ ($.eventSource = iam.amazonaws.com) && (${join(" || ", [for e in local.iam_policy_change_events : "($.eventName = ${e})"])}) }"
    cloudtrail-change = "{ ($.eventSource = cloudtrail.amazonaws.com) && (($.eventName = StopLogging) || ($.eventName = DeleteTrail) || ($.eventName = UpdateTrail) || ($.eventName = PutEventSelectors)) }"
  }
}

resource "aws_cloudwatch_log_metric_filter" "audit" {
  for_each = local.audit_filters

  name           = each.key
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = each.value

  metric_transformation {
    name          = each.key
    namespace     = local.metric_namespace
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "audit" {
  for_each = local.audit_filters

  alarm_name          = "${var.name_prefix}-audit-${each.key}"
  alarm_description   = "CloudTrail: ${each.key} detected in the last 5 minutes."
  namespace           = local.metric_namespace
  metric_name         = each.key
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.audit.arn]
}
