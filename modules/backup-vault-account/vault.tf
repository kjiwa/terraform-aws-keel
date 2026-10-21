# The destination vault, owned by this account and encrypted under its key. A
# copy landing here is a separate object in a separate account, out of reach of
# anything the workload account can do.
resource "aws_backup_vault" "replica" {
  name        = var.vault_name
  kms_key_arn = aws_kms_key.backup_replica.arn

  tags = {
    Name = var.vault_name
  }

  # Holds the only copies that survive losing the workload account.
  lifecycle {
    prevent_destroy = true
  }
}

# The source account gets CopyIntoBackupVault and nothing else: it can write
# copies here and cannot read, delete, or enumerate them. Scoped to the account
# rather than aws:PrincipalOrgID, which would silently extend to accounts added
# to the organization later.
data "aws_iam_policy_document" "replica" {
  statement {
    sid       = "AllowSourceAccountCopyIn"
    effect    = "Allow"
    actions   = ["backup:CopyIntoBackupVault"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.source_root]
    }
  }
}

resource "aws_backup_vault_policy" "replica" {
  backup_vault_name = aws_backup_vault.replica.name
  policy            = data.aws_iam_policy_document.replica.json
}

# The vault policy stops the source account from deleting copies; the lock stops
# principals in this account too. Off by default because locking an unproven
# copy pipeline can leave you paying for recovery points you cannot delete.
# See var.vault_lock for the modes.
resource "aws_backup_vault_lock_configuration" "replica" {
  count             = var.vault_lock.mode == "none" ? 0 : 1
  backup_vault_name = aws_backup_vault.replica.name

  min_retention_days = var.vault_lock.min_retention_days
  max_retention_days = var.vault_lock.max_retention_days

  # Setting it turns the lock into compliance mode, so governance must omit it.
  changeable_for_days = var.vault_lock.mode == "compliance" ? var.vault_lock.changeable_for_days : null
}
