# terraform-aws-keel

Shared Terraform modules and scripts for single-instance AWS apps: audit, finops, DNS, state, and backup governance.

## Modules

| Module | Purpose |
| --- | --- |
| [`modules/audit`](modules/audit) | CloudTrail in an Object-Locked bucket, optional KMS, Access Analyzer, S3 access logging, tamper alarms, password policy. |
| [`modules/finops`](modules/finops) | Monthly cost budget with alerts and a cost anomaly monitor. |
| [`modules/dns`](modules/dns) | Route 53 hosted zones, optional DNSSEC per domain, extra records. |

Further modules (state bucket, backup vault account) are not released yet.

## Usage

Pin every module to a release tag with a literal `ref`:

```hcl
module "dns" {
  source = "github.com/kjiwa/terraform-aws-keel//modules/dns?ref=v0.1.0"

  name_prefix = "example"
  domains     = { "example.com" = { dnssec = true } }

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
```

A literal ref lets Dependabot propose bumps. Each module README lists its inputs, outputs, and required providers.

## Versioning

Releases follow semantic versioning. Before 1.0, a minor release may change inputs or resource addresses; the release notes list the `moved` blocks a consumer needs.

## Testing

```sh
terraform -chdir=modules/finops init -backend=false
terraform -chdir=modules/finops test
sh scripts/tests/run.sh
pre-commit run --all-files
```

The module tests use mocked providers and need no AWS credentials. `scripts/docs.sh` regenerates the module READMEs between their terraform-docs markers.
