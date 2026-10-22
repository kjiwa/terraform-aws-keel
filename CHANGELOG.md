# Changelog

## v0.1.1

### Changed

- audit: the `iam-policy-change` metric filter now requires `eventSource = iam.amazonaws.com` and matches an explicit list of event names instead of `Put*Policy`-style wildcards. Existing consumers get a changed filter pattern on apply. The list adds `UpdateAssumeRolePolicy` and the permissions-boundary and policy-version events, and no longer matches unrelated events in other services.
- audit: the CloudTrail-to-CloudWatch Logs role trust is conditioned on `aws:SourceAccount` and `aws:SourceArn` (the trail).
- audit: the Access Analyzer notification no longer includes the `Actions` field; the array-valued `$.detail.action` path does not render in an input template.
- backup-vault-account: the restore role trust is conditioned on `aws:SourceAccount` (this account).
- state-bucket: resources are renamed from `tfstate_web` to `this`. `moved` blocks ship in the module; a consumer plan shows state moves only.

### Removed

- audit: the `moved` blocks that mapped `aws_kms_key.audit` and `aws_kms_alias.audit` to index `[0]`. v0.1.0 already uses the indexed addresses.

### Fixed

- scripts/hygiene.sh also rejects the names of consuming projects.
