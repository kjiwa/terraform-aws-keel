data "aws_caller_identity" "default" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  function_name = "${var.name_prefix}-ami-updater"

  # Must match NAMESPACE in lambda/ami_updater.py.
  metric_namespace = "AmiUpdater"

  arn_prefix = "arn:${data.aws_partition.current.partition}"
}
