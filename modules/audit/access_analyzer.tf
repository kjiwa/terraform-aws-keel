# Flags any resource policy that grants access outside the account.
resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "${var.name_prefix}-account"
  type          = "ACCOUNT"

  tags = {
    Name = "${var.name_prefix}-account"
  }
}

# Archives the expected external access of the backup account: permanent read
# access to a KMS key, and the transient share of each snapshot during a
# cross-account copy. Scoped to that principal, so any other account still fires.
resource "aws_accessanalyzer_archive_rule" "backup_account_cmk" {
  count         = var.backup_account_id != "" ? 1 : 0
  analyzer_name = aws_accessanalyzer_analyzer.account.analyzer_name
  rule_name     = "expected-backup-account-access"

  filter {
    criteria = "principal.AWS"
    eq       = [var.backup_account_id]
  }

  filter {
    criteria = "resourceType"
    eq       = ["AWS::KMS::Key", "AWS::EC2::Snapshot"]
  }
}
