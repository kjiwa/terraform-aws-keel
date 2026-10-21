# CMK for the trail objects in the Object-Locked bucket and the parallel
# CloudWatch Logs group, with an auditable policy and annual rotation. The
# access-log bucket stays SSE-S3 so the S3 logging service can deliver without a
# key grant.
resource "aws_kms_key" "audit" {
  count                   = var.kms_encryption_enabled ? 1 : 0
  description             = "Encrypts ${var.name_prefix} CloudTrail logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudTrailEncrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:GenerateDataKey*"
        Resource  = "*"
        Condition = {
          StringLike = {
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid       = "AllowCloudTrailDescribeKey"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:DescribeKey"
        Resource  = "*"
      },
      {
        # Scoped to this account's log groups via the encryption context.
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${local.region}:${local.account_id}:log-group:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-audit"
  }

  # Deleting the key makes the whole CloudTrail archive unreadable.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "audit" {
  count         = var.kms_encryption_enabled ? 1 : 0
  name          = "alias/${var.name_prefix}-audit"
  target_key_id = aws_kms_key.audit[0].key_id
}

moved {
  from = aws_kms_key.audit
  to   = aws_kms_key.audit[0]
}

moved {
  from = aws_kms_alias.audit
  to   = aws_kms_alias.audit[0]
}
