# Backup & DR — Implementation Steps

Companion to [BACKUP-DR.md](BACKUP-DR.md). Each section below is the
concrete, ordered work for that requirement.

## 1. Automated AMI Snapshots per Customer Environment

- Decide DLM vs AWS Backup. Default recommendation: **AWS Backup** — it also
  covers the restore-testing requirement (#5) natively, whereas plain DLM
  does not.
- In Terraform, create an `aws_backup_vault` (one per environment, or one
  shared vault with tag-based selection — pick shared unless compliance
  requires isolation).
- Create an `aws_backup_plan` with a daily rule:
  - Schedule: `cron(0 5 * * ? *)` (pick a low-traffic hour).
  - `lifecycle { delete_after = 30 }` — satisfies the 30-day retention.
- Create an `aws_backup_selection` that targets resources by tag (e.g.
  `Environment = cus0001, stg-customer, prd-customer`) rather than listing
  instance IDs — so new instances are picked up automatically.
- Create the IAM role AWS Backup assumes (`aws_iam_role` + attach
  `AWSBackupServiceRolePolicyForBackup` / `...ForRestores`).
- Apply, then manually trigger one on-demand backup job to confirm the
  selection tags are actually matching instances before waiting for the first
  scheduled run.
- Add `aws_backup_vault_lock_configuration` if compliance wants immutability
  (optional, ask before enabling — it's hard to undo).

## 2. Golden AMI

- Pick the tool: **EC2 Image Builder** if you want AWS-native
  scheduling/pipelines and Terraform-manageable resources; **Packer** if the
  team already has Packer templates elsewhere or wants more portability.
  Default to Image Builder for tighter Terraform integration.
- Define the base: which source AMI (e.g. latest Amazon Linux 2023 / Ubuntu
  LTS) you're building from.
- Write the component document(s) — the list of build steps: OS patching,
  required agents (monitoring, backup agent, etc.), CIS hardening steps.
  Start from AWS's published CIS-hardening managed components if available
  for your OS, then layer custom components for anything Lighthouse-specific.
- In Terraform: `aws_imagebuilder_image_recipe` (base image + components),
  `aws_imagebuilder_infrastructure_configuration` (instance type/role/subnet
  for the build), `aws_imagebuilder_distribution_configuration` (which
  regions/accounts get the resulting AMI), `aws_imagebuilder_image_pipeline`
  tying them together.
- Add a test/validation stage in the recipe: boot check + CIS benchmark scan
  (e.g. via a component running inspec/openscap or AWS Inspector) before the
  pipeline marks the image as distributable.
- Run the pipeline once manually, confirm the resulting AMI boots and passes
  checks.
- Document the image: create a short `GOLDEN-AMI.md` recording what's baked
  in, build date, source AMI, and the pipeline that produced it. Tag the AMI
  itself with build date + version.

## 3. Golden AMI Update Process on New App Release

- Write the procedure doc (`GOLDEN-AMI-UPDATE.md`) answering:
  - **Trigger:** who/what kicks off a rebuild (manual approval vs. automatic
    on app release tag).
  - **What's baked in:** does app code/version go into the AMI, or does the
    AMI stay app-agnostic and app deploys happen post-launch? (This
    determines whether the pipeline needs to run per release or only per
    OS/agent update.)
  - **Test gate:** same validation as step 2's boot check + CIS scan, run
    again before promoting.
- Store the resulting AMI ID somewhere Terraform reads dynamically, not
  hardcoded:
  - **Option A:** SSM Parameter Store — pipeline writes the new AMI ID to a
    parameter (e.g. `/lighthouse/golden-ami/latest`) on successful build;
    environments read it via `data "aws_ssm_parameter"`.
  - **Option B:** `data "aws_ami" "golden" { most_recent = true; filter {
    name = "tag:Role"; values = ["lighthouse-golden"] } }` — no SSM needed,
    just tag discipline.
- Decide the rollout mechanism: does updating the parameter auto-trigger a
  `terraform apply`/instance refresh, or is it a manual, reviewed step?
  Recommend manual/reviewed for prod, automatic is fine for dev/staging.
- Add this trigger point to whatever CI/CD pipeline handles app releases —
  even if it's just a checklist step or a manual approval gate initially.

## 4. RTO / RPO Targets

- Get the actual link/document ID for Digi's RTO/RPO procedure from whoever
  owns that doc (compliance/security team likely).
- Pull the target values that apply to this class of system (customer
  environments, single-region).
- Cross-check the RPO against your actual snapshot frequency — daily
  snapshots = ~24h max RPO. If the target RPO is tighter than 24h, you'll
  need more frequent snapshots or a supplementary mechanism (e.g. DB-level
  continuous backup) — flag this early since it changes scope.
- Record the agreed numbers in `BACKUP-DR.md` section 4, replacing the
  placeholder.
- Get sign-off from whoever owns the compliance requirement that these
  numbers are acceptable for Lighthouse.

## 5. Recovery Procedure — Documented and Tested

- Write the runbook as an ordered checklist, specific enough that someone
  unfamiliar with the system could follow it:
  1. Identify the correct AMI/recovery point for the affected environment.
  2. Launch a new instance from that AMI (specify instance type, subnet,
     security group — ideally reference the Terraform module so this is
     "apply with a variable override" rather than manual console work).
  3. Reattach/restore networking (EIP, security groups), storage (any
     separate EBS volumes/snapshots), and DNS (Route53 record repoint).
  4. Health-check steps to confirm the instance is actually serving traffic
     correctly.
  5. Rollback/abort criteria if the restore doesn't come up clean.
- Schedule an actual DR drill: pick a non-prod environment first, restore it
  end-to-end, time it.
- Record the drill: what was restored, start/end timestamps, whether it met
  the RTO target, any issues hit. Save as a ticket, doc, or log — this is
  your "tested" evidence.
- Fix anything the drill surfaced (missing IAM permission, DNS TTL too long,
  etc.), then repeat until it passes cleanly.
- Put the drill on a recurring cadence (e.g. quarterly) — a one-time test
  satisfies the initial requirement but compliance will likely expect ongoing
  evidence.

## 6. S3 Buckets Encrypted at Rest

- Identify every bucket in scope (exported backups, Image Builder
  logs/artifacts, any DR-related logs).
- For each: `aws_s3_bucket_server_side_encryption_configuration` with
  `sse_algorithm = "aws:kms"` and a customer-managed `aws_kms_key` (not the
  default AWS-managed key — check Digi's Cryptography Standard, it likely
  requires customer-managed).
- Set key rotation: `aws_kms_key { enable_key_rotation = true }`.
- Lock down the key policy to only the roles that need it (backup role,
  Image Builder role, anyone auditing) — least privilege, per whatever the
  Cryptography Standard specifies.
- Add `aws_s3_bucket_public_access_block` on each bucket regardless
  (belt-and-suspenders, likely already a baseline elsewhere in the repo).
- Once you have the actual Cryptography Standard doc, double check rotation
  period and key policy pattern match what's mandated exactly — don't assume
  the Terraform defaults above are sufficient without checking.

## 7. All Backup and DR Configuration as IaC

- Create a new module, e.g. `modules/backup-dr/`, containing everything from
  sections 1, 2, 6 (AWS Backup vault/plan/selection, Image Builder pipeline,
  S3 + KMS, IAM roles).
- Wire it into each `environment/*` the same way other shared modules are
  consumed in this repo (check the existing pattern — likely a module block
  per environment with environment-specific variables like tags/name).
- Run `terraform plan` against a non-prod environment first, review the diff
  carefully (IAM role creation especially), then apply.
- Add this module to whatever CI checks run on other modules in the repo
  (lint/plan-on-PR, etc.) so it's held to the same review bar.

## 8. Documented in the Architecture/Infrastructure Reference Doc

- Get the location/format of the org's central architecture doc
  (Confluence/SharePoint/wiki — whatever the team already uses).
- Port the content of `BACKUP-DR.md` into that doc once it's finalized (not
  before — finish steps 1–7 first so you're not documenting a moving target).
- Link back to this repo's `BACKUP-DR.md`/`GOLDEN-AMI.md` for implementation
  detail, so the central doc stays a summary/reference rather than
  duplicating everything.
- Add a review reminder (calendar or ticket) to keep the central doc in sync
  whenever the Terraform module changes materially.

## Suggested order of execution

Doing these roughly in this order avoids rework:

1. **Section 6** (S3 + KMS) — small, self-contained, other pieces depend on
   having a bucket.
2. **Section 2** (Golden AMI pipeline) — needed before anything references a
   "golden" AMI.
3. **Section 1** (AWS Backup vault/plan/selection) — can run in parallel with
   #2.
4. **Section 3** (update process + AMI ID propagation) — depends on #2
   existing.
5. **Section 4** (RTO/RPO) — get the doc/numbers early since section 5
   depends on it, but no infra work needed, do it in parallel with 1–3.
6. **Section 7** (fold everything into a proper module) — do this refactor
   once 1, 2, 3, 6 exist individually, don't try to build it as a module from
   scratch on day one.
7. **Section 5** (runbook + drill) — last, since it needs the real infra in
   place to actually test against.
8. **Section 8** (central doc) — last of all.
