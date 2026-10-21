# dns

Route 53 hosted zones with optional per-domain DNSSEC and extra records. Needs an `aws.us_east_1` provider alias for the DNSSEC KMS keys.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.15 |
| aws | >= 6.45 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_kms_alias.dnssec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.dnssec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_route53_hosted_zone_dnssec.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_hosted_zone_dnssec) | resource |
| [aws_route53_key_signing_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_key_signing_key) | resource |
| [aws_route53_record.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.dnssec_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| domains | Apex domains to create hosted zones for (map of domain name to object). dnssec enables DNSSEC signing (KMS KSK + DS record) for that zone. A single-domain consumer passes one entry and reads zone\_ids[<domain>]. | ```map(object({ dnssec = optional(bool, false) }))``` | n/a | yes |
| name\_prefix | Prefix for the Name tag on every hosted zone (string, lowercase letters, digits and hyphens). | `string` | n/a | yes |
| dnssec\_key\_deletion\_window\_days | Days a DNSSEC KMS key stays pending after deletion is scheduled (number, 7 to 30). | `number` | `30` | no |
| records | Extra records to create verbatim, such as ones carried over from a previous registrar (map of stable name to object). zone is a key of domains; ttl is in seconds; name is passed to Route 53 unchanged. | ```map(object({ zone = string name = string type = string ttl = optional(number, 300) values = list(string) }))``` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| ds\_records | Map of domain name to DS record string (paste into registrar). Only present for DNSSEC-enabled domains. |
| ns\_records | Map of domain name to list of NS record values. Update registrar for all domains. |
| zone\_ids | Map of domain name to Route53 zone ID. |
<!-- END_TF_DOCS -->
