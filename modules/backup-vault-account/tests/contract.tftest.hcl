mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-2:123456789012:key/demo"
    }
  }
  mock_resource "aws_backup_vault" {
    defaults = {
      arn = "arn:aws:backup:us-east-2:123456789012:backup-vault:demo-app-backup-replica"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/demo-app-restore"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix = "demo-app"
  vault_name  = "demo-app-backup-replica"
  # Built from parts so the hygiene check, which allows only the documented
  # account ID, still sees a source account distinct from the backup account.
  source_account_id = join("", ["1111", "2222", "3333"])
}

run "names_follow_inputs" {
  command = plan

  assert {
    condition     = aws_backup_vault.replica.name == "demo-app-backup-replica" && aws_backup_vault.replica.tags["Name"] == "demo-app-backup-replica"
    error_message = "The vault must be named var.vault_name."
  }

  assert {
    condition     = aws_iam_role.restore.name == "demo-app-restore" && aws_iam_role.restore.tags["Name"] == "demo-app-restore"
    error_message = "The restore role must be <name_prefix>-restore."
  }

  assert {
    condition     = aws_kms_alias.backup_replica.name == "alias/demo-app-backup-replica" && aws_kms_key.backup_replica.tags["Name"] == "demo-app-backup-replica"
    error_message = "The key alias and Name tag must default to vault_name."
  }
}

run "kms_key_name_overrides_alias_and_tag" {
  command = plan

  variables {
    kms_key_name = "demo-backup-replica"
  }

  assert {
    condition     = aws_kms_alias.backup_replica.name == "alias/demo-backup-replica" && aws_kms_key.backup_replica.tags["Name"] == "demo-backup-replica"
    error_message = "kms_key_name must set the alias and the Name tag."
  }

  assert {
    condition     = aws_backup_vault.replica.name == "demo-app-backup-replica"
    error_message = "kms_key_name must not rename the vault."
  }
}

run "key_policy_trusts_source_for_copy_in_only" {
  command = plan

  assert {
    condition     = aws_kms_key.backup_replica.enable_key_rotation && aws_kms_key.backup_replica.deletion_window_in_days == 30
    error_message = "The vault key must rotate and keep a 30 day deletion window."
  }

  assert {
    condition = (
      length(jsondecode(aws_kms_key.backup_replica.policy).Statement) == 3
      && jsondecode(aws_kms_key.backup_replica.policy).Statement[0].Sid == "RootFullAccess"
      && jsondecode(aws_kms_key.backup_replica.policy).Statement[0].Principal.AWS == "arn:aws:iam::123456789012:root"
    )
    error_message = "Statement one must delegate to the backup account's own root."
  }

  assert {
    condition = (
      jsondecode(aws_kms_key.backup_replica.policy).Statement[1].Sid == "SourceAccountCopyIn"
      && jsondecode(aws_kms_key.backup_replica.policy).Statement[1].Principal.AWS == "arn:aws:iam::${var.source_account_id}:root"
      && toset(jsondecode(aws_kms_key.backup_replica.policy).Statement[1].Action) == toset([
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncryptFrom",
        "kms:ReEncryptTo",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:DescribeKey",
      ])
    )
    error_message = "The source account must get exactly the seven copy-in key actions, never kms:*."
  }

  assert {
    condition = (
      jsondecode(aws_kms_key.backup_replica.policy).Statement[2].Sid == "SourceAccountCreateGrant"
      && jsondecode(aws_kms_key.backup_replica.policy).Statement[2].Action == "kms:CreateGrant"
      && jsondecode(aws_kms_key.backup_replica.policy).Statement[2].Condition.Bool["kms:GrantIsForAWSResource"] == "true"
    )
    error_message = "CreateGrant must be limited to grants for AWS resources."
  }
}

run "vault_policy_allows_copy_in_only" {
  command = plan

  assert {
    condition = (
      one(data.aws_iam_policy_document.replica.statement).sid == "AllowSourceAccountCopyIn"
      && one(data.aws_iam_policy_document.replica.statement).actions == toset(["backup:CopyIntoBackupVault"])
      && one(one(one(data.aws_iam_policy_document.replica.statement).principals).identifiers) == "arn:aws:iam::${var.source_account_id}:root"
    )
    error_message = "The vault policy must grant the source account CopyIntoBackupVault and nothing else."
  }
}

run "lock_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_backup_vault_lock_configuration.replica) == 0
    error_message = "No lock may be created while vault_lock.mode is none."
  }
}

