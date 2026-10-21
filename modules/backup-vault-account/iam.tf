# The role that gets the data back out. Both recovery paths run through it and
# must be driven from this account, because AWS Backup cannot restore
# cross-account and copy jobs resolve the source vault in the caller's account:
#
#   - Restore inside this account (the fast path).
#   - Copy a recovery point back to the workload account and restore it there.
#
# Pre-provisioned so recovery does not depend on console creation during an
# incident.
data "aws_iam_policy_document" "restore_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "restore" {
  name               = "${var.name_prefix}-restore"
  assume_role_policy = data.aws_iam_policy_document.restore_assume.json

  tags = {
    Name = "${var.name_prefix}-restore"
  }
}

# ForBackup carries backup:CopyFromBackupVault and backup:CopyIntoBackupVault,
# the identity half of a cross-account copy. The S3 pair is separate from the
# EBS pair, and its two policies live at the policy root, not under
# service-role/ like the EBS pair, despite the matching names.
resource "aws_iam_role_policy_attachment" "restore" {
  for_each = toset(concat(
    [
      "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
      "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    ],
    var.s3_recovery_enabled ? [
      "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup",
      "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore",
    ] : [],
  ))

  role       = aws_iam_role.restore.name
  policy_arn = each.value
}

# AWS Backup's own service-linked role cannot create this one, so the first
# cross-account copy of an RDS recovery point would fail without it.
resource "aws_iam_service_linked_role" "rds" {
  count            = var.rds_service_linked_role_enabled ? 1 : 0
  aws_service_name = "rds.amazonaws.com"
}

# Root principal plus a PrincipalArn condition, not the role ARN as principal:
# IAM validates principal ARNs at creation, so naming the role would fail this
# apply whenever the source role does not exist yet.
data "aws_iam_policy_document" "vault_reader_assume" {
  count = var.vault_reader_source_role_name == null ? 0 : 1

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [local.source_root]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${var.source_account_id}:role/${var.vault_reader_source_role_name}"]
    }
  }
}

resource "aws_iam_role" "vault_reader" {
  count              = var.vault_reader_source_role_name == null ? 0 : 1
  name               = "${var.name_prefix}-vault-reader"
  assume_role_policy = data.aws_iam_policy_document.vault_reader_assume[0].json

  tags = {
    Name = "${var.name_prefix}-vault-reader"
  }
}

# DescribeBackupVault on this one vault: it cannot read, copy, delete, or
# enumerate recovery points.
data "aws_iam_policy_document" "vault_reader" {
  count = var.vault_reader_source_role_name == null ? 0 : 1

  statement {
    sid       = "DescribeReplicaVault"
    effect    = "Allow"
    actions   = ["backup:DescribeBackupVault"]
    resources = [aws_backup_vault.replica.arn]
  }
}

resource "aws_iam_role_policy" "vault_reader" {
  count  = var.vault_reader_source_role_name == null ? 0 : 1
  name   = "${var.name_prefix}-vault-reader"
  role   = aws_iam_role.vault_reader[0].id
  policy = data.aws_iam_policy_document.vault_reader[0].json
}
