# ami-updater

Keeps an Auto Scaling group's launch templates on the newest Amazon Linux AMI without replacing instances the moment AWS publishes one.

A daily Lambda reads the SSM public parameter of each architecture. When that AMI has been published for `min_age_hours` and differs from the launch template's latest version, it writes a new version that copies the latest and changes the image, then points the group at it. Running instances keep their AMI until they are replaced for another reason. It starts an instance refresh only when a running instance's AMI is older than `ami_max_age_days` and a newer AMI is targeted. The refresh uses `refresh_preferences` and the group's own lifecycle hooks. A run does nothing while a refresh is in progress or a named alarm is in ALARM.

The consumer's launch template ignores changes to `image_id`, so Terraform seeds the first image and never reverts the updater. The group pins launch template versions by number (`latest_version`), not `$Latest`: `$Latest` would stop a Terraform-triggered refresh when a template changes, and AWS does not allow SSM-parameter AMIs with attribute-based instance selection or skip-matching. `DesiredConfiguration` and skip-matching are not used.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.15 |
| archive | ~> 2.4 |
| aws | >= 6.45 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_event_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.age](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_function.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [archive_file.this](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| alarm\_topic\_arn | Existing SNS topic ARN notified when a running AMI is over 21 days old (string). | `string` | n/a | yes |
| asg\_name | Name of the Auto Scaling group whose launch templates the updater advances (string). | `string` | n/a | yes |
| launch\_template\_ids | Launch template ID per architecture the group uses (map of string); the key selects the entry of ssm\_parameters. The group must pin each template by version number, not $Latest, so that a Terraform-triggered refresh still follows template changes. | `map(string)` | n/a | yes |
| name\_prefix | Prefix for every resource name this module creates (string, lowercase letters, digits and hyphens). | `string` | n/a | yes |
| ami\_max\_age\_days | Age in days past which a running instance's AMI triggers an instance refresh, when a newer AMI is targeted (number). The refresh replaces every instance, with the blip that costs. | `number` | `14` | no |
| dry\_run | Log what the updater would do without writing a launch template version, updating the group or starting a refresh (bool). The AmiAgeDays metric is still published. | `bool` | `false` | no |
| min\_age\_hours | Hours an AMI must have been published before the updater writes it into a launch template (number). | `number` | `24` | no |
| refresh\_preferences | Preferences of the refresh the updater starts (object): healthy percentages, instance warmup in seconds (null uses the group's default), and alarms that hold the updater back while any is in ALARM. Match the group's own instance\_refresh so a forced refresh behaves like a Terraform-triggered one; the lifecycle hook is the group's and applies either way. | ```object({ min_healthy_percentage = optional(number, 100) max_healthy_percentage = optional(number, 200) instance_warmup = optional(number) alarm_names = optional(list(string), []) })``` | `{}` | no |
| ssm\_parameters | SSM public parameter holding the newest AMI, per architecture (map of string). Defaults to the Amazon Linux 2023 kernel-default parameters. | `map(string)` | ```{ "arm64": "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64", "x86_64": "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" }``` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| age\_alarm\_name | Alarm that fires when a running instance's AMI is over 21 days old. |
| function\_name | Updater Lambda function name; invoke it to run the updater outside its schedule. |
<!-- END_TF_DOCS -->
