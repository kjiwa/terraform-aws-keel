data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  # CloudTrail validates bucket write access at create time, so the trail bucket
  # policy needs the trail ARN before the trail exists; referencing the resource
  # would be a dependency cycle.
  trail_arn = "arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/${var.name_prefix}"

  metric_namespace = coalesce(
    var.metric_namespace,
    "${join("", [for word in split("-", var.name_prefix) : "${upper(substr(word, 0, 1))}${substr(word, 1, -1)}"])}Audit",
  )

  log_group_retention_days = coalesce(var.log_group_retention_days, var.log_retention_days)

  # Null when KMS is off, which leaves the trail and log group unencrypted by a CMK.
  kms_key_arn = one(aws_kms_key.audit[*].arn)
}
