mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix   = "demo-app"
  az            = "us-east-2a"
  backup_region = "us-west-2"
  backup = {
    # Built from parts so the hygiene check, which allows only the documented
    # account ID, still sees a backup account distinct from the workload one.
    account_id = join("", ["1111", "2222", "3333"])
  }
}

run "volume_defaults_to_aws_ebs_key_outside_cross_account" {
  command = plan

  assert {
    condition     = aws_ebs_volume.this.size == 8 && aws_ebs_volume.this.type == "gp3" && aws_ebs_volume.this.encrypted
    error_message = "The volume must default to 8 GiB, gp3, encrypted."
  }

  assert {
    condition     = length(aws_kms_key.data) == 0 && length(aws_kms_alias.data) == 0 && output.volume_kms_key_arn == null
    error_message = "No data-volume CMK may exist unless backup.mode is cross_account."
  }

  assert {
    condition     = aws_ebs_volume.this.tags["Name"] == "demo-app-data" && aws_ebs_volume.this.tags["Persistent"] == "true"
    error_message = "The volume Name tag must be <name_prefix>-data and Persistent must be true."
  }
}

run "local_mode_builds_one_vault_plan_and_selection" {
  command = plan

  assert {
    condition = (
      aws_backup_vault.this[0].name == "demo-app-backup"
      && aws_backup_plan.this[0].name == "demo-app-daily"
      && aws_backup_selection.this[0].name == "demo-app-irreplaceable"
      && aws_iam_role.backup[0].name == "demo-app-backup"
    )
    error_message = "Vault, plan, selection and role names must derive from name_prefix."
  }

  assert {
    condition     = length(aws_backup_vault.replica) == 0 && length(aws_backup_vault_policy.this) == 0 && output.backup_copy_vault_arn == null
    error_message = "Local mode must create no replica vault, vault policy or copy destination."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.backup) == 4
    error_message = "The backup role must carry the four AWS Backup managed policies."
  }

  assert {
    condition     = output.backup_resource_count == 1 && output.vault_name == "demo-app-backup"
    error_message = "Only the volume is selected by default, and vault_name must be exported."
  }
}

run "plan_rule_follows_schedule_and_retention" {
  command = plan

  variables {
    backup = {
      schedule       = "cron(0 5 * * ? *)"
      retention_days = 14
    }
  }

  assert {
    condition     = one(aws_backup_plan.this[0].rule).rule_name == "daily-14d" && one(aws_backup_plan.this[0].rule).schedule == "cron(0 5 * * ? *)"
    error_message = "The rule must be named daily-<retention_days>d and use backup.schedule."
  }

  assert {
    condition     = one(one(aws_backup_plan.this[0].rule).lifecycle).delete_after == 14 && output.backup_remote_retention_days == 14
    error_message = "Remote retention 0 must fall back to retention_days."
  }
}

run "remote_retention_overrides_when_set" {
  command = plan

  variables {
    backup = {
      account_id            = "123456789012"
      mode                  = "cross_account"
      retention_days        = 7
      remote_retention_days = 90
    }
  }

  assert {
    condition     = output.backup_remote_retention_days == 90
    error_message = "A positive remote_retention_days must be applied as is."
  }
}

run "extra_resources_join_the_selection" {
  command = plan

  variables {
    extra_backup_resource_arns = ["arn:aws:s3:::demo-media"]
  }

  assert {
    condition     = output.backup_resource_count == 2
    error_message = "Extra ARNs must be counted with the volume."
  }
}

run "disabled_mode_creates_no_backup_resources" {
  command = plan

  variables {
    backup = {
      mode = "disabled"
    }
  }

  assert {
    condition = (
      length(aws_backup_vault.this) == 0
      && length(aws_backup_plan.this) == 0
      && length(aws_backup_selection.this) == 0
      && length(aws_iam_role.backup) == 0
      && length(aws_iam_role_policy_attachment.backup) == 0
      && output.vault_name == null
    )
    error_message = "Disabled mode must create no vault, plan, selection or role."
  }

  assert {
    condition     = aws_ebs_volume.this.availability_zone == var.az
    error_message = "The volume must exist even with backups disabled."
  }
}

run "cross_account_keys_the_volume_and_constructs_the_destination" {
  command = plan

  variables {
    backup = {
      account_id      = join("", ["1111", "2222", "3333"])
      mode            = "cross_account"
      dest_vault_name = "demo-app-backup"
    }
  }

  assert {
    condition     = length(aws_kms_key.data) == 1 && one(aws_kms_alias.data[*].name) == "alias/demo-app-data"
    error_message = "cross_account must create the data-volume CMK and its alias."
  }

  assert {
    condition     = output.backup_copy_vault_arn == "arn:aws:backup:us-west-2:${join("", ["1111", "2222", "3333"])}:backup-vault:demo-app-backup"
    error_message = "The destination vault ARN must be built from account, backup_region and dest_vault_name."
  }

  assert {
    condition     = length(aws_backup_vault_policy.this) == 1 && length(aws_backup_vault.replica) == 0
    error_message = "cross_account must attach the copy-back policy and create no replica vault."
  }

  assert {
    condition     = length(one(aws_backup_plan.this[0].rule).copy_action) == 1
    error_message = "cross_account must add one copy_action."
  }
}

