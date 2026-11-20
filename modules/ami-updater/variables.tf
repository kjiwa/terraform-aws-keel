variable "name_prefix" {
  description = "Prefix for every resource name this module creates (string, lowercase letters, digits and hyphens)."
  type        = string
}

variable "asg_name" {
  description = "Name of the Auto Scaling group whose launch templates the updater advances (string)."
  type        = string
}

variable "launch_template_ids" {
  description = "Launch template ID per architecture the group uses (map of string); the key selects the entry of ssm_parameters. The group must pin each template by version number, not $Latest, so that a Terraform-triggered refresh still follows template changes."
  type        = map(string)

  validation {
    condition     = length(var.launch_template_ids) > 0 && alltrue([for architecture in keys(var.launch_template_ids) : contains(keys(var.ssm_parameters), architecture)])
    error_message = "launch_template_ids must name at least one template, and every key must also be a key of ssm_parameters."
  }
}

variable "instance_role_arns" {
  description = "ARNs of the IAM roles behind the launch templates' instance profiles (list of string). UpdateAutoScalingGroup needs the caller to be able to pass them; leave empty for templates without an instance profile."
  type        = list(string)
  default     = []
}

variable "ssm_parameters" {
  description = "SSM public parameter holding the newest AMI, per architecture (map of string). Defaults to the Amazon Linux 2023 kernel-default parameters."
  type        = map(string)
  default = {
    arm64  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    x86_64 = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  }
}

variable "min_age_hours" {
  description = "Hours an AMI must have been published before the updater writes it into a launch template (number)."
  type        = number
  default     = 24

  validation {
    condition     = var.min_age_hours >= 0
    error_message = "min_age_hours must not be negative."
  }
}

variable "ami_max_age_days" {
  description = "Age in days past which a running instance's AMI triggers an instance refresh, when a newer AMI is targeted (number). The refresh replaces every instance, with the blip that costs."
  type        = number
  default     = 14

  validation {
    condition     = var.ami_max_age_days >= 0
    error_message = "ami_max_age_days must not be negative."
  }
}

variable "refresh_preferences" {
  description = "Preferences of the refresh the updater starts (object): healthy percentages, instance warmup in seconds (null uses the group's default), and alarms that hold the updater back while any is in ALARM. Match the group's own instance_refresh so a forced refresh behaves like a Terraform-triggered one; the lifecycle hook is the group's and applies either way."
  type = object({
    min_healthy_percentage = optional(number, 100)
    max_healthy_percentage = optional(number, 200)
    instance_warmup        = optional(number)
    alarm_names            = optional(list(string), [])
  })
  default = {}
}

variable "alarm_topic_arn" {
  description = "Existing SNS topic ARN notified when the updater fails or a running AMI is more than 7 days past ami_max_age_days old (string)."
  type        = string
}

variable "dry_run" {
  description = "Log what the updater would do without writing a launch template version, updating the group or starting a refresh (bool). The AmiAgeDays metric is still published."
  type        = bool
  default     = false
}
