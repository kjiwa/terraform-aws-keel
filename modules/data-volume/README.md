# data-volume

Encrypted gp3 EBS data volume with `prevent_destroy`, and one AWS Backup plan that covers it and any extra resources: local vault, optional cross-region replica vault, or cross-account copy into a vault from `backup-vault-account`. `vault_kms` selects the AWS-managed or a customer-managed key for the vaults. The replica vault uses the provider's per-resource `region`, so no provider alias is needed.


<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.15 |
| aws | >= 6.45 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_backup_plan.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan) | resource |
| [aws_backup_selection.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_selection) | resource |
| [aws_backup_vault.replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_backup_vault.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_backup_vault_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_policy) | resource |
| [aws_ebs_volume.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume) | resource |
| [aws_iam_role.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.backup_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.backup_replica](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.backup_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.backup_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.backup_vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.data_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| az | Availability zone for the EBS volume (string). Must match the instance AZ. | `string` | n/a | yes |
| backup\_region | Region of the off-site copy (string). The replica vault is created there under cross\_region, and the destination vault ARN is built from it under cross\_account, so it must match the backup account's region. Unused for local and disabled. | `string` | n/a | yes |
| name\_prefix | Prefix for the names of the vault, plan, selection, role and keys this module creates (string, lowercase letters, digits and hyphens). | `string` | n/a | yes |
| backup | Backup of the volume and any extra resources through one AWS Backup plan (object).    mode                  local (daily recovery points in this account and                         region), cross\_region (also copy each to a vault                         this module creates in backup\_region),                         cross\_account (also copy each to a vault another                         account owns, named by account\_id and                         dest\_vault\_name), or disabled.   schedule              Cron or rate expression for the plan.   retention\_days        Days the local vault keeps a recovery point.   remote\_retention\_days Days the off-site copy is kept; 0 means the same                         as retention\_days.   account\_id            12-digit destination account, required for                         cross\_account.   dest\_vault\_name       Destination vault name for cross\_account; null                         uses <name\_prefix>-backup. The destination ARN is                         constructed from it, so the name must match the                         backup account's vault.  Only cross\_account yields a copy this account cannot delete. It also needs a customer-managed key on the volume, because aws/ebs cannot be shared with another account. | ```object({ mode = optional(string, "local") schedule = optional(string, "cron(0 3 * * ? *)") retention_days = optional(number, 7) remote_retention_days = optional(number, 0) account_id = optional(string, "") dest_vault_name = optional(string) })``` | `{}` | no |
| extra\_backup\_resource\_arns | ARNs of further resources for the backup selection (list of string), such as an S3 media bucket. The volume is always selected. | `list(string)` | `[]` | no |
| size\_gib | Size of the EBS data volume in GiB (number, gp3). Raising it is an in-place ModifyVolume; lowering it is not supported by EBS. | `number` | `8` | no |
| snapshot\_id | EC2 snapshot ID to create the volume from (string), or null. First apply only: snapshot\_id is ForceNew and the volume carries prevent\_destroy, so setting it on a live volume plans a replace that errors instead of adopting the volume. For rebuilding an environment from a disaster-recovery snapshot. | `string` | `null` | no |
| vault\_kms | Encryption of the local and replica vaults (string): aws\_managed uses the AWS-managed aws/backup key at no cost; cmk creates a customer-managed key per vault at about $1 per month each. EBS recovery points are encrypted by the volume's key either way, so aws\_managed suffices for an EBS-only plan; S3 resources in extra\_backup\_resource\_arns need cmk to be copied cross-account. A vault's key cannot change after creation, so match the existing vault. | `string` | `"aws_managed"` | no |
| volume\_name | Name tag of the volume and basis of its data key alias (string). Null uses <name\_prefix>-data. | `string` | `null` | no |
| volume\_tags | Extra tags for the volume (map of string), merged under Name and Persistent. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| backup\_copy\_vault\_arn | Vault each recovery point is copied to (string): the replica vault under cross\_region, the constructed destination vault ARN under cross\_account, null otherwise. |
| backup\_remote\_retention\_days | Off-site copy retention the plan applies (number): backup.remote\_retention\_days with 0 resolved to backup.retention\_days. |
| backup\_resource\_count | Number of resources the backup selection covers (number): the volume plus extra\_backup\_resource\_arns. Makes recovery-point counts checkable as resource\_count x retention\_days. |
| vault\_name | Local AWS Backup vault the daily plan writes to (string), or null when backup.mode is disabled. |
| volume\_arn | EBS data volume ARN. Scopes AttachVolume in the instance IAM policy. |
| volume\_id | EBS data volume ID. User-data attaches it by ID at boot. |
| volume\_kms\_key\_arn | CMK ARN encrypting the volume (string), or null unless backup.mode is cross\_account. The re-key procedure for a volume that predates the key consumes it. |
<!-- END_TF_DOCS -->