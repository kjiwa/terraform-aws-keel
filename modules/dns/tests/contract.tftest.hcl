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

mock_provider "aws" {
  alias = "us_east_1"
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
  name_prefix = "demo"
  domains = {
    "example.org" = { dnssec = true }
    "example.net" = {}
  }
}

run "zones_per_domain_with_prefixed_names" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  assert {
    condition     = toset(keys(aws_route53_zone.this)) == toset(["example.org", "example.net"])
    error_message = "There must be one zone per domains key."
  }

  assert {
    condition     = aws_route53_zone.this["example.org"].tags["Name"] == "demo-example.org"
    error_message = "Zone Name tags must be <name_prefix>-<domain>."
  }
}

run "dnssec_only_for_flagged_domains" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  assert {
    condition     = toset(keys(aws_kms_key.dnssec)) == toset(["example.org"])
    error_message = "A DNSSEC KMS key must exist only for domains with dnssec = true."
  }

  assert {
    condition     = toset(keys(aws_kms_alias.dnssec)) == toset(["example.org"]) && toset(keys(aws_route53_key_signing_key.this)) == toset(["example.org"]) && toset(keys(aws_route53_hosted_zone_dnssec.this)) == toset(["example.org"]) && toset(keys(data.aws_iam_policy_document.dnssec_kms)) == toset(["example.org"])
    error_message = "The alias, key-signing key, zone DNSSEC and key policy must exist only for flagged domains."
  }

  assert {
    condition     = aws_kms_alias.dnssec["example.org"].name == "alias/route53-dnssec-example-org" && aws_route53_key_signing_key.this["example.org"].name == "example-org"
    error_message = "Dots in the domain must become hyphens in the alias and key-signing key names."
  }
}

run "dnssec_off_by_default" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    domains = {
      "example.org" = {}
    }
  }

  assert {
    condition     = length(aws_kms_key.dnssec) == 0 && length(aws_route53_key_signing_key.this) == 0 && length(aws_route53_hosted_zone_dnssec.this) == 0
    error_message = "Omitting dnssec must create no DNSSEC resources."
  }
}

run "key_deletion_window_default" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  assert {
    condition     = aws_kms_key.dnssec["example.org"].deletion_window_in_days == 30
    error_message = "The DNSSEC key deletion window must default to 30 days."
  }
}

run "key_deletion_window_override" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    dnssec_key_deletion_window_days = 7
  }

  assert {
    condition     = aws_kms_key.dnssec["example.org"].deletion_window_in_days == 7
    error_message = "dnssec_key_deletion_window_days must reach the KMS key."
  }
}

run "records_land_in_their_zone" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    records = {
      mx = {
        zone   = "example.org"
        name   = "example.org"
        type   = "MX"
        ttl    = 3600
        values = ["10 mail.example.com"]
      }
      www = {
        zone   = "example.net"
        name   = "www.example.net"
        type   = "CNAME"
        values = ["example.net"]
      }
    }
  }

  assert {
    condition     = toset(keys(aws_route53_record.this)) == toset(["mx", "www"])
    error_message = "There must be one record per records key."
  }

  assert {
    condition     = aws_route53_record.this["mx"].ttl == 3600 && aws_route53_record.this["www"].ttl == 300
    error_message = "ttl must be honoured and default to 300 seconds."
  }
}

run "no_records_by_default" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  assert {
    condition     = length(aws_route53_record.this) == 0
    error_message = "No records may be created unless records is set."
  }
}

run "rejects_record_in_unknown_zone" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    records = {
      stray = {
        zone   = "example.com"
        name   = "example.com"
        type   = "TXT"
        values = ["\"hello\""]
      }
    }
  }

  expect_failures = [var.records]
}

run "rejects_bad_prefix" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    name_prefix = ""
  }

  expect_failures = [var.name_prefix]
}

run "rejects_bad_deletion_window" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    dnssec_key_deletion_window_days = 3
  }

  expect_failures = [var.dnssec_key_deletion_window_days]
}
