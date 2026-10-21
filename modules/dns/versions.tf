terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.45"
      # Route 53 DNSSEC requires the KSK's KMS key in us-east-1 regardless of
      # where the default provider points; only dnssec.tf uses this alias.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
