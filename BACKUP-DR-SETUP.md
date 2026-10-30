# Backup & DR — Setup Walkthrough

Detailed, ordered setup steps for the "Suggested order of execution" in
[BACKUP-DR-IMPLEMENTATION.md](BACKUP-DR-IMPLEMENTATION.md). Each step below
says what's actually done, what's blocked, and the exact commands/decisions
needed next.

All new infra lives in `environment/shr-backup-dr/` — a new shared,
account-level root module, following the same convention as `shr-iam` and
`shr-bootstrap` (own state key, applied manually by an admin, not from CI).
This repo has no `modules/` directory or `module` block usage anywhere else,
so section 7's "fold into a module" is satisfied by building this as one
cohesive root module from the start rather than introducing a new
composition pattern the rest of the repo doesn't use — see step 6 below.

## Step 1 — S3 + KMS (design spec section 6) — done

Created:
- [environment/shr-backup-dr/main.tf](environment/shr-backup-dr/main.tf) — backend (state key `shr-backup-dr/terraform.tfstate`), provider, `local.environment`
- [environment/shr-backup-dr/kms.tf](environment/shr-backup-dr/kms.tf) — customer-managed KMS key (`alias/lighthouse-backup-dr`), rotation enabled, key policy scoped to root + the backup service role
- [environment/shr-backup-dr/s3.tf](environment/shr-backup-dr/s3.tf) — `lighthouse-backup-dr-artifacts-<account-id>` bucket, versioned, SSE-KMS with the key above, public access fully blocked

**To apply** (manual, admin credentials — same as `shr-iam`, not run from CI):
```sh
cd environment/shr-backup-dr
terraform init
terraform plan
terraform apply
```

**Verify after apply:**
- `aws s3api get-bucket-encryption --bucket lighthouse-backup-dr-artifacts-<account-id>` shows `aws:kms` with the new key's ARN
- `aws kms describe-key --key-id alias/lighthouse-backup-dr` shows `KeyState: Enabled` and rotation on
- `aws s3api get-public-access-block --bucket lighthouse-backup-dr-artifacts-<account-id>` shows all four block flags `true`

**Still pending, deferred until Digi's Cryptography Standard doc is linked**
(placeholder in `BACKUP-DR.md` section 6): confirm the 30-day
`deletion_window_in_days`, rotation cadence, and key policy scope match
whatever that standard actually mandates — the values above are reasonable
defaults, not confirmed-compliant ones.

## Step 2 — Golden AMI pipeline (design spec section 2) — blocked

**Blocker:** this repo has no VPC or subnet anywhere (`grep`-confirmed — zero
`aws_vpc`/`aws_subnet` resources in `environment/*`). EC2 Image Builder's
`aws_imagebuilder_infrastructure_configuration` needs a subnet to launch its
build instance in, so this can't be written as real, applyable Terraform
without networking existing first.

**Decisions needed before this can be scaffolded:**
1. Which VPC/subnet should Image Builder build in — a new one dedicated to
   the pipeline, or an existing one? (None exist today.)
2. Source base AMI (e.g. latest Amazon Linux 2023, Ubuntu 22.04/24.04 LTS) —
   whatever Lighthouse instances actually run today.
3. Which hardening/CIS component to start from — AWS publishes managed
   Image Builder components per OS; which one matches your baseline.
4. Instance type/profile for the build stage, and an instance profile role
   with Image Builder's required permissions.

**Once unblocked**, the Terraform shape (for reference, not yet written):
`aws_imagebuilder_image_recipe` → `aws_imagebuilder_infrastructure_configuration`
(subnet, instance profile) → `aws_imagebuilder_distribution_configuration` →
`aws_imagebuilder_image_pipeline`, plus a validation component (boot check +
CIS scan) before the image is marked distributable. This would live in
`environment/shr-backup-dr/imagebuilder.tf` alongside the resources from
step 1, once the above is answered.

## Step 3 — AWS Backup vault/plan/selection (design spec section 1) — done

Created (parallel with step 2, no dependency on it):
- [environment/shr-backup-dr/iam.tf](environment/shr-backup-dr/iam.tf) — `lighthouse-backup-dr-service-role`, assumable by `backup.amazonaws.com`, with the AWS-managed `ForBackup`/`ForRestores` policies attached
- [environment/shr-backup-dr/backup.tf](environment/shr-backup-dr/backup.tf) — `lighthouse-backup-vault` (encrypted with the step-1 KMS key), `lighthouse-daily-ami-snapshot` plan (`cron(0 5 * * ? *)`, 30-day `delete_after`), and a tag-based `aws_backup_selection`

**Design choice, deviating slightly from the implementation doc:** the doc's
example selects by `Environment = cus0001, stg-customer, prd-customer` —
enumerated values. That means editing this module every time a new customer
environment is added, which undercuts the doc's own stated goal ("new
instances are picked up automatically"). Instead, selection here matches a
dedicated `Backup = "true"` tag. **Action for whoever builds the EC2 layer:**
tag every instance that needs daily backup with `Backup = "true"`.

**To apply:** same `terraform apply` as step 1 (same module, same command).

**Validate the selection actually matches something** — this is explicitly
called out in the implementation doc, and it's a real gap right now: this
repo currently provisions **zero EC2 instances** anywhere
(`environment/*-customer` only creates a test S3 bucket + security group).
So today, `terraform apply` will succeed but the backup plan will have
nothing to protect. Once instances exist and are tagged:
```sh
aws backup start-backup-job \
  --backup-vault-name lighthouse-backup-vault \
  --resource-arn <instance-arn> \
  --iam-role-arn <lighthouse-backup-dr-service-role-arn>
```
confirms the role/vault/selection actually work end-to-end before waiting on
the first scheduled run.

