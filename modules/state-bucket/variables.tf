variable "bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state (string). Backend blocks cannot read variables, so the same name is stated in every backend configuration that uses the bucket."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3 to 63 characters of lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit."
  }
}

variable "kms_encryption_enabled" {
  description = "Encrypt the bucket with a customer-managed KMS key (bool). The key costs about 1 USD per month; false falls back to SSE-S3. Turning it off on a deployed bucket is refused by prevent_destroy on the key."
  type        = bool
  default     = true
  nullable    = false
}
