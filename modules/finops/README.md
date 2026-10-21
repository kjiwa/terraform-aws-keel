# finops

Monthly cost budget with alert notifications and a cost anomaly monitor.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.15 |
| aws | >= 6.45 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_budgets_budget.monthly](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) | resource |
| [aws_ce_anomaly_monitor.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_monitor) | resource |
| [aws_ce_anomaly_subscription.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_subscription) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| alert\_email | Address that receives budget-threshold and cost-anomaly emails (string). Budgets and Cost Explorer deliver directly by email, so there is no SNS subscription to confirm. | `string` | n/a | yes |
| name\_prefix | Prefix for every resource name this module creates (string, lowercase letters, digits and hyphens). | `string` | n/a | yes |
| monthly\_budget\_usd | Monthly cost budget in USD (number). Notifications fire at 80% of actual and 100% of forecasted spend. Size it a little above steady-state so normal months stay quiet but a runaway (a stuck build loop, a forgotten resource) trips it; the default suits a single small instance. | `number` | `15` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| anomaly\_monitor\_arn | Cost anomaly monitor ARN. |
| budget\_name | Monthly cost budget name. |
<!-- END_TF_DOCS -->
