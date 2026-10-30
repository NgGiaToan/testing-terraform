# Multi-Region Customer Support — Design Spec

Design spec for adding multi-region support to Lighthouse customer
environments (`environment/*-customer`, `environment/*-cus*`). Companion to
[MULTI-REGION-IMPLEMENTATION.md](MULTI-REGION-IMPLEMENTATION.md), which has
the ordered, concrete build steps for each section below.

**Status:** design/net-new. As of this writing, `region` is hardcoded to
`"us-east-1"` in both the `backend "s3"` block and the `provider "aws"` block
of every `environment/*/main.tf` in this repo (all 13 environments checked).
Customer environment modules do not yet launch EC2 instances, a VPC, a load
balancer, or a WAF Web ACL at all — they currently provision a test S3 bucket
+ security group (same gap noted in
[BACKUP-DR.md](BACKUP-DR.md)). The VPC/EC2/LB/WAF layer is a prerequisite for
section 3 below and is out of scope for this doc; treat it as a blocking
dependency, not something this spec builds.

**Scope note:** unlike `BACKUP-DR.md` (explicitly single-region), this
requirement is inherently multi-region — that's the point of it. It does not
cover cross-region DR/failover (a customer environment runs in one region at
a time, selected at provisioning time); it covers being able to *choose*
which region a given customer lands in, and having every supported region be
equally correct.

## Client Requirement (As Stated)

Verbatim acceptance criteria as given by the client. Sections 1–5 below are
this repo's engineering breakdown of each line item, in the same order:

> - Support AWS regions confirmed and documented in the architecture and
>   infrastructure reference document
> - IaC updated to accept region as a per-customer configuration variable
> - Customer environment successfully provisioned and validated in each
>   supported AWS region
>   - All required AWS services available in each region
>   - VPC, EC2, load balancer, and storage resources provisioned correctly
>   - Security services active and functioning in each region
>   - WAF Web ACL association working correctly in each region
> - Any region-specific configuration differences identified and documented
> - Supported region list in the proposal appendix confirmed as accurate

## 1. Supported AWS Regions Confirmed and Documented

The list of AWS regions Lighthouse will actually support (e.g. `us-east-1`,
`eu-west-1`, `ap-southeast-2`) must be finalized and written into the
architecture/infrastructure reference document before any region-specific
build or validation work starts. This is a documentation gate, not an
engineering task — no region gets built against until it's on this
confirmed list.

**Why it matters:** engineering effort (section 3 below) is proportional to
the number of regions on this list. Building against an unconfirmed list
risks wasted validation work on a region that gets dropped, or missing one
that gets added late.

