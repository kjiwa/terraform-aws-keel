data "aws_caller_identity" "current" {}

locals {
  source_root  = "arn:aws:iam::${var.source_account_id}:root"
  kms_key_name = coalesce(var.kms_key_name, var.vault_name)
}

# A cross-account destination vault cannot use the default vault: the
# AWS-managed aws/backup key has an immutable policy that cannot be shared
# cross-account. AWS Backup re-encrypts every copy landing here under this key,
# so it is the key that protects the off-site corpus.
#
# Root full-access delegates authorization to IAM, which lets the AWS Backup
# service-linked role in this account use the key without being named here: the
# destination account's role performs the copy, not the source's.
resource "aws_kms_key" "backup_replica" {
  description             = "Encrypts the ${var.vault_name} backup vault"
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
      },
      # Encrypt-shaped, never kms:*: the source account must not be able to
      # schedule this key for deletion, which would crypto-shred the off-site
      # copies from the account they exist to survive. Spelled out because the
      # source key policy on the other side must list the same actions; the
      # service rejects wildcards there.
      {
        Sid       = "SourceAccountCopyIn"
        Effect    = "Allow"
        Principal = { AWS = local.source_root }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
      {
        Sid       = "SourceAccountCreateGrant"
        Effect    = "Allow"
        Principal = { AWS = local.source_root }
        Action    = "kms:CreateGrant"
        Resource  = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      },
    ]
  })

  tags = {
    Name = local.kms_key_name
  }

  # Scheduling this key for deletion makes every off-site copy unreadable in 30
  # days, so a plan that would do it must fail.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "backup_replica" {
  name          = "alias/${local.kms_key_name}"
  target_key_id = aws_kms_key.backup_replica.key_id
}
