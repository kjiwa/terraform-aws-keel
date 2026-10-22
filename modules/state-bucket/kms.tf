data "aws_caller_identity" "current" {}

resource "aws_kms_key" "this" {
  count                   = var.kms_encryption_enabled ? 1 : 0
  description             = "Encrypts the ${var.bucket_name} S3 bucket"
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
    Name = var.bucket_name
  }

  # Deleting the key makes every state version unreadable.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "this" {
  count         = var.kms_encryption_enabled ? 1 : 0
  name          = "alias/s3/${var.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}
