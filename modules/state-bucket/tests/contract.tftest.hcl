mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/demo"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  bucket_name = "demo-app-tfstate-123456789012"
}

run "default_bucket_shape" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "demo-app-tfstate-123456789012" && aws_s3_bucket.this.tags["Name"] == "demo-app-tfstate-123456789012"
    error_message = "The bucket must carry var.bucket_name as its name and Name tag."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public access blocks must be on."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled with BucketOwnerEnforced."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.this.versioning_configuration).status == "Enabled"
    error_message = "Versioning must be enabled."
  }
}

run "default_encryption_is_kms" {
  command = plan

  assert {
    condition     = one(aws_kms_key.this).enable_key_rotation && one(aws_kms_key.this).deletion_window_in_days == 30
    error_message = "The state key must rotate and keep a 30 day deletion window."
  }

  assert {
    condition     = one(aws_kms_alias.this).name == "alias/s3/demo-app-tfstate-123456789012"
    error_message = "The alias must be alias/s3/<bucket_name>."
  }

  assert {
    condition = (
      one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
      && one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled
    )
    error_message = "The bucket must default to aws:kms with a bucket key."
  }

  assert {
    condition = (
      length(jsondecode(one(aws_kms_key.this).policy).Statement) == 1
      && jsondecode(one(aws_kms_key.this).policy).Statement[0].Sid == "RootFullAccess"
      && jsondecode(one(aws_kms_key.this).policy).Statement[0].Principal.AWS == "arn:aws:iam::123456789012:root"
    )
    error_message = "The key policy must be the single root delegation statement for this account."
  }
}

run "kms_off_falls_back_to_sse_s3" {
  command = plan

  variables {
    kms_encryption_enabled = false
  }

  assert {
    condition     = length(aws_kms_key.this) == 0 && length(aws_kms_alias.this) == 0
    error_message = "No key or alias may exist when kms_encryption_enabled is false."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Without KMS the bucket must default to AES256."
  }
}

run "lifecycle_rules" {
  command = plan

  assert {
    condition = (
      length(aws_s3_bucket_lifecycle_configuration.this.rule) == 2
      && one([for r in aws_s3_bucket_lifecycle_configuration.this.rule : one(r.abort_incomplete_multipart_upload).days_after_initiation if r.id == "abort-incomplete-multipart"]) == 7
      && one([for r in aws_s3_bucket_lifecycle_configuration.this.rule : one(r.noncurrent_version_expiration).noncurrent_days if r.id == "expire-noncurrent-versions"]) == 90
    )
    error_message = "Incomplete uploads must abort after 7 days and noncurrent versions expire after 90."
  }
}

run "tls_only_policy" {
  command = plan

  assert {
    condition = (
      length(data.aws_iam_policy_document.this.statement) == 1
      && one(data.aws_iam_policy_document.this.statement).sid == "DenyInsecureTransport"
      && one(data.aws_iam_policy_document.this.statement).effect == "Deny"
      && one(one(data.aws_iam_policy_document.this.statement).condition).variable == "aws:SecureTransport"
    )
    error_message = "The bucket policy must deny every request made without TLS."
  }
}

run "rejects_bad_bucket_name" {
  command = plan

  variables {
    bucket_name = "Not_A_Bucket"
  }

  expect_failures = [var.bucket_name]
}

run "noncurrent_expiry_cleans_delete_markers" {
  command = plan

  assert {
    condition     = anytrue([for r in aws_s3_bucket_lifecycle_configuration.this.rule : length(r.expiration) > 0 && r.expiration[0].expired_object_delete_marker == true]) || !anytrue([for r in aws_s3_bucket_lifecycle_configuration.this.rule : length(r.noncurrent_version_expiration) > 0])
    error_message = "Every lifecycle configuration with noncurrent_version_expiration must have a rule with expired_object_delete_marker = true."
  }
}
