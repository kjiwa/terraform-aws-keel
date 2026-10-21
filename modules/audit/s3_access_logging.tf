# Server access logging on the workload buckets -> the isolated log bucket, under
# a per-bucket prefix. Object-level access records complementing the API-level
# CloudTrail record.
#
# When a source bucket is created in the same apply, its name is unknown while
# this for_each is evaluated; applying the bucket first (-target) converges it.
# Keying on the bucket name keeps existing logging configs at the same address;
# an index would reassign every one of them.
resource "aws_s3_bucket_logging" "source" {
  for_each = { for b in var.log_source_buckets : b.name => b }

  bucket        = each.value.name
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/${each.value.name}/"

  depends_on = [aws_s3_bucket_policy.logs]
}