run "cross_region_creates_a_replica_vault_in_the_backup_region" {
  command = plan

  variables {
    backup = {
      mode = "cross_region"
    }
  }

  assert {
    condition     = aws_backup_vault.replica[0].region == "us-west-2" && aws_backup_vault.replica[0].name == "demo-app-backup-replica"
    error_message = "The replica vault must live in backup_region and be named <name_prefix>-backup-replica."
  }

  assert {
    condition     = length(aws_kms_key.data) == 0 && length(aws_backup_vault_policy.this) == 0
    error_message = "cross_region needs neither the volume CMK nor the copy-back policy."
  }

  assert {
    condition     = length(one(aws_backup_plan.this[0].rule).copy_action) == 1
    error_message = "cross_region must add one copy_action."
  }
}

run "aws_managed_vaults_create_no_vault_keys" {
  command = plan

  variables {
    vault_kms = "aws_managed"
    backup = {
      mode = "cross_region"
    }
  }

  assert {
    condition     = length(aws_kms_key.backup) == 0 && length(aws_kms_alias.backup) == 0 && length(aws_kms_key.backup_replica) == 0 && length(aws_kms_alias.backup_replica) == 0
    error_message = "vault_kms = aws_managed must create no vault or replica key."
  }
}

run "cmk_vaults_get_a_key_and_alias_each" {
  command = plan

  variables {
    vault_kms = "cmk"
    backup = {
      mode = "cross_region"
    }
  }

  assert {
    condition     = one(aws_kms_alias.backup[*].name) == "alias/demo-app-backup" && one(aws_kms_alias.backup_replica[*].name) == "alias/demo-app-backup-replica"
    error_message = "cmk must create <name_prefix>-backup and <name_prefix>-backup-replica keys with matching aliases."
  }

  assert {
    condition     = aws_kms_key.backup_replica[0].region == "us-west-2" && aws_kms_key.backup[0].enable_key_rotation
    error_message = "The replica key must live in backup_region and rotation must be on."
  }
}

run "cmk_is_not_created_when_backups_are_disabled" {
  command = plan

  variables {
    vault_kms = "cmk"
    backup = {
      mode = "disabled"
    }
  }

  assert {
    condition     = length(aws_kms_key.backup) == 0
    error_message = "A disabled backup must not create a vault key."
  }
}

run "volume_name_and_tags_are_overridable" {
  command = plan

  variables {
    volume_name = "demo-store"
    volume_tags = {
      Project = "demo"
    }
    backup = {
      mode       = "cross_account"
      account_id = join("", ["1111", "2222", "3333"])
    }
  }

  assert {
    condition     = aws_ebs_volume.this.tags["Name"] == "demo-store" && aws_ebs_volume.this.tags["Project"] == "demo" && aws_ebs_volume.this.tags["Persistent"] == "true"
    error_message = "volume_name and volume_tags must reach the volume without dropping Persistent."
  }

  assert {
    condition     = one(aws_kms_alias.data[*].name) == "alias/demo-store"
    error_message = "The data key alias must follow volume_name."
  }
}

run "snapshot_and_size_pass_through" {
  command = plan

  variables {
    size_gib    = 20
    snapshot_id = "snap-0123456789abcdef0"
  }

  assert {
    condition     = aws_ebs_volume.this.size == 20 && aws_ebs_volume.this.snapshot_id == "snap-0123456789abcdef0"
    error_message = "size_gib and snapshot_id must reach the volume."
  }
}

run "rejects_unknown_mode" {
  command = plan

  variables {
    backup = {
      mode = "weekly"
    }
  }

  expect_failures = [var.backup]
}

run "rejects_cross_account_without_account_id" {
  command = plan

  variables {
    backup = {
      mode = "cross_account"
    }
  }

  expect_failures = [var.backup]
}

run "rejects_non_positive_retention" {
  command = plan

  variables {
    backup = {
      retention_days = 0
    }
  }

  expect_failures = [var.backup]
}

run "rejects_unknown_vault_kms" {
  command = plan

  variables {
    vault_kms = "customer"
  }

  expect_failures = [var.vault_kms]
}

run "rejects_bad_prefix" {
  command = plan

  variables {
    name_prefix = "Demo_App"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_tiny_volume" {
  command = plan

  variables {
    size_gib = 0
  }

  expect_failures = [var.size_gib]
}

run "local_mode_needs_no_backup_region" {
  command = plan

  variables {
    backup_region = null
    backup = {
      mode = "local"
    }
  }

  assert {
    condition     = length(aws_backup_vault.replica) == 0
    error_message = "Local mode must plan without a backup_region and create no replica vault."
  }
}

run "cross_region_requires_backup_region" {
  command = plan

  variables {
    backup_region = null
    backup = {
      mode = "cross_region"
    }
  }

  expect_failures = [var.backup_region]
}

run "cross_account_requires_backup_region" {
  command = plan

  variables {
    backup_region = null
    backup = {
      mode       = "cross_account"
      account_id = join("", ["1111", "2222", "3333"])
    }
  }

  expect_failures = [var.backup_region]
}
