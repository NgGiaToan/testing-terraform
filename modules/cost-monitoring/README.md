# cost-monitoring

One monthly budget and one cost anomaly monitor per customer, kept in the management account next to the alert
topics (like the quota alarms). Called from `environment/shr-monitoring` (`cost_customers`), applied by an admin: the
customer environments and the CI role need no billing permission.

| Resource | Meaning |
| --- | --- |
| `aws_budgets_budget.customer` | `<environment>-<customer>-monthly-budget`, filtered on the `Instance` tag (`cost_tag_key`) = the customer's `instance`. 80% actual (`warning_percent`) and a forecast over 100% alert **P3**; 100% actual (`critical_percent`) alerts **P2** |
| `aws_ce_anomaly_monitor.customer` | A custom monitor on the same tag |
| `aws_ce_anomaly_subscription.customer` | Sends an anomaly of at least `anomaly_threshold_usd` (default `default_anomaly_threshold_usd`) to **P3**, immediately |

The alerts go through the alert topics and the alert delivery Lambda to the Operations Slack channel. For that the topics
have to allow AWS Budgets and Cost Anomaly Detection: `alert-delivery` always does it (topic policy and key policy), for this
account only. There is no switch: cost monitoring is on, and creating budgets only needs `cost_customers` in `shr-monitoring`.

## Before it shows anything

- Every resource of a customer carries the `Instance` tag, and the value is the customer's `instance`. `CostCenter` is
  not unique per customer, so the budgets do not use it.
- The tag is **active** in Billing > Cost Allocation Tags (in the payer account). Otherwise a budget reads zero spend and
  never alerts, with no error. A tag counts only from the day it is activated.
- `instance` is unique per customer (the module checks it).

## Limits

- Budgets are account-wide and named with the environment: fill `customers` in **one** deployment per environment, not
  in each region, or the apply fails on duplicate names.
- Costs that cannot carry a tag (some services, shared charges) belong to no customer.
- Not verified: that Budgets can publish to a topic in the region of the deployment, the exact text of the alerts, the key
  policy statement for Budgets (see `alert-delivery/kms.tf`), `match_options = GREATER_THAN_OR_EQUAL` of the anomaly
  threshold (the provider page lists other values, the AWS API accepts this one: check with `terraform plan`), and the per-account limits and
  price of budgets and monitors when the number of customers grows.
- `terraform validate` was not run (the AWS provider plugin does not respond where this was written).
