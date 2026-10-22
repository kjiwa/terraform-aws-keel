# backup-vault-account

The backup-account half of cross-account AWS Backup: a customer-managed KMS key, a destination vault that accepts copies from one source account and nothing more, optional Vault Lock, and a pre-provisioned restore role. Apply it with credentials for the backup account, with its own state bucket there, so that state is not reachable from the workload account.

The vault, its key, and the restore role are the recovery path, so the vault and key are protected by `prevent_destroy`.

The caller's provider sets the region, `allowed_account_ids`, and default tags. Pin `allowed_account_ids` to the backup account: applying this module with the workload account's credentials would build the "isolated" vault inside the account it exists to be isolated from.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.15 |
| aws | >= 6.45 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_backup_vault.replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_backup_vault_lock_configuration.replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_lock_configuration) | resource |
| [aws_backup_vault_policy.replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_policy) | resource |
| [aws_iam_role.restore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.vault_reader](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.vault_reader](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.restore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_service_linked_role.rds](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_service_linked_role) | resource |
| [aws_kms_alias.backup_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.backup_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.restore_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_reader](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_reader_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name\_prefix | Prefix for the IAM role names this module creates (string, lowercase letters, digits and hyphens). | `string` | n/a | yes |
| source\_account\_id | AWS account ID of the workload account whose backups are copied here (string). It is granted backup:CopyIntoBackupVault on the vault and encrypt-shaped access to the vault's key, and nothing else: it can write copies here but cannot delete them. | `string` | n/a | yes |
| vault\_name | Backup vault name (string). The workload account builds this vault's ARN from the backup account ID, region and this name, so the two sides must state the same name; a mismatch fails at copy-job runtime, not at plan time. | `string` | n/a | yes |
| kms\_key\_name | Name of the vault key (string): the alias is alias/<kms\_key\_name> and the key's Name tag is <kms\_key\_name>. Null uses vault\_name. | `string` | `null` | no |
| rds\_service\_linked\_role\_enabled | Create the RDS service-linked role in this account (bool). A cross-account copy of an RDS recovery point calls CreateServiceLinkedRole for rds.amazonaws.com here and fails outright if the role is missing. Creating it errors when the account already has one. | `bool` | `false` | no |
| s3\_recovery\_enabled | Attach the AWS Backup S3 backup and restore policies to the restore role (bool), for recovery points of S3 buckets. EBS-only deployments leave this off. | `bool` | `false` | no |
| vault\_lock | Vault Lock (WORM) on the destination vault (object). It makes the isolation hold against a compromised principal in this account, not only against the source account. mode picks the flavour:    none       - vault policy only: the source account can copy in, not                delete. Do not lock a vault whose copy pipeline has not been                proven end to end.   governance - WORM, removable by a principal in this account holding                backup:DeleteBackupVaultLockConfiguration. Paired with an SCP                that denies that permission to every principal in the                account, it cannot be removed from inside the account:                reversing it means detaching the SCP from the management                account first. That gives compliance-grade protection while                keeping a way back that does not wait out retention. Setting                mode back to none then fails with AccessDenied until the SCP                is detached, which is the control working.   compliance - irreversible once changeable\_for\_days elapses. Nobody, not                AWS Support, can then delete the vault or its recovery                points until retention expires.  min\_retention\_days and max\_retention\_days bound the retention a copy may ask for; a copy outside the range is rejected. A copy job with no lifecycle means infinite retention, which exceeds the maximum, so an ad-hoc start-copy-job must pass a lifecycle. changeable\_for\_days is the compliance cooling-off window (at least 3) and is ignored in governance mode. | ```object({ mode = optional(string, "none") min_retention_days = optional(number, 7) max_retention_days = optional(number, 365) changeable_for_days = optional(number, 3) })``` | `{}` | no |
| vault\_reader\_source\_role\_name | Name of a role in the source account that may assume a read-only role here (string), or null for no such role. The role can only call backup:DescribeBackupVault on this vault, which lets a monitoring or status role read the lock state. Trust names the source account root plus a PrincipalArn condition, so the source role need not exist yet. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| kms\_key\_arn | ARN of the CMK encrypting the vault. Copies landing here are re-encrypted under it; the workload account never needs it, so it is for verification and key-rotation audits. |
| restore\_role\_arn | ARN of the role both recovery paths run through, from this account: restoring a recovery point here, or copying one back to the workload account. Pass it to start-restore-job or to start-copy-job --iam-role-arn. |
| vault\_arn | ARN of the destination backup vault, for verification and for an on-demand start-copy-job. The workload account builds the same ARN from the backup account ID, region and vault name instead of reading this. |
| vault\_name | Name of the destination backup vault. Must equal the destination vault name configured on the workload side. |
| vault\_reader\_role\_arn | ARN of the read-only role the source role may assume to describe the vault, or null when vault\_reader\_source\_role\_name is null. |
<!-- END_TF_DOCS -->
