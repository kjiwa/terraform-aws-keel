locals {
  dnssec_domains = { for k, v in var.domains : k => v if v.dnssec }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "dnssec_kms" {
  for_each = local.dnssec_domains

  statement {
    sid     = "AllowRootAdmin"
    actions = ["kms:*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    resources = ["*"]
  }

  statement {
    sid     = "AllowRoute53DnssecService"
    actions = ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign", "kms:Verify"]
    principals {
      type        = "Service"
      identifiers = ["dnssec-route53.amazonaws.com"]
    }
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:route53:::hostedzone/${aws_route53_zone.this[each.key].zone_id}"]
    }
  }

  statement {
    sid     = "AllowRoute53DnssecGrant"
    actions = ["kms:CreateGrant"]
    principals {
      type        = "Service"
      identifiers = ["dnssec-route53.amazonaws.com"]
    }
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

# Route 53 DNSSEC requires the KSK's CMK in us-east-1 regardless of the
# default provider's region.
resource "aws_kms_key" "dnssec" {
  for_each = local.dnssec_domains
  provider = aws.us_east_1

  description              = "Route53 DNSSEC KSK for ${each.key}"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = var.dnssec_key_deletion_window_days
  enable_key_rotation      = false
  policy                   = data.aws_iam_policy_document.dnssec_kms[each.key].json
}

resource "aws_kms_alias" "dnssec" {
  for_each = local.dnssec_domains
  provider = aws.us_east_1

  # Replace dots so the alias is valid (no dots allowed in alias names)
  name          = "alias/route53-dnssec-${replace(each.key, ".", "-")}"
  target_key_id = aws_kms_key.dnssec[each.key].key_id
}

resource "aws_route53_key_signing_key" "this" {
  for_each = local.dnssec_domains

  name                       = replace(each.key, ".", "-")
  hosted_zone_id             = aws_route53_zone.this[each.key].zone_id
  key_management_service_arn = aws_kms_key.dnssec[each.key].arn

  depends_on = [aws_kms_alias.dnssec]
}

resource "aws_route53_hosted_zone_dnssec" "this" {
  for_each = local.dnssec_domains

  hosted_zone_id = aws_route53_zone.this[each.key].zone_id

  depends_on = [aws_route53_key_signing_key.this]
}
