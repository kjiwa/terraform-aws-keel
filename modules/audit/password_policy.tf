# Account-wide IAM password policy. Defense-in-depth control governing password
# strength if IAM users are created.
resource "aws_iam_account_password_policy" "strict" {
  count = var.password_policy_enabled ? 1 : 0

  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}

moved {
  from = aws_iam_account_password_policy.strict
  to   = aws_iam_account_password_policy.strict[0]
}
