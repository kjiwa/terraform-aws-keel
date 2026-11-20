data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = local.function_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name = local.function_name
  }
}

data "aws_iam_policy_document" "this" {
  # The EC2 and Auto Scaling describe calls take no resource.
  statement {
    sid    = "Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeLaunchTemplateVersions",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeInstanceRefreshes",
      "cloudwatch:DescribeAlarms",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadAmiParameters"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [for name in values(var.ssm_parameters) : "${local.arn_prefix}:ssm:${data.aws_region.current.region}::parameter${name}"]
  }

  statement {
    sid       = "WriteTemplateVersions"
    effect    = "Allow"
    actions   = ["ec2:CreateLaunchTemplateVersion"]
    resources = [for id in values(var.launch_template_ids) : "${local.arn_prefix}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.default.account_id}:launch-template/${id}"]
  }

  statement {
    sid       = "ManageGroup"
    effect    = "Allow"
    actions   = ["autoscaling:StartInstanceRefresh", "autoscaling:UpdateAutoScalingGroup"]
    resources = ["${local.arn_prefix}:autoscaling:${data.aws_region.current.region}:${data.aws_caller_identity.default.account_id}:autoScalingGroup:*:autoScalingGroupName/${var.asg_name}"]
  }

  # UpdateAutoScalingGroup checks the caller may launch from the template.
  statement {
    sid       = "LaunchFromTemplates"
    effect    = "Allow"
    actions   = ["ec2:RunInstances"]
    resources = ["*"]

    condition {
      test     = "ArnEquals"
      variable = "ec2:LaunchTemplate"
      values   = [for id in values(var.launch_template_ids) : "${local.arn_prefix}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.default.account_id}:launch-template/${id}"]
    }
  }

  statement {
    sid       = "PublishAge"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [local.metric_namespace]
    }
  }

  statement {
    sid       = "WriteLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = local.function_name
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}
