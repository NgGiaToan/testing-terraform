# synthetics-canaries

Deploys the two CloudWatch Synthetics canaries `modules/customer-monitoring` alarms on but
doesn't create itself: an HTTPS availability check (`canary_src/https_availability`) and a
workflow canary (`canary_src/workflow`). Apply once per customer, alongside
`modules/customer-monitoring`.

## Usage

```hcl
module "canaries" {
  source = "../../modules/synthetics-canaries"

  customer_code = "cus001"
  environment   = "prod-cus001"
  target_url    = "https://cus001.lighthouse.example.com"
  tags          = local.common_tags
}

module "monitoring" {
  source = "../../modules/customer-monitoring"
  # ...
  https_availability_canary_name = module.canaries.https_availability_canary_name
  synthetics_canary_name         = module.canaries.workflow_canary_name
}
```

## Before you rely on it

- **`canary_src/workflow/nodejs/node_modules/workflow.js` is a placeholder.** It only
  confirms the homepage loads and has a non-empty title — replace the `TODO` step with the
  customer's actual critical workflow (login, create a record, run a search, whatever best
  represents "the product works").
- **`runtime_version` defaults to `syn-nodejs-puppeteer-9.0`** — AWS deprecates Synthetics
  runtimes on a schedule; confirm the current one with
  `aws synthetics describe-runtime-versions` before relying on the default.
- Both canaries execute as Lambda functions under the hood, under one shared IAM role
  (`<environment>-canaries-execution`) scoped to this module's own S3 artifact bucket and
  the `CloudWatchSynthetics` metrics namespace only.
