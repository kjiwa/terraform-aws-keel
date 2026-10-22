variable "name_prefix" {
  description = "Prefix for the IAM role names this module creates (string, lowercase letters, digits and hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 40 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "vault_name" {
  description = "Backup vault name (string). The workload account builds this vault's ARN from the backup account ID, region and this name, so the two sides must state the same name; a mismatch fails at copy-job runtime, not at plan time."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{2,50}$", var.vault_name))
    error_message = "vault_name must be 2 to 50 characters of letters, digits, dots, underscores and hyphens."
  }
}

variable "source_account_id" {
  description = "AWS account ID of the workload account whose backups are copied here (string). It is granted backup:CopyIntoBackupVault on the vault and encrypt-shaped access to the vault's key, and nothing else: it can write copies here but cannot delete them."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
  }
}

variable "kms_key_name" {
  description = "Name of the vault key (string): the alias is alias/<kms_key_name> and the key's Name tag is <kms_key_name>. Null uses vault_name."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[A-Za-z0-9/_-]{1,250}$", coalesce(var.kms_key_name, var.vault_name))) && !startswith(coalesce(var.kms_key_name, var.vault_name), "aws/")
    error_message = "The key name (kms_key_name, or vault_name when null) must be 1 to 250 characters of letters, digits, slashes, underscores and hyphens, and must not start with aws/, because KMS alias names allow neither dots nor that prefix."
  }
}

variable "s3_recovery_enabled" {
  description = "Attach the AWS Backup S3 backup and restore policies to the restore role (bool), for recovery points of S3 buckets. EBS-only deployments leave this off."
  type        = bool
  default     = false
  nullable    = false
}

variable "rds_service_linked_role_enabled" {
  description = "Create the RDS service-linked role in this account (bool). A cross-account copy of an RDS recovery point calls CreateServiceLinkedRole for rds.amazonaws.com here and fails outright if the role is missing. Creating it errors when the account already has one."
  type        = bool
  default     = false
  nullable    = false
}

variable "vault_reader_source_role_name" {
  description = "Name of a role in the source account that may assume a read-only role here (string), or null for no such role. The role can only call backup:DescribeBackupVault on this vault, which lets a monitoring or status role read the lock state. Trust names the source account root plus a PrincipalArn condition, so the source role need not exist yet."
  type        = string
  default     = null

  validation {
    condition     = var.vault_reader_source_role_name == null || can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", coalesce(var.vault_reader_source_role_name, "-")))
    error_message = "vault_reader_source_role_name must be null or a valid IAM role name."
  }
}

variable "vault_lock" {
  description = <<-EOT
    Vault Lock (WORM) on the destination vault (object). It makes the isolation
    hold against a compromised principal in this account, not only against the
    source account. mode picks the flavour:

      none       - vault policy only: the source account can copy in, not
                   delete. Do not lock a vault whose copy pipeline has not been
                   proven end to end.
      governance - WORM, removable by a principal in this account holding
                   backup:DeleteBackupVaultLockConfiguration. Paired with an SCP
                   that denies that permission to every principal in the
                   account, it cannot be removed from inside the account:
                   reversing it means detaching the SCP from the management
                   account first. That gives compliance-grade protection while
                   keeping a way back that does not wait out retention. Setting
                   mode back to none then fails with AccessDenied until the SCP
                   is detached, which is the control working.
      compliance - irreversible once changeable_for_days elapses. Nobody, not
                   AWS Support, can then delete the vault or its recovery
                   points until retention expires.

    min_retention_days and max_retention_days bound the retention a copy may
    ask for; a copy outside the range is rejected. A copy job with no lifecycle
    means infinite retention, which exceeds the maximum, so an ad-hoc
    start-copy-job must pass a lifecycle. changeable_for_days is the compliance
    cooling-off window (at least 3) and is ignored in governance mode.
  EOT
  type = object({
    mode                = optional(string, "none")
    min_retention_days  = optional(number, 7)
    max_retention_days  = optional(number, 365)
    changeable_for_days = optional(number, 3)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["none", "governance", "compliance"], var.vault_lock.mode)
    error_message = "vault_lock.mode must be one of: none, governance, compliance."
  }

  validation {
    condition     = var.vault_lock.min_retention_days >= 1 && var.vault_lock.min_retention_days <= var.vault_lock.max_retention_days
    error_message = "vault_lock.min_retention_days must be at least 1 and no greater than max_retention_days."
  }

  validation {
    condition     = var.vault_lock.mode != "compliance" || var.vault_lock.changeable_for_days >= 3
    error_message = "vault_lock.mode = compliance requires changeable_for_days of at least 3 (the AWS minimum cooling-off window)."
  }
}
