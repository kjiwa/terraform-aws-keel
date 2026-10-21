resource "aws_s3_bucket" "tfstate_web" {
  bucket = var.bucket_name

  tags = {
    Name = var.bucket_name
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate_web" {
  bucket                  = aws_s3_bucket.tfstate_web.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate_web" {
  bucket = aws_s3_bucket.tfstate_web.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "tfstate_web" {
  bucket = aws_s3_bucket.tfstate_web.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_web" {
  bucket = aws_s3_bucket.tfstate_web.id

  rule {
    bucket_key_enabled = var.kms_encryption_enabled ? true : null

    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_encryption_enabled ? "aws:kms" : "AES256"
      kms_master_key_id = one(aws_kms_key.tfstate_web[*].arn)
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate_web" {
  bucket = aws_s3_bucket.tfstate_web.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# The state bucket holds every ARN and resource detail in the estate, so
# plaintext transport must not be allowed.
data "aws_iam_policy_document" "tfstate_web" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.tfstate_web.arn, "${aws_s3_bucket.tfstate_web.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate_web" {
  bucket = aws_s3_bucket.tfstate_web.id

  # S3 can reject concurrent bucket-level configuration calls.
  depends_on = [aws_s3_bucket_public_access_block.tfstate_web]

  policy = data.aws_iam_policy_document.tfstate_web.json
}
