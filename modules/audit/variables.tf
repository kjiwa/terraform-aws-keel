variable "name_prefix" {
  description = "Prefix for every resource name this module creates (string, lowercase letters, digits and hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 40 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "alert_email" {
  description = "Address subscribed to the audit SNS topic for CloudTrail alarms and Access Analyzer findings (string). The subscription must be confirmed by hand after the first apply."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+$", var.alert_email))
    error_message = "alert_email must be an email address."
  }
}

variable "log_source_buckets" {
  description = "Workload buckets to enable S3 server access logging on and to authorize as log senders (list of objects). Each has name, the bucket to attach logging to, and arn, used in the delivery policy's SourceArn condition."
  type = list(object({
    name = string
    arn  = string
  }))
  default  = []
  nullable = false
}

variable "log_retention_days" {
  description = "Days to retain the trail, the S3 access logs, and by default the trail's log group (number). The trail bucket is Object-Locked for this long. SOC2 commonly expects at least a year."
  type        = number
  default     = 365
  nullable    = false

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days == floor(var.log_retention_days)
    error_message = "log_retention_days must be a whole number of days, at least 1."
  }
}

variable "log_group_retention_days" {
  description = "Days to retain the CloudTrail CloudWatch log group (number), or null to follow log_retention_days. Must be a retention value CloudWatch Logs accepts."
  type        = number
  default     = null

  validation {
    condition     = var.log_group_retention_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], coalesce(var.log_group_retention_days, 0))
    error_message = "log_group_retention_days must be null or a retention period CloudWatch Logs supports, such as 90, 365, or 731."
  }
}

variable "kms_encryption_enabled" {
  description = "Encrypt the trail objects and the trail's log group with a customer-managed KMS key (bool). The key costs about 1 USD per month; false falls back to SSE-S3 on the trail bucket and no encryption key on the log group. Turning it off on a deployed stack is refused by prevent_destroy on the key."
  type        = bool
  default     = true
  nullable    = false
}

variable "metric_namespace" {
  description = "CloudWatch namespace for the CloudTrail metric-filter alarms (string), or null to derive it from name_prefix: each hyphen-separated word capitalized, then Audit."
  type        = string
  default     = null

  validation {
    condition     = var.metric_namespace == null || (can(regex("^[A-Za-z0-9._#:/-]{1,255}$", coalesce(var.metric_namespace, "-"))) && !startswith(coalesce(var.metric_namespace, ""), "AWS/"))
    error_message = "metric_namespace must be null or 1 to 255 characters of letters, digits and . _ # : / -, and must not start with AWS/."
  }
}

variable "backup_account_id" {
  description = "AWS account ID of a cross-account backup destination (string), or empty when backups stay in the account. Non-empty archives the Access Analyzer findings for that account's expected access to KMS keys and snapshots, so they do not re-fire forever."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.backup_account_id == "" || can(regex("^[0-9]{12}$", var.backup_account_id))
    error_message = "backup_account_id must be a 12-digit AWS account ID or empty."
  }
}
