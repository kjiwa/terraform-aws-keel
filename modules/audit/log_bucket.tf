# Isolated destination for S3 server access logs, kept out of the workload
# buckets it records: locked down (public access blocked, ownership enforced),
# versioned, encrypted at rest, expired on a retention schedule. SSE-S3 (not
# KMS) is deliberate -- the S3 logging service cannot deliver to a bucket whose
# default encryption is a CMK it has no grant on.
#
# CloudTrail writes to the Object-Locked bucket in trail_bucket.tf, not here --
# an Object Lock bucket cannot be a server-access-logging destination, so the
# two records cannot share a bucket.
resource "aws_s3_bucket" "logs" {
  bucket = "${var.name_prefix}-logs-${local.account_id}"

  tags = {
    Name = "${var.name_prefix}-logs"
  }

  # Holds S3 access logs; never let a Terraform change delete it.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket     = aws_s3_bucket.logs.id
  depends_on = [aws_s3_bucket_versioning.logs]

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-delete-markers"
    status = "Enabled"
    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }
}

# Bucket policy: let the S3 logging service deliver access logs, scoped to this
# account and to the named source buckets. TLS-only for every principal.
data "aws_iam_policy_document" "logs" {
  dynamic "statement" {
    for_each = length(var.log_source_buckets) > 0 ? [1] : []
    content {
      sid     = "S3ServerAccessLogsDelivery"
      effect  = "Allow"
      actions = ["s3:PutObject"]
      principals {
        type        = "Service"
        identifiers = ["logging.s3.amazonaws.com"]
      }
      resources = ["${aws_s3_bucket.logs.arn}/s3-access/*"]
      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = [for b in var.log_source_buckets : b.arn]
      }
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
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

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json
}
