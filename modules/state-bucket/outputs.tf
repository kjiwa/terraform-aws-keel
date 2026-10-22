output "bucket_name" {
  description = "Name of the state bucket. Put it in the `bucket` argument of every S3 backend that stores state here."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the state bucket, for the IAM policies of the principals that run Terraform."
  value       = aws_s3_bucket.this.arn
}

output "kms_key_arn" {
  description = "ARN of the CMK encrypting the bucket, or null when kms_encryption_enabled is false. Principals that run Terraform need kms:Decrypt and kms:GenerateDataKey on it unless their identity policy already allows kms:* via the key's root delegation."
  value       = one(aws_kms_key.this[*].arn)
}
