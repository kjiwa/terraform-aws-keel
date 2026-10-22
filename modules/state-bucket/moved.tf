moved {
  from = aws_s3_bucket.tfstate_web
  to   = aws_s3_bucket.this
}

moved {
  from = aws_s3_bucket_public_access_block.tfstate_web
  to   = aws_s3_bucket_public_access_block.this
}

moved {
  from = aws_s3_bucket_ownership_controls.tfstate_web
  to   = aws_s3_bucket_ownership_controls.this
}

moved {
  from = aws_s3_bucket_versioning.tfstate_web
  to   = aws_s3_bucket_versioning.this
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.tfstate_web
  to   = aws_s3_bucket_server_side_encryption_configuration.this
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.tfstate_web
  to   = aws_s3_bucket_lifecycle_configuration.this
}

moved {
  from = aws_s3_bucket_policy.tfstate_web
  to   = aws_s3_bucket_policy.this
}

moved {
  from = aws_kms_key.tfstate_web
  to   = aws_kms_key.this
}

moved {
  from = aws_kms_alias.tfstate_web
  to   = aws_kms_alias.this
}