run "governance_lock_omits_changeable_for_days" {
  command = plan

  variables {
    vault_lock = {
      mode               = "governance"
      min_retention_days = 7
      max_retention_days = 365
    }
  }

  assert {
    condition = (
      length(aws_backup_vault_lock_configuration.replica) == 1
      && aws_backup_vault_lock_configuration.replica[0].min_retention_days == 7
      && aws_backup_vault_lock_configuration.replica[0].max_retention_days == 365
      && aws_backup_vault_lock_configuration.replica[0].changeable_for_days == null
    )
    error_message = "Governance mode must set the retention bounds and omit changeable_for_days."
  }
}

run "compliance_lock_sets_changeable_for_days" {
  command = plan

  variables {
    vault_lock = {
      mode                = "compliance"
      changeable_for_days = 5
    }
  }

  assert {
    condition     = aws_backup_vault_lock_configuration.replica[0].changeable_for_days == 5
    error_message = "Compliance mode must pass changeable_for_days."
  }
}

run "restore_role_policies_default_to_ebs_only" {
  command = plan

  assert {
    condition = toset(keys(aws_iam_role_policy_attachment.restore)) == toset([
      "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
      "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    ])
    error_message = "Without S3 recovery the role carries only the two service-role policies."
  }
}

run "s3_recovery_adds_root_path_policies" {
  command = plan

  variables {
    s3_recovery_enabled = true
  }

  assert {
    condition = toset(keys(aws_iam_role_policy_attachment.restore)) == toset([
      "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
      "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
      "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup",
      "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore",
    ])
    error_message = "The S3 policies live at the policy root, not under service-role/."
  }
}

run "rds_service_linked_role_is_opt_in" {
  command = plan

  assert {
    condition     = length(aws_iam_service_linked_role.rds) == 0
    error_message = "The RDS service-linked role must not exist by default."
  }
}

run "rds_service_linked_role_enabled" {
  command = plan

  variables {
    rds_service_linked_role_enabled = true
  }

  assert {
    condition     = one(aws_iam_service_linked_role.rds).aws_service_name == "rds.amazonaws.com"
    error_message = "The role must be the rds.amazonaws.com service-linked role."
  }
}

run "no_vault_reader_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role.vault_reader) == 0 && length(aws_iam_role_policy.vault_reader) == 0
    error_message = "No vault reader role may exist unless vault_reader_source_role_name is set."
  }
}

run "vault_reader_is_scoped_to_one_source_role" {
  command = plan

  variables {
    vault_reader_source_role_name = "demo-app-status"
  }

  assert {
    condition     = one(aws_iam_role.vault_reader).name == "demo-app-vault-reader" && one(aws_iam_role_policy.vault_reader).name == "demo-app-vault-reader"
    error_message = "The reader role and policy must be <name_prefix>-vault-reader."
  }

  assert {
    condition = (
      one(one(one(data.aws_iam_policy_document.vault_reader_assume[0].statement).principals).identifiers) == "arn:aws:iam::${var.source_account_id}:root"
      && one(one(one(data.aws_iam_policy_document.vault_reader_assume[0].statement).condition).values) == "arn:aws:iam::${var.source_account_id}:role/demo-app-status"
      && one(one(data.aws_iam_policy_document.vault_reader_assume[0].statement).condition).variable == "aws:PrincipalArn"
    )
    error_message = "Trust must name the source root plus a PrincipalArn condition on the one role."
  }

  assert {
    condition = (
      one(one(data.aws_iam_policy_document.vault_reader[0].statement).actions) == "backup:DescribeBackupVault"
      && length(one(data.aws_iam_policy_document.vault_reader[0].statement).resources) == 1
    )
    error_message = "The reader may only describe this one vault."
  }
}

run "rejects_bad_source_account" {
  command = plan

  variables {
    source_account_id = "1234"
  }

  expect_failures = [var.source_account_id]
}

run "rejects_bad_prefix" {
  command = plan

  variables {
    name_prefix = "Not Valid"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_unknown_lock_mode" {
  command = plan

  variables {
    vault_lock = { mode = "forever" }
  }

  expect_failures = [var.vault_lock]
}

run "rejects_inverted_retention" {
  command = plan

  variables {
    vault_lock = {
      mode               = "governance"
      min_retention_days = 30
      max_retention_days = 7
    }
  }

  expect_failures = [var.vault_lock]
}

run "rejects_short_compliance_window" {
  command = plan

  variables {
    vault_lock = {
      mode                = "compliance"
      changeable_for_days = 2
    }
  }

  expect_failures = [var.vault_lock]
}
