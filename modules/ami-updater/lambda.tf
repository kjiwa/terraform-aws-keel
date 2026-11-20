data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/lambda/ami_updater.py"
  output_path = "${path.module}/lambda/ami_updater.zip"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30
}

resource "aws_lambda_function" "this" {
  function_name    = local.function_name
  role             = aws_iam_role.this.arn
  runtime          = "python3.13"
  handler          = "ami_updater.handler"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  architectures    = ["arm64"]
  memory_size      = 128
  timeout          = 120

  # The schedule can invoke within seconds of creation; without this the
  # runtime auto-creates the log group first and Terraform's create conflicts.
  depends_on = [aws_cloudwatch_log_group.this]

  environment {
    variables = {
      ASG_NAME            = var.asg_name
      LAUNCH_TEMPLATE_IDS = jsonencode(var.launch_template_ids)
      SSM_PARAMETERS      = jsonencode(var.ssm_parameters)
      MIN_AGE_HOURS       = tostring(var.min_age_hours)
      MAX_AGE_DAYS        = tostring(var.ami_max_age_days)
      PREFERENCES         = jsonencode({ for key, value in var.refresh_preferences : key => value if key != "alarm_names" })
      ALARM_NAMES         = jsonencode(var.refresh_preferences.alarm_names)
      DRY_RUN             = tostring(var.dry_run)
    }
  }

  tags = {
    Name = local.function_name
  }
}
