# Backup & Disaster Recovery — Design Spec

Design spec for backup/DR coverage of Lighthouse customer environments
(`environment/*-customer`, `environment/*-cus*`). Companion to
[BACKUP-DR-IMPLEMENTATION.md](BACKUP-DR-IMPLEMENTATION.md), which has the
ordered, concrete build steps for each section below.

**Status:** design/net-new. As of this writing, no backup, DR, or Golden AMI
tooling exists in this repo — customer environment modules do not yet launch
EC2 instances at all (they currently provision a test S3 bucket + security
group). The EC2/Golden-AMI layer is a prerequisite for sections 1 and 5 below
and is out of scope for this doc; see the implementation doc's suggested
execution order.

**Scope note:** single region only. Cross-region S3/backup redundancy is
explicitly out of scope for this phase. This constrains the RTO/RPO targets in
section 4 below — single-region DR implies different (generally less
aggressive) numbers than a multi-region setup, and that should be made
explicit wherever these targets are signed off.

## 1. Automated AMI Snapshots per Customer Environment

Daily automated snapshot of every customer instance, tagged by environment
(e.g. `cus0001`, `stg-customer`, `prd-customer`), retained for a minimum of 30
days, with periodic validation that a snapshot actually restores to a working
instance (not just that the snapshot exists).

## 2. Golden AMI

A single hardened, pre-configured base image (OS + patches + agents +
baseline hardening) that every Lighthouse instance launches from, built via a
repeatable pipeline, validated (boots cleanly, passes hardening/CIS checks,
required agents present), and documented (contents, version, build date,
source AMI lineage).

## 3. Golden AMI Update Process on New App Release

A documented, repeatable procedure for rebuilding/re-validating the Golden AMI
when a new app version ships: who triggers it, what gets baked in, how it's
tested, and how the new AMI ID propagates into Terraform (via a variable/SSM
parameter, never hardcoded).

## 4. RTO / RPO Targets

- **RTO** (Recovery Time Objective): max acceptable time to restore service
  after an outage. _Placeholder — pending Digi's RTO/RPO procedure doc:
  `<link/doc ID>`_
- **RPO** (Recovery Point Objective): max acceptable data loss window.
  Directly tied to snapshot frequency — daily snapshots imply an RPO of up to
  ~24h unless a supplementary mechanism (e.g. DB-level continuous backup)
  fills the gap. _Placeholder — pending the same doc._

These numbers must come from Digi's existing RTO/RPO procedure document, not
be invented ad hoc, so they stay consistent with how the rest of the org
defines and measures them. See implementation doc section 4 for the
cross-check against actual snapshot cadence.

## 5. Recovery Procedure — Documented and Tested

A step-by-step DR runbook (which AMI, which environment, how to relaunch, how
to reattach networking/storage/DNS) that has been executed as an actual drill
— restoring an instance from a snapshot and confirming it comes back inside
the defined RTO, with recorded evidence (report, ticket, or log), on a
recurring cadence (e.g. quarterly).

## 6. S3 Buckets Encrypted at Rest

Any S3 buckets involved in this backup/DR flow (exported snapshots, logs,
Image Builder artifacts) encrypted at rest with SSE-KMS using a
customer-managed key, matching Digi's Cryptography Standard (key rotation, key
policy restrictions). _Placeholder — pending link to Digi's Cryptography
Standard: `<link/doc ID>`_

## 7. All Backup and DR Configuration as IaC

Everything above (backup vault/plan/selection, Golden AMI pipeline, S3 bucket
+ encryption, IAM roles) defined in Terraform in this repo, reviewable and
reproducible like the rest of `environment/*`.

## 8. Documented in the Architecture/Infrastructure Reference Doc

The design and recovery procedures written into the org's central
architecture/infra reference document (not just this repo), once sections 1–7
are implemented and stable — so it's discoverable outside the Terraform
codebase and doesn't document a moving target.

## Open items

- [ ] Link to Digi's RTO/RPO procedure document (section 4)
- [ ] Link to Digi's Cryptography Standard (section 6)
- [ ] Location/format of the org's central architecture reference doc
      (section 8)
