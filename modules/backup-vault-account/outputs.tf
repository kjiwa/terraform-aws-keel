output "vault_arn" {
  description = "ARN of the destination backup vault, for verification and for an on-demand start-copy-job. The workload account builds the same ARN from the backup account ID, region and vault name instead of reading this."
  value       = aws_backup_vault.replica.arn
}

output "vault_name" {
  description = "Name of the destination backup vault. Must equal the destination vault name configured on the workload side."
  value       = aws_backup_vault.replica.name
}

output "kms_key_arn" {
  description = "ARN of the CMK encrypting the vault. Copies landing here are re-encrypted under it; the workload account never needs it, so it is for verification and key-rotation audits."
  value       = aws_kms_key.backup_replica.arn
}

output "restore_role_arn" {
  description = "ARN of the role both recovery paths run through, from this account: restoring a recovery point here, or copying one back to the workload account. Pass it to start-restore-job or to start-copy-job --iam-role-arn."
  value       = aws_iam_role.restore.arn
}

output "vault_reader_role_arn" {
  description = "ARN of the read-only role the source role may assume to describe the vault, or null when vault_reader_source_role_name is null."
  value       = one(aws_iam_role.vault_reader[*].arn)
}