**Status:** a candidate list of 8 regions was captured 2026-08-19 (see
[Multiple-Region-Setup-Detail.md:34-46](Multiple-Region-Setup-Detail.md#L34-L46)),
but not signed off — blocked on cross-checking against Lighthouse's
required-AWS-services list, which doesn't exist yet.

## 2. Region as a Per-Customer IaC Configuration Variable

Every `environment/*/main.tf` currently hardcodes `region = "us-east-1"` in
two places: the `backend "s3"` block and the `provider "aws"` block. This
requirement means refactoring so **region becomes an input, set per
customer**, consumed by both blocks instead of a literal string.

**Why it matters:** this is the actual engineering unlock — everything in
section 3 depends on this existing first. Until region is parameterized,
"provision a customer in `eu-west-1`" isn't expressible in this codebase at
all.

**Constraint to flag:** Terraform's `backend` block cannot interpolate a
variable directly (`backend "s3" { region = var.region }` is invalid
HCL). Resolved as: the backend `region` stays a fixed literal (there is one
shared state bucket for every environment — see
`environment/shr-bootstrap/main.tf` — its region is unrelated to which
region a customer's resources land in), while the `provider` block's region
*does* take `var.region` normally. See the implementation doc for the
concrete pattern.

**Status:** partially done — the `provider "aws"` block now reads
`var.region` in `dev-cus0001`, `prd-customer`, and `stg-customer` (see
`environment/prd-customer/main.tf`), but the Secrets Manager schema, CI
plumbing (`terraform-plan-cost` action, calling workflows), and an
end-to-end no-op validation aren't done yet.

## 3. Customer Environment Provisioned and Validated in Each Supported Region

For every region on the confirmed list (section 1), a full customer
environment must actually be deployed there and functionally validated —
not just "the plan applied cleanly." Four things get checked per region:

- **All required AWS services available in the region.** Not every AWS
  service, instance type, or feature is available in every region. Whatever
  Lighthouse's dependency list is (specific instance families, WAF, specific
  managed services), each supported region needs to actually offer them
  before it's marked supported.
- **VPC, EC2, load balancer, and storage resources provisioned correctly.**
  The core compute/network/storage stack for a customer environment comes up
  clean in that region. *(Depends on the VPC/EC2/LB build existing at all —
  see the Status note above; this is currently a placeholder S3 bucket + SG,
  not this stack.)*
- **Security services active and functioning in each region.** Many AWS
  security services (GuardDuty, Security Hub, Config, etc. — whichever
  Lighthouse's baseline uses) are region-scoped and must be individually
  enabled and confirmed working per region, not assumed to inherit from
  wherever they were first turned on.
- **WAF Web ACL association working correctly in each region.** WAFv2 Web
  ACLs are region-scoped (the exception being the separate CloudFront/global
  scope), so the association between a Web ACL and the customer's ALB/other
  protected resource has to be verified to actually take effect in each
  region — a Web ACL built and tested in one region does not imply the
  association pattern works in another.

**Why it matters:** this is the actual acceptance test for the whole
requirement. Everything else (sections 1, 2) is preparation for being able
to do this section per region without one-off, region-specific code paths.

**Status:** blocked. Customer modules don't launch a VPC, EC2, load
balancer, or WAF at all yet — only a placeholder S3 bucket + security
group — so this whole section is blocked until that build exists (owner
not yet identified) and until section 2 is finished.

## 4. Region-Specific Configuration Differences Identified and Documented

Wherever a region needs a genuine override — a missing AZ count, an
unavailable instance type substituted for another, a compliance-driven
setting that only applies in one jurisdiction — that difference must be
captured in documentation, not left as an undocumented `count` or `try()`
buried in the module.

**Why it matters:** without this, region-specific exceptions become tribal
knowledge that breaks quietly the next time someone adds a region or
refactors the module.

**Status:** not started — nothing to document until region provisioning
(section 3) actually surfaces findings.

## 5. Support Region List in the Proposal Appendix Confirmed as Accurate

The region list promised to the client in the sales proposal's appendix must
match what was actually built and validated in sections 1–4. This is a
sign-off/reconciliation step, closing the loop between what was sold and
what was delivered.

**Why it matters:** a mismatch here (proposal promises a region that wasn't
actually validated, or validates a region nobody promised) is a contractual
and client-trust risk, not just a technical one.

**Status:** not started — needs section 1's sign-off and section 3's
validation evidence first.

**Bottom line:** this is a sequenced requirement, not five independent
tasks. Sections 1 and 2 can run in parallel, but section 3 is blocked on
both section 2 finishing and the VPC/EC2/LB/WAF build existing (currently
the single biggest blocker, with no owner assigned), and sections 4 and 5
only produce content once section 3 runs per region.

## Out of Scope

The following are explicitly **not** part of this requirement. Each is a
separate architecture decision that region selection does not depend on and
should not be conflated with:

- **Multi-tenant Lighthouse architecture** — this requirement assumes the
  existing per-customer environment model (`environment/*-customer`,
  `environment/*-cus*`: one dedicated environment/module instance per
  customer). Region support means *choosing where* that dedicated instance
  lands, not sharing infrastructure across customers.
- **Multiple-instance Lighthouse configuration**
- **Shared instance model**
- **Customer self-service portal**
- **Migration tooling** (e.g. moving an existing customer from one region to
  another after initial provisioning)
- **Restriction of risky configuration options within the Lighthouse
  instance**

If any of these become active work, they should get their own design spec
rather than being folded into multi-region support.

## Future Consideration — GitOps-Triggered Deployment

Noted for later, explicitly out of scope for this phase: automatically
triggering a customer environment deployment based on the state of the repo
(GitOps-style — e.g., a controller reconciling live infra against a Git
source of truth, or a merge-to-main auto-apply) rather than the current
manual/pipeline-triggered flow. Revisit once multi-region provisioning
itself is stable; don't design region support around an automation model
that doesn't exist yet.

## Step-by-Step Execution

Condensed checklist mapping the sequence above to action. Full detail,
worked examples, and commands for each numbered step live in
[MULTI-REGION-IMPLEMENTATION.md](MULTI-REGION-IMPLEMENTATION.md#suggested-order-of-execution--step-by-step)
— this section is kept as a quick-reference index into that doc, not a
second copy of it.

1. **Confirm the region list** (Section 1). Get the candidate list from the
   proposal owner → cross-check against Lighthouse's required
   services/instance types → write into the architecture doc with date/owner
   → get written sign-off → share back to the proposal owner.
   *Exit: a dated, signed-off region list exists.*
2. **Region as a per-customer IaC variable** (Section 2, parallel with Step
   1). Add `variable "region"` to each customer module → point
   `provider "aws"` at `var.region` → fix the backend region as a literal
   (Option B, already decided) → thread region through the Secrets Manager
   customer secret → update `terraform-plan-cost` to accept/forward it →
   update the calling workflows → run a no-op `terraform plan` for an
   existing customer through the full path.
   *Exit: no-op plan passes end-to-end for at least one existing customer.*
3. **Prerequisite VPC/EC2/LB/WAF build** (blocking dependency, start in
   parallel with Steps 1–2). Identify an owner → get a timeline → confirm
   the build takes `var.region` from the start.
   *Exit: a working single-region VPC/EC2/LB/WAF stack applies cleanly.*
4. **Provision and validate each region** (Section 3, starts only after
   Steps 2 and 3 complete). Per region: service-availability check →
   provision a test customer through the real pipeline → validate
   VPC/EC2/LB/storage → validate security services → validate the WAF Web
   ACL association blocks a real bad request → record pass/fail → tear
   down → feed any override straight into Step 5.
   *Exit: every confirmed region has a recorded pass on all four checks.*
5. **Document region-specific overrides** (Section 4, done incrementally
   during Step 4). Express each override as data
   (`region_overrides` map), not an inline conditional → log it in
   `MULTI-REGION-OVERRIDES.md` with region/override/why.
   *Exit: overrides doc is complete by the time Step 4 finishes its last
   region.*
6. **Reconcile the proposal appendix** (Section 5, needs Step 4 evidence).
   Pull the current appendix list → diff against the confirmed + validated
   list → escalate any promised-but-not-validated region immediately → flag
   (don't block on) any validated-but-not-promised region → get sign-off
   that the lists match.
   *Exit: signed-off confirmation the appendix and validated list match.*
7. **Port into the central architecture doc** (last, once Steps 1–6 are
   stable). Copy the confirmed list, validation results, and overrides doc
   into the org's central doc → link back to this repo rather than
   duplicating → add a recurring sync reminder.
   *Exit: central doc updated and linked; requirement fully closed out.*

## Open items

- [x] Candidate AWS region list (section 1) — captured 2026-08-19: see
      [MULTI-REGION-SETUP.md](MULTI-REGION-SETUP.md#step-1--confirm-the-region-list-section-1--in-progress-blocked).
      Not yet signed off — blocked on the required-services cross-check
      below.
- [ ] Proposal appendix document/link (section 5), to reconcile against the
      confirmed list.
- [ ] Lighthouse's required-AWS-services list (section 3) — what actually
      needs to be checked for availability per region. Blocks the section 1
      cross-check too — owner not yet identified (whoever owns the customer
      environment architecture).
- [ ] Lighthouse's security-service baseline (section 3) — which services
      count as "security services active and functioning."
- [ ] VPC/EC2/LB build (see Status note) — currently doesn't exist in this
      repo; blocks section 3 entirely until it lands.
