# Multi-Region Candidate List

**Status:** Draft
**Owner:** <name/role responsible for this doc>
**Related docs:** [MULTI-REGION-SUPPORT.md](MULTI-REGION-SUPPORT.md#1-supported-aws-regions-confirmed-and-documented) · [Multiple-Region-Setup-Detail.md §2.1](Multiple-Region-Setup-Detail.md#21-step-1--confirm-the-region-list)

---

## 0. Change Log

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-19 | 0.1 | First draft — candidate region list taken from sales proposal appendix | |
| 2026-08-20 | 0.2 | Moved doc to standard structure (change log, definitions, validation methodology, cross-check §5.1/5.2, sign-off checklist) | |
| | | | |

> Must be updated every time the region list or status changes. No new entry = no valid change.

---

## 1. Overview

- This doc confirms: the official list of AWS regions Lighthouse supports.
- Not covered: how to provision (→ Step 2–4, `Multiple-Region-Setup-Detail.md` §2.2–2.4), region overrides (→ Step 5, `MULTI-REGION-OVERRIDES.md`).
- Once **Confirmed**, this is the source of truth — other docs (`MULTI-REGION-SUPPORT.md`, `Multiple-Region-Setup-Detail.md`) **link back to §5.2**, not copy the region table.
- This doc is a **living document**: re-validated periodically per §4.4, not signed off once and forgotten.

---

## 2. Definitions

| Term | Definition |
|---|---|
| Candidate region | A region proposed but not yet fully validated |
| Confirmed region | A region that has passed the full cross-check in §5 and been signed off in §6 |
| Required service/instance type | The list of services/instance types that must be available in a region (source: §4.1) |
| Aggregation Region | ⚠️ **BLOCKER — role not yet formally specified.** us-east-1 is flagged as the Aggregation Region in the sales proposal appendix, but the exact scope/role (cross-customer aggregation? admin-level functions?) has not been confirmed. This doc **cannot move to Confirmed** until (owner — see §4.1) settles the Aggregation Region's role. Tracking: `<ticket link>` |

---

## 3. Candidate Region List

| Region code | Requested by | Business justification | Source (proposal appendix, date pulled) | Notes |
|---|---|---|---|---|
| us-east-1 | <team/person, not yet identified> | <business reason, not yet recorded> | Sales proposal appendix, 2026-08-19 | Aggregation Region — see blocker in §2 |
| us-east-2 | <team/person, not yet identified> | <business reason, not yet recorded> | Sales proposal appendix, 2026-08-19 | Input, **not yet validated** |
| us-west-1 | <team/person, not yet identified> | <business reason, not yet recorded> | Sales proposal appendix, 2026-08-19 | Input, **not yet validated** |
| us-west-2 | <team/person, not yet identified> | <business reason, not yet recorded> | Sales proposal appendix, 2026-08-19 | Input, **not yet validated** |
| eu-west-1 | <team/person, not yet identified> | <business reason, not yet recorded> | Sales proposal appendix, 2026-08-19 | Input, **not yet validated** |
| eu-west-2 | <team/person, not yet identified> | <business reason, not yet recorded> | Sales proposal appendix, 2026-08-19 | Input, **not yet validated** |
| eu-central-1 | <team/person, not yet identified> | <business reason, not yet recorded> | Sales proposal appendix, 2026-08-19 | Input, **not yet validated** |
| ap-southeast-2 | <team/person, not yet identified> | <business reason, not yet recorded> | Sales proposal appendix, 2026-08-19 | Input, **not yet validated** |

> Every row in this table defaults to **unvalidated input** until it appears in §5 with a Confirmed result.

---

## 4. Validation Methodology

**4.1 Source of the required-services/instance-types list**
- Owner: <role, not yet identified — whoever owns the customer-environment architecture>
- Link: `<link to required list — does not exist yet, blocker>`
- Last updated: `<date — N/A, list doesn't exist yet>`

**4.2 Cross-check procedure**
1. Pull the latest required service/instance type list from the source in §4.1
2. For each candidate region, run the corresponding check (see §4.3)
3. Record pass/fail results with evidence in §5
4. If it fails → note the reason, propose Deferred or Dropped

**4.3 Commands used & pass/fail criteria**

| Check | Command | Pass criteria |
|---|---|---|
| Instance type availability | `aws ec2 describe-instance-type-offerings --region <region> --location-type region --filters Name=instance-type,Values=<type>` | Instance type is returned in the output |
| GuardDuty availability | `aws guardduty list-detectors --region <region>` | Region supports GuardDuty (no `UnrecognizedClientException`/region-unsupported error) |
| <other service — Security Hub, Config, WAFv2, ...> | `<command>` | `<criteria>` |

**4.4 Re-validation trigger**
- When a new required service/instance type is added to the list in §4.1
- Periodically, every **(X months — TBD)**, regardless of whether anything changed
- Owner of the re-validation: <role>
- Re-validation results → update §5 + log in §0

---

## 5. Cross-Check Results

**Status: blocked** — the required-services/instance-types list in §4.1 does not exist yet, so §5.1/§5.2 have no real data.

**5.1 Detail table**

| Region | Required item | Available? | Notes / Evidence | Date checked |
|---|---|---|---|---|
| *(pending — populate once the required-services list in §4.1 exists)* | | | | |

**5.2 Summary table**

| Region | Result | Reason (short) | Revisit date (if Deferred) | Blocked by (if Deferred) |
|---|---|---|---|---|
| us-east-1 | Deferred | Cross-check blocked — required list doesn't exist; Aggregation Region role not confirmed | (not set) | Required-services list (§4.1) + Aggregation Region role (§2) |
| us-east-2 | Deferred | Cross-check blocked — required list doesn't exist | (not set) | Required-services list (§4.1) |
| us-west-1 | Deferred | Cross-check blocked — required list doesn't exist | (not set) | Required-services list (§4.1) |
| us-west-2 | Deferred | Cross-check blocked — required list doesn't exist | (not set) | Required-services list (§4.1) |
| eu-west-1 | Deferred | Cross-check blocked — required list doesn't exist | (not set) | Required-services list (§4.1) |
| eu-west-2 | Deferred | Cross-check blocked — required list doesn't exist | (not set) | Required-services list (§4.1) |
| eu-central-1 | Deferred | Cross-check blocked — required list doesn't exist | (not set) | Required-services list (§4.1) |
| ap-southeast-2 | Deferred | Cross-check blocked — required list doesn't exist | (not set) | Required-services list (§4.1) |

> Deferred **must** have a revisit date or blocked-by — never leave it open-ended. Revisit dates should be set as soon as the §4.1 owner is identified.

---

## 6. Sign-Off

- **Confirmed by:** *(not yet — pending §5)*
- **Region list version approved:** *(not yet — will point to §5.2, version in §0, once signed off)*
- **Prerequisites before sign-off:**
  - [ ] No remaining blockers in §2 (Aggregation Region role confirmed)
  - [ ] Every candidate region in §3 has a result in §5 (none left "not yet validated")
  - [ ] Any Deferred items have a clear revisit date/blocked-by

**Operating rules after Confirmed:**
1. No downstream step (provision, deploy) may target a region outside the approved list in §5.2.
2. **Process for adding a new region after Confirmed:**
   - Propose the new region → add it to §3 as a new candidate (do not edit the Confirmed table directly)
   - Re-run §4 for that region
   - Update §5, request additional sign-off in §6 (note it's an amendment, not the original Confirmed)
   - Log the change in §0
