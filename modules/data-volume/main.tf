data "aws_caller_identity" "current" {}

locals {
  volume_name = coalesce(var.volume_name, "${var.name_prefix}-data")
}

# Present only under cross_account: aws/ebs has an immutable policy and cannot
# be shared with another account, so a volume on it cannot be copied to one.
# Gated because kms_key_id is ForceNew; naming a key unconditionally would plan
# a replace of every existing volume, which prevent_destroy refuses.
data "aws_iam_policy_document" "data_key" {
  count = local.backup_cross_account ? 1 : 0

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

  # Data-key actions only, so the backup account cannot schedule this key for
  # deletion. Spelled out because the GenerateDataKey* and ReEncrypt* wildcards
  # also grant asymmetric key-pair operations.
  statement {
    sid    = "BackupAccountCopySnapshot"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.backup.account_id}:root"]
    }
  }

  # AWS Backup creates grants on the caller's behalf to run a copy job;
  # GrantIsForAWSResource confines this to grants AWS services make for
  # themselves.
  statement {
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

resource "aws_kms_key" "data" {
  count = local.backup_cross_account ? 1 : 0

  description             = "Encrypts the ${local.volume_name} EBS volume"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.data_key[0].json

  tags = {
    Name = local.volume_name
  }
}

resource "aws_kms_alias" "data" {
  count         = local.backup_cross_account ? 1 : 0
  name          = "alias/${local.volume_name}"
  target_key_id = aws_kms_key.data[0].key_id
}

resource "aws_ebs_volume" "this" {
  availability_zone = var.az
  size              = var.size_gib
  type              = "gp3"
  encrypted         = true
  snapshot_id       = var.snapshot_id

  # Null outside cross_account means "whatever the volume already uses", so a
  # volume that never leaves the account keeps its key with no diff.
  kms_key_id = local.backup_cross_account ? aws_kms_key.data[0].arn : null

  tags = merge(var.volume_tags, {
    Name       = local.volume_name
    Persistent = "true"
  })

  lifecycle {
    prevent_destroy = true
  }
}
