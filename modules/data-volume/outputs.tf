output "volume_id" {
  description = "EBS data volume ID. User-data attaches it by ID at boot."
  value       = aws_ebs_volume.this.id
}

output "volume_arn" {
  description = "EBS data volume ARN. Scopes AttachVolume in the instance IAM policy."
  value       = aws_ebs_volume.this.arn
}

output "volume_kms_key_arn" {
  description = "CMK ARN encrypting the volume (string), or null unless backup.mode is cross_account. The re-key procedure for a volume that predates the key consumes it."
  value       = one(aws_kms_key.data[*].arn)
}

output "vault_name" {
  description = "Local AWS Backup vault the daily plan writes to (string), or null when backup.mode is disabled."
  value       = one(aws_backup_vault.this[*].name)
}

output "backup_copy_vault_arn" {
  description = "Vault each recovery point is copied to (string): the replica vault under cross_region, the constructed destination vault ARN under cross_account, null otherwise."
  value       = local.backup_copy_vault_arn
}

output "backup_resource_count" {
  description = "Number of resources the backup selection covers (number): the volume plus extra_backup_resource_arns. Makes recovery-point counts checkable as resource_count x retention_days."
  value       = length(local.backup_resources)
}

output "backup_remote_retention_days" {
  description = "Off-site copy retention the plan applies (number): backup.remote_retention_days with 0 resolved to backup.retention_days."
  value       = local.backup_remote_retention_days
}
