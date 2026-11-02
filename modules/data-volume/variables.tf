variable "name_prefix" {
  description = "Prefix for the names of the vault, plan, selection, role and keys this module creates (string, lowercase letters, digits and hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 40 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "az" {
  description = "Availability zone for the EBS volume (string). Must match the instance AZ."
  type        = string
}

variable "size_gib" {
  description = "Size of the EBS data volume in GiB (number, gp3). Raising it is an in-place ModifyVolume; lowering it is not supported by EBS."
  type        = number
  default     = 8

  validation {
    condition     = var.size_gib >= 1
    error_message = "size_gib must be at least 1."
  }
}

variable "snapshot_id" {
  description = "EC2 snapshot ID to create the volume from (string), or null. First apply only: snapshot_id is ForceNew and the volume carries prevent_destroy, so setting it on a live volume plans a replace that errors instead of adopting the volume. For rebuilding an environment from a disaster-recovery snapshot."
  type        = string
  default     = null
}

variable "volume_name" {
  description = "Name tag of the volume and basis of its data key alias (string). Null uses <name_prefix>-data."
  type        = string
  default     = null
}

variable "volume_tags" {
  description = "Extra tags for the volume (map of string), merged under Name and Persistent."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "backup" {
  description = <<-EOT
    Backup of the volume and any extra resources through one AWS Backup plan
    (object).

      mode                  local (daily recovery points in this account and
                            region), cross_region (also copy each to a vault
                            this module creates in backup_region),
                            cross_account (also copy each to a vault another
                            account owns, named by account_id and
                            dest_vault_name), or disabled.
      schedule              Cron or rate expression for the plan.
      retention_days        Days the local vault keeps a recovery point.
      remote_retention_days Days the off-site copy is kept; 0 means the same
                            as retention_days.
      account_id            12-digit destination account, required for
                            cross_account.
      dest_vault_name       Destination vault name for cross_account; null
                            uses <name_prefix>-backup. The destination ARN is
                            constructed from it, so the name must match the
                            backup account's vault.

    Only cross_account yields a copy this account cannot delete. It also
    needs a customer-managed key on the volume, because aws/ebs cannot be
    shared with another account.
  EOT
  type = object({
    mode                  = optional(string, "local")
    schedule              = optional(string, "cron(0 3 * * ? *)")
    retention_days        = optional(number, 7)
    remote_retention_days = optional(number, 0)
    account_id            = optional(string, "")
    dest_vault_name       = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["local", "cross_region", "cross_account", "disabled"], var.backup.mode)
    error_message = "backup.mode must be one of: local, cross_region, cross_account, disabled."
  }

  validation {
    condition     = var.backup.mode != "cross_account" || can(regex("^[0-9]{12}$", var.backup.account_id))
    error_message = "backup.mode = cross_account requires backup.account_id, a 12-digit AWS account ID."
  }

  validation {
    condition     = var.backup.retention_days >= 1 && var.backup.remote_retention_days >= 0
    error_message = "backup.retention_days must be at least 1 and backup.remote_retention_days must not be negative."
  }
}

variable "backup_region" {
  description = "Region of the off-site copy (string). The replica vault is created there under cross_region, and the destination vault ARN is built from it under cross_account, so it must match the backup account's region. Unused for local and disabled."
  type        = string
}

variable "vault_kms" {
  description = "Encryption of the local and replica vaults (string): aws_managed uses the AWS-managed aws/backup key at no cost; cmk creates a customer-managed key per vault at about $1 per month each. EBS recovery points are encrypted by the volume's key either way, so aws_managed suffices for an EBS-only plan; S3 resources in extra_backup_resource_arns need cmk to be copied cross-account. A vault's key cannot change after creation, so match the existing vault."
  type        = string
  default     = "aws_managed"
  nullable    = false

  validation {
    condition     = contains(["aws_managed", "cmk"], var.vault_kms)
    error_message = "vault_kms must be one of: aws_managed, cmk."
  }
}

variable "extra_backup_resource_arns" {
  description = "ARNs of further resources for the backup selection (list of string), such as an S3 media bucket. The volume is always selected."
  type        = list(string)
  default     = []
  nullable    = false
}
