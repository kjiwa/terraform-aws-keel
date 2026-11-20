mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-west-2", name = "us-west-2" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

mock_provider "archive" {}

variables {
  name_prefix         = "demo"
  asg_name            = "demo-asg"
  launch_template_ids = { arm64 = "lt-0123456789abcdef0", x86_64 = "lt-0123456789abcdef1" }
  alarm_topic_arn     = "arn:aws:sns:us-west-2:123456789012:demo"
}

run "function_is_configured_from_the_inputs" {
  command = plan

  variables {
    min_age_hours    = 6
    ami_max_age_days = 10
    dry_run          = true
    refresh_preferences = {
      min_healthy_percentage = 100
      max_healthy_percentage = 150
      instance_warmup        = 60
      alarm_names            = ["demo-site-down"]
    }
  }

  assert {
    condition     = aws_lambda_function.this.function_name == "demo-ami-updater" && aws_lambda_function.this.runtime == "python3.13"
    error_message = "The function must be <name_prefix>-ami-updater on python3.13."
  }

  assert {
    condition = (
      aws_lambda_function.this.environment[0].variables["ASG_NAME"] == "demo-asg"
      && aws_lambda_function.this.environment[0].variables["MIN_AGE_HOURS"] == "6"
      && aws_lambda_function.this.environment[0].variables["MAX_AGE_DAYS"] == "10"
      && aws_lambda_function.this.environment[0].variables["DRY_RUN"] == "true"
      && jsondecode(aws_lambda_function.this.environment[0].variables["ALARM_NAMES"]) == ["demo-site-down"]
      && jsondecode(aws_lambda_function.this.environment[0].variables["LAUNCH_TEMPLATE_IDS"]) == { arm64 = "lt-0123456789abcdef0", x86_64 = "lt-0123456789abcdef1" }
    )
    error_message = "The environment must carry every input the handler reads."
  }

  assert {
    condition     = jsondecode(aws_lambda_function.this.environment[0].variables["PREFERENCES"]) == { min_healthy_percentage = 100, max_healthy_percentage = 150, instance_warmup = 60 }
    error_message = "The refresh preferences must reach the handler without the alarm names."
  }
}

run "defaults_follow_the_amazon_linux_parameters" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_lambda_function.this.environment[0].variables["SSM_PARAMETERS"]).arm64 == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
      && jsondecode(aws_lambda_function.this.environment[0].variables["SSM_PARAMETERS"]).x86_64 == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
      && aws_lambda_function.this.environment[0].variables["MIN_AGE_HOURS"] == "24"
      && aws_lambda_function.this.environment[0].variables["MAX_AGE_DAYS"] == "14"
      && aws_lambda_function.this.environment[0].variables["DRY_RUN"] == "false"
    )
    error_message = "Defaults must be the AL2023 kernel-default parameters, 24 hours, 14 days, not a dry run."
  }
}

run "runs_daily" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_rule.this.schedule_expression == "rate(1 day)"
    error_message = "The updater must run once a day."
  }
}

run "alarm_watches_the_oldest_running_image" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.age.namespace == "AmiUpdater"
      && aws_cloudwatch_metric_alarm.age.metric_name == "AmiAgeDays"
      && aws_cloudwatch_metric_alarm.age.dimensions["AutoScalingGroupName"] == "demo-asg"
      && aws_cloudwatch_metric_alarm.age.threshold == 21
      && aws_cloudwatch_metric_alarm.age.comparison_operator == "GreaterThanThreshold"
      && aws_cloudwatch_metric_alarm.age.treat_missing_data == "notBreaching"
      && contains(aws_cloudwatch_metric_alarm.age.alarm_actions, "arn:aws:sns:us-west-2:123456789012:demo")
    )
    error_message = "The alarm must fire above 21 days on the group's AmiAgeDays and notify the topic."
  }
}

run "writes_are_scoped_to_the_group_and_templates" {
  command = plan

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.this.statement : (
        contains(s.actions, "autoscaling:StartInstanceRefresh") ? toset(s.resources) == toset(["arn:aws:autoscaling:us-west-2:123456789012:autoScalingGroup:*:autoScalingGroupName/demo-asg"]) : true
      )
    ])
    error_message = "StartInstanceRefresh must be limited to the group."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.this.statement : (
        contains(s.actions, "ec2:CreateLaunchTemplateVersion") ? toset(s.resources) == toset(["arn:aws:ec2:us-west-2:123456789012:launch-template/lt-0123456789abcdef0", "arn:aws:ec2:us-west-2:123456789012:launch-template/lt-0123456789abcdef1"]) : true
      )
    ])
    error_message = "CreateLaunchTemplateVersion must be limited to the named templates."
  }
}

run "templates_need_a_parameter_each" {
  command = plan
  variables {
    launch_template_ids = { riscv = "lt-0123456789abcdef0" }
  }

  expect_failures = [var.launch_template_ids]
}

run "min_age_cannot_be_negative" {
  command = plan
  variables {
    min_age_hours = -1
  }

  expect_failures = [var.min_age_hours]
}

run "pass_role_is_limited_to_the_instance_roles" {
  command = plan
  variables {
    instance_role_arns = ["arn:aws:iam::123456789012:role/demo"]
  }

  assert {
    condition = length([
      for s in data.aws_iam_policy_document.this.statement : s if contains(s.actions, "iam:PassRole") && toset(s.resources) == toset(["arn:aws:iam::123456789012:role/demo"])
    ]) == 1
    error_message = "UpdateAutoScalingGroup passes the template's instance role, so PassRole must be granted for exactly those roles."
  }
}

run "no_pass_role_without_instance_roles" {
  command = plan

  assert {
    condition     = length([for s in data.aws_iam_policy_document.this.statement : s if contains(s.actions, "iam:PassRole")]) == 0
    error_message = "Templates without an instance profile need no PassRole."
  }
}

run "tags_are_created_only_by_launches" {
  command = plan

  assert {
    condition     = length([for s in data.aws_iam_policy_document.this.statement : s if contains(s.actions, "ec2:CreateTags")]) == 1
    error_message = "UpdateAutoScalingGroup needs CreateTags for templates that tag instances at launch."
  }
}
