locals {
  backup_enabled       = var.backup.mode != "disabled"
  backup_offsite       = contains(["cross_region", "cross_account"], var.backup.mode)
  backup_cross_region  = var.backup.mode == "cross_region"
  backup_cross_account = var.backup.mode == "cross_account"
  vault_cmk            = local.backup_enabled && var.vault_kms == "cmk"
  replica_cmk          = local.backup_cross_region && var.vault_kms == "cmk"

  # A vault ARN is fully determined by account, region and name, so the
  # contract with the backup account's vault is the name alone. A mismatch
  # fails at copy-job runtime; Terraform cannot check a vault in another
  # account.
  backup_copy_vault_arn = (
    local.backup_cross_region ? one(aws_backup_vault.replica[*].arn) :
    local.backup_cross_account ? "arn:aws:backup:${var.backup_region}:${var.backup.account_id}:backup-vault:${coalesce(var.backup.dest_vault_name, "${var.name_prefix}-backup")}" :
    null
  )

  backup_remote_retention_days = (
    var.backup.remote_retention_days > 0
    ? var.backup.remote_retention_days
    : var.backup.retention_days
  )

  # The two S3 policies live at the policy root and the other two under
  # service-role/. A wrong path fails at apply time, not plan time.
  backup_role_policies = local.backup_enabled ? toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore",
  ]) : toset([])

  # Explicit ARNs rather than tag selection: a tag-based set changes the first
  # time anything else in the account wears the tag.
  backup_resources = concat([aws_ebs_volume.this.arn], var.extra_backup_resource_arns)
}

# AWS Backup encrypts S3 recovery points under the vault key, so a cross-account
# copy of S3 data needs a key the destination account can use. EBS recovery
# points keep the volume's key and never touch this one.
data "aws_iam_policy_document" "backup_key" {
  count = local.vault_cmk ? 1 : 0

  statement {
    sid       = "RootFullAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Mirror of SourceAccountCopyIn on the backup account's key: the copy back
  # re-encrypts under this key, so decrypt alone is not enough.
  dynamic "statement" {
    for_each = local.backup_cross_account ? [1] : []
    content {
      sid    = "BackupAccountCopy"
      effect = "Allow"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncryptFrom",
        "kms:ReEncryptTo",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:DescribeKey",
      ]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${var.backup.account_id}:root"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.backup_cross_account ? [1] : []
    content {
      sid       = "BackupAccountCreateGrant"
      effect    = "Allow"
      actions   = ["kms:CreateGrant"]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${var.backup.account_id}:root"]
      }
      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }
}

resource "aws_kms_key" "backup" {
  count = local.vault_cmk ? 1 : 0

  description             = "Encrypts the ${var.name_prefix}-backup vault"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.backup_key[0].json

  tags = {
    Name = "${var.name_prefix}-backup"
  }
}

resource "aws_kms_alias" "backup" {
  count         = local.vault_cmk ? 1 : 0
  name          = "alias/${var.name_prefix}-backup"
  target_key_id = aws_kms_key.backup[0].key_id
}

resource "aws_backup_vault" "this" {
  count       = local.backup_enabled ? 1 : 0
  name        = "${var.name_prefix}-backup"
  kms_key_arn = one(aws_kms_key.backup[*].arn)

  tags = {
    Name = "${var.name_prefix}-backup"
  }
}

# Return path: lets the backup account copy a recovery point back here, and
# nothing else. A copy back takes 4 to 6 hours and shows CREATED with no status
# message throughout, so a short poll cannot tell it from a hung job.
data "aws_iam_policy_document" "backup_vault" {
  count = local.backup_cross_account ? 1 : 0

  statement {
    sid       = "AllowBackupAccountCopyBack"
    effect    = "Allow"
    actions   = ["backup:CopyIntoBackupVault"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.backup.account_id}:root"]
    }
  }
}

resource "aws_backup_vault_policy" "this" {
  count             = local.backup_cross_account ? 1 : 0
  backup_vault_name = aws_backup_vault.this[0].name
  policy            = data.aws_iam_policy_document.backup_vault[0].json
}

resource "aws_kms_key" "backup_replica" {
  count  = local.replica_cmk ? 1 : 0
  region = var.backup_region

  description             = "Encrypts the ${var.name_prefix}-backup-replica vault in ${var.backup_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-backup-replica"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "backup_replica" {
  count         = local.replica_cmk ? 1 : 0
  region        = var.backup_region
  name          = "alias/${var.name_prefix}-backup-replica"
  target_key_id = aws_kms_key.backup_replica[0].key_id
}

# prevent_destroy on the vault and its key: leaving cross_region drops both to
# count 0, and Terraform would schedule the key for deletion while failing to
# delete the non-empty vault, leaving copies unreadable in 30 days. The plan
# errors instead. To retire it, delete the recovery points, remove these
# lifecycle blocks, and apply.
resource "aws_backup_vault" "replica" {
  count       = local.backup_cross_region ? 1 : 0
  region      = var.backup_region
  name        = "${var.name_prefix}-backup-replica"
  kms_key_arn = one(aws_kms_key.backup_replica[*].arn)

  tags = {
    Name = "${var.name_prefix}-backup-replica"
  }

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  count              = local.backup_enabled ? 1 : 0
  name               = "${var.name_prefix}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json

  tags = {
    Name = "${var.name_prefix}-backup"
  }
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each   = local.backup_role_policies
  role       = aws_iam_role.backup[0].name
  policy_arn = each.value
}

# Periodic rather than continuous: continuous backup of S3 depends on the
# bucket's EventBridge notifications, and if those are ever turned off the
# backups stop silently with no alarm and no failed job. It also caps
# retention at 35 days.
resource "aws_backup_plan" "this" {
  count = local.backup_enabled ? 1 : 0
  name  = "${var.name_prefix}-daily"

  rule {
    rule_name         = "daily-${var.backup.retention_days}d"
    target_vault_name = aws_backup_vault.this[0].name
    schedule          = var.backup.schedule

    lifecycle {
      delete_after = var.backup.retention_days
    }

    # No cold-storage transition: cross-account copies of cold-tier recovery
    # points are unsupported, and S3 recovery points cannot be tiered.
    dynamic "copy_action" {
      for_each = local.backup_offsite ? [1] : []
      content {
        destination_vault_arn = local.backup_copy_vault_arn

        lifecycle {
          delete_after = local.backup_remote_retention_days
        }
      }
    }
  }

  tags = {
    Name = "${var.name_prefix}-daily"
  }
}

resource "aws_backup_selection" "this" {
  count        = local.backup_enabled ? 1 : 0
  name         = "${var.name_prefix}-irreplaceable"
  iam_role_arn = aws_iam_role.backup[0].arn
  plan_id      = aws_backup_plan.this[0].id

  resources = local.backup_resources
}
