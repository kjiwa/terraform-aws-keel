# The detection half of the audit module. CloudTrail (trail_bucket.tf) and
# Access Analyzer (access_analyzer.tf) both record; nothing here creates records,
# it only routes them somewhere a human is notified. Without this, the trail is a
# write-only archive and Access Analyzer findings sit in a console nobody opens.

# One topic for every audit-plane alert. Separate from a workload's operational
# topic on purpose: that one is about whether the app is up, this one is security
# (did someone change the account).
#
# Deliberately NOT KMS-encrypted, matching the operational topic: a CMK on the
# topic forces every publisher principal (here cloudwatch.amazonaws.com and
# events.amazonaws.com) into the key policy with Decrypt + GenerateDataKey, and
# getting it wrong makes SNS silently drop the message rather than error. The
# payloads are alarm names and one-line finding summaries -- the sensitive
# material (the audit records themselves) lives in the Object-Locked bucket, not
# in these notifications.
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

  # Flatten the finding into a one-line human summary instead of mailing raw
  # EventBridge JSON.
  input_transformer {
    input_paths = {
      resource = "$.detail.resource"
      type     = "$.detail.resourceType"
      action   = "$.detail.action"
    }
    input_template = "\"Access Analyzer: <resource> (<type>) is externally accessible. Actions: <action>.\""
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

# A metric filter + alarm per event class we want paged on. Kept to the handful
# that actually signal account tampering rather than every management event: the
# root account being used, IAM/policy changes, and CloudTrail itself being
# stopped or reconfigured (the classic "disable logging before doing damage"
# move). Each alarm publishes to the audit topic.
locals {
  # name -> CloudWatch Logs metric-filter pattern.
  audit_filters = {
    root-account-used = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
    iam-policy-change = "{ ($.eventName = Put*Policy) || ($.eventName = Delete*Policy) || ($.eventName = Attach*Policy) || ($.eventName = Detach*Policy) || ($.eventName = Create*Policy*) }"
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