## Step 4 — AMI update process + AMI ID propagation (design spec section 3) — blocked on step 2

Per the implementation doc's own dependency note, this depends on the Golden
AMI pipeline existing. Once step 2 is unblocked:
1. Write `GOLDEN-AMI-UPDATE.md`: trigger (manual approval vs. auto on app
   release tag), whether app code is baked into the AMI or deployed
   post-launch, and the test gate (same boot+CIS check as the pipeline's
   validation stage).
2. Add an `aws_ssm_parameter` (e.g. `/lighthouse/golden-ami/latest`) to
   `environment/shr-backup-dr/`, written by the pipeline on a successful,
   validated build — with `lifecycle { ignore_changes = [value] }` so
   Terraform doesn't fight the pipeline's out-of-band writes to it.
3. Each `environment/*-customer` module reads the AMI ID via
   `data "aws_ssm_parameter"` rather than hardcoding it.
4. Decide manual-approval-to-roll-out for prod vs. automatic for dev/stg, and
   wire that decision into whatever CI/CD handles app releases.

## Step 5 — RTO / RPO targets (design spec section 4) — no infra, do now in parallel

This has no Terraform dependency on anything else — do it now, independent
of steps 1–4:
1. Identify who owns Digi's RTO/RPO procedure doc (compliance/security team)
   and get the actual link/doc ID.
2. Ask specifically for the target that applies to: single-region,
   customer-environment-class systems (not just the org-wide default, if
   there's a tiered target).
3. Cross-check: current design is daily snapshots → ~24h max RPO. If the
   real target is tighter, that's a scope change (more frequent snapshots or
   a supplementary mechanism) — flag it back to whoever owns the requirement
   immediately, don't silently absorb it.
4. Record the agreed numbers by replacing the placeholders in
   [BACKUP-DR.md](BACKUP-DR.md#4-rto--rpo-targets) section 4.
5. Get explicit sign-off (email/ticket) that those numbers are accepted for
   Lighthouse specifically — keep that as evidence alongside the doc.

## Step 6 — Fold into a proper module (design spec section 7) — done differently than planned, see note

The implementation doc's suggested order builds sections 1/2/3/6 as
individual pieces first, then refactors into `modules/backup-dr/` once
they're proven out. In practice, since this repo's existing shared/account-
level stacks (`shr-iam`, `shr-bootstrap`) are each already structured as one
cohesive root module rather than a `modules/` + call-site pattern, steps 1
and 3 above were built directly into `environment/shr-backup-dr/` as that
same kind of root module — no separate refactor step needed for what's built
so far. When step 2 (Image Builder) is unblocked, its resources join this
same module rather than a new one.

**Not yet done:** wiring this module into CI. `shr-iam`/`shr-bootstrap` are
deliberately absent from `infrastructure-main.yml`/`infrastructure-pr.yml`'s
matrices (they're admin-applied) — `shr-backup-dr` follows that same
precedent and is intentionally not in either workflow.

## Step 7 — Runbook + drill (design spec section 5) — blocked on step 2

Cannot be meaningfully tested until real EC2/AMI infrastructure exists to
restore against (this is the implementation doc's own stated reason for
running it last). Once unblocked:
1. Write the runbook as an ordered, literal checklist (identify recovery
   point → launch from AMI via `terraform apply -var` override → reattach
   EIP/SG/EBS/Route53 → health-check → rollback criteria).
2. Run one real drill against a non-prod environment, timed.
3. Record start/end timestamps, whether the step-5 RTO target was met, and
   any issues — as a ticket/doc/log, not just "we did it."
4. Fix what the drill surfaces, repeat until clean.
5. Put it on a recurring calendar (quarterly) — one clean drill satisfies the
   initial ask, compliance will expect ongoing evidence.

## Step 8 — Central architecture doc (design spec section 8) — last

1. Get the actual location/format of Digi's central architecture/infra
   reference doc from the team that owns it (Confluence/SharePoint/wiki).
2. Port `BACKUP-DR.md` into it once steps 1–7 are actually implemented and
   stable — not before, so it doesn't document a moving target.
3. Link back to this repo's `BACKUP-DR.md`/`BACKUP-DR-IMPLEMENTATION.md`/
   `GOLDEN-AMI.md` for implementation detail rather than duplicating it.
4. Set a recurring reminder (ticket/calendar) to keep it in sync whenever
   this module changes materially.

## Current status summary

| Step | Section | Status |
|---|---|---|
| 1 | 6 — S3 + KMS | Done — `terraform apply` in `shr-backup-dr` |
| 2 | 2 — Golden AMI | Blocked — no VPC/subnet, needs OS/hardening decisions |
| 3 | 1 — AWS Backup | Done — `terraform apply` in `shr-backup-dr`; nothing to protect yet (no EC2 anywhere) |
| 4 | 3 — AMI update process | Blocked on step 2 |
| 5 | 4 — RTO/RPO | Not started — needs Digi's procedure doc link |
| 6 | 7 — Module structure | Done as-built (see note above); CI wiring intentionally skipped |
| 7 | 5 — Runbook + drill | Blocked on step 2 |
| 8 | 8 — Central doc | Not started — needs doc location + steps 1–7 stable first |
