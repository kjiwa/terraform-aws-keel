resource "aws_cloudwatch_event_rule" "this" {
  name                = local.function_name
  description         = "Advance the launch templates of ${var.asg_name} to the newest AMI."
  schedule_expression = "rate(1 day)"

  tags = {
    Name = local.function_name
  }
}

resource "aws_cloudwatch_event_target" "this" {
  rule      = aws_cloudwatch_event_rule.this.name
  target_id = "ami-updater"
  arn       = aws_lambda_function.this.arn
}

resource "aws_lambda_permission" "this" {
  statement_id  = "AllowSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this.arn
}
