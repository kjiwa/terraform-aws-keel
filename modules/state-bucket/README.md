# state-bucket

S3 bucket for Terraform state: versioned, private, TLS-only, encrypted by default with a customer-managed KMS key, with stale multipart uploads and old versions expired. Locking uses the S3 backend's native lock file (`use_lockfile = true`), which needs no further resources.

The bucket and its key are protected by `prevent_destroy`. Run one instance per AWS account. To bootstrap, create the bucket by hand, point a partial `backend "s3" {}` at it, then `terraform import` the bucket and apply. Leave `encrypt` and `kms_key_id` out of the backend configuration: they would override the bucket's default encryption.

The caller's provider sets the region, `allowed_account_ids`, and default tags.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.15 |
| aws | >= 6.45 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_name | Globally unique S3 bucket name for Terraform state (string). Backend blocks cannot read variables, so the same name is stated in every backend configuration that uses the bucket. | `string` | n/a | yes |
| kms\_encryption\_enabled | Encrypt the bucket with a customer-managed KMS key (bool). The key costs about 1 USD per month; false falls back to SSE-S3. Turning it off on a deployed bucket is refused by prevent\_destroy on the key. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_arn | ARN of the state bucket, for the IAM policies of the principals that run Terraform. |
| bucket\_name | Name of the state bucket. Put it in the `bucket` argument of every S3 backend that stores state here. |
| kms\_key\_arn | ARN of the CMK encrypting the bucket, or null when kms\_encryption\_enabled is false. Principals that run Terraform need kms:Decrypt and kms:GenerateDataKey on it unless their identity policy already allows kms:* via the key's root delegation. |
<!-- END_TF_DOCS -->
