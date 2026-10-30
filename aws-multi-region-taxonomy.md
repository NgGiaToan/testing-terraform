# AWS Multi-Region Architecture Reference

> Terraform resource mapping and region/quota considerations for multi-region AWS design. Corrections and additions from the 2026-08-24 review (`MULTI-REGION-TAXONOMY-REVIEW.md`) are folded in below.

---

## How This Document Is Organized

Every entry sits at the same level: **one AWS service**, grouped under five categories (Compute, Networking, Storage, Security, Monitoring) plus a Cross-Cutting section for services that don't belong to any single region. Sub-resources are filed under the service that owns them — for example, Security Groups and NACLs live under VPC, not under EC2, since they are VPC constructs regardless of which compute resource references them.

Quota tables from the original draft are intentionally not reproduced in full. A flat number that simply resets per Region — 5 VPCs/Region, 2,500 Security Groups/Region, 100 Web ACLs/Region — is a capacity-planning input, not a multi-region *design* fact, and it drifts out of date faster than this document will be revisited. Each service instead gets:

- **Terraform resources** — what manages it today (or the gap, if none)
- **Region model** — Global vs. Regional, and what that implies for how the resource is provisioned
- **Multi-region considerations** — the non-obvious facts that actually change how you design across Regions
- **Quota scope** — called out only when it deviates from the norm (see below) or when a number genuinely differs by Region

For live quota/availability numbers, use the AWS Service Quotas API and the AWS SSM global-infrastructure parameters described in [Section 7](#7-operational-recommendations), not a static table.

### Quota Scope Model

Two patterns show up across these services, and the difference matters far more than any individual number:

1. **Per-Region, per-account (the norm).** Quota resets independently in every Region. Adding a Region gives you a fresh pool automatically. Applies to VPC, EC2, ALB/NLB, KMS, Secrets Manager, CloudTrail, WAF, Security Hub, Config, and most others below.
2. **Account-wide, global pool (the exception).** Quota is shared across *every* Region in the account. Adding a Region does **not** add headroom. The clearest example is the S3 general-purpose bucket count — this is the pattern most likely to surprise a multi-region design, precisely because it breaks the pattern everything else follows.

---

## 1. Compute

### 1.1 Amazon EC2 (Instances, AMIs, EBS)

**Terraform resources:** not yet present in this repo — needed: `aws_instance`, `aws_launch_template`, `aws_autoscaling_group`, `aws_key_pair`; AMI: `data "aws_ami"`, `aws_ami`, `aws_ami_copy`, `aws_ami_launch_permission`; EBS: `aws_ebs_volume`, `aws_volume_attachment`, `aws_ebs_snapshot`, `aws_ebs_snapshot_copy`.

**Region model:** Regional, down to the AZ. Support for an instance type in a Region does not guarantee support in every AZ of that Region. Verify with:
```
aws ec2 describe-instance-type-offerings --location-type "availability-zone" \
  --filters Name=location,Values=us-east-2a --region us-east-2
```

**Multi-region considerations:**
- **AMI IDs are Region-specific** even for an identical image. Resolve them with `data "aws_ami"` (filtered by `most_recent`, `owners`, `name`) per provider alias instead of hardcoding IDs.
- **EBS volumes and snapshots are AZ-bound.** Moving one to another AZ or Region requires a snapshot copy (`aws_ebs_snapshot_copy`) and restore — there is no in-place move.
- Volume-type availability by Region isn't centrally documented the way instance-type offerings are; Local Zones have their own separate table.
- Performance ceilings depend on Nitro support: io2 Block Express reaches 4,000 MB/s / 256,000 IOPS / 64 TiB per volume but only on Nitro-based instances; io1 tops out at 64,000 IOPS / 1,000 MB/s and needs EBS-optimized/Nitro to hit that ceiling.

**Quota scope:** On-Demand and Spot vCPU quotas are per account, per Region, and auto-increase with usage — **but the auto-increase is based on usage history in that specific Region.** A brand-new Region has no history to act on, so on day 1 of a new-Region rollout, request the increase proactively rather than relying on automation. Reserved Instances discount running On-Demand capacity but never exceed the On-Demand limit itself.

**Source:** [EC2 instance type availability](https://docs.aws.amazon.com/ec2/latest/instancetypes/ec2-instance-regions.html) · [EC2 service quotas](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-resource-limits.html) · [EBS volume types](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html)

---

## 2. Networking

### 2.1 Amazon VPC (Subnets, Routing, Gateways, Endpoints, Security Groups, NACLs, Flow Logs)

**Terraform resources:** `aws_vpc`, `aws_subnet`, `aws_eip`, `aws_route_table` (+ `aws_route_table_association`), `aws_network_acl` (+ `aws_network_acl_association`, `aws_network_acl_rule`), `aws_ec2_managed_prefix_list`, `aws_internet_gateway`, `aws_nat_gateway`, `aws_vpc_endpoint`, `aws_flow_log`, `aws_security_group`, `aws_default_security_group`, `aws_vpc_security_group_ingress_rule`, `aws_vpc_security_group_egress_rule`.

**Region model:** Regional. Every VPC, subnet, security group, NACL, and gateway belongs to exactly one Region (subnets further to one AZ). Nearly all VPC quotas (VPCs/Region, Security Groups/Region, rules/SG, ENIs/Region, NAT Gateways/AZ, route tables/VPC, etc.) follow the per-Region-per-account norm — the same values everywhere, resetting fresh in each new Region.

**Multi-region considerations:**
- When a Security Group is shared cross-account via VPC sharing/RAM, the *rule* quota is enforced against the **owning** account, while SG-per-ENI and rule-per-ENI quotas apply as the **minimum** of the owner's and participant's values.
- The newer **Regional NAT Gateway** architecture spans multiple AZs from a single deployment (no dedicated public subnet required) and supports 32 IPs/AZ vs. 8 for the older zonal NAT Gateway — worth standardizing on if rolling the same NAT pattern into new Regions.
- VPC endpoints are singly-homed to one VPC in one Region; a multi-region design needs its own endpoint stack per Region.

**Source:** [Amazon VPC quotas](https://docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html) · [Regional NAT Gateway](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateways-regional.html)

### 2.2 Elastic Load Balancing (ALB / NLB)

**Terraform resources:** not yet present — needed: `aws_lb`, `aws_lb_listener`, `aws_lb_listener_rule`, `aws_lb_target_group`, `aws_lb_target_group_attachment`.

**Region model:** Regional. The "load balancers per Region" pool is shared between Classic ELB and ALB; NLB has its own separate pool. The target-group pool (3,000/Region) is shared between ALB and NLB — a uniform limit everywhere, not a Region-specific concern.

**Multi-region considerations:** a target registered in N target groups counts as N targets against quota. Chaining an ALB as an NLB target counts as 50 targets with cross-zone load balancing off, or 100 with it on — relevant when a cross-region failover topology daisy-chains load balancers.

**Source:** [ALB quotas](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-limits.html) · [NLB quotas](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-limits.html)

---

## 3. Storage

### 3.1 Amazon S3

**Terraform resources:** `aws_s3_bucket`, `aws_s3_bucket_lifecycle_configuration`, `aws_s3_bucket_ownership_controls`, `aws_s3_bucket_public_access_block`, `aws_s3_bucket_server_side_encryption_configuration`, `aws_s3_bucket_versioning`.

**Region model:** Regional resource, but the bucket-count quota is the clear exception to the per-Region norm: **it is a single pool shared across every Region in the account.** As of November 2024, AWS raised the ceiling from the 10,000 default to **1,000,000 buckets/account** (via Service Quotas request) — but the pool is still account-wide, so adding Regions never adds headroom. This is the single most important fact for any bucket-per-tenant or bucket-per-region-per-tenant design.

**Multi-region considerations:**
- Directory buckets (100) are the one S3 sub-quota scoped per Region, not account-wide.
- Multi-Region Access Points: max 100/account, up to 17 Regions per MRAP, and the Region set is **immutable after creation** — changing it means delete and recreate.
- Console-level bucket management for the commercial partition is centralized in **us-east-1**; GovCloud (US) is centralized in **us-gov-west-1**.
- Buckets cannot be renamed or moved between Regions — a "move" is always copy + delete.

**Source:** [S3 bucket restrictions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/BucketRestrictions.html) · [S3 up to 1 million buckets](https://aws.amazon.com/about-aws/whats-new/2024/11/amazon-s3-up-1-million-buckets-per-aws-account/)

### 3.2 AWS Backup

**Terraform resources:** not yet present — needed: `aws_backup_vault`, `aws_backup_plan`, `aws_backup_selection`, `aws_backup_vault_policy`, `aws_backup_vault_lock_configuration`.

**Region model:** Regional; vaults and plans exist per account, per Region.

**Multi-region considerations:**
- Cross-region copy jobs use a "spillover" model: up to 100 concurrent jobs into a destination Region overall, plus up to 5 more per vault once that cap is hit.
- Cross-account copy to the same destination Region caps at 30 concurrent; only 1 concurrent backup+copy job is allowed per resource.
- The first copy into a new Region is always a full copy; later copies are incremental where the service supports it — EBS is always a full copy if the encryption status changes.
- Cross-account copy requires a **customer-managed KMS key**; AWS-managed keys block it.
- Logically air-gapped vaults currently only support same-account/same-Region as the primary backup target — they cannot be used as a cross-region target.

**Source:** [AWS Backup quotas](https://docs.aws.amazon.com/aws-backup/latest/devguide/aws-backup-limits.html) · [Cross-region backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/cross-region-backup.html)

---

## 4. Security

### 4.1 AWS KMS

**Terraform resources:** `aws_kms_key`.

**Region model:** Regional — a key lives in exactly one Region. Cross-region use requires an explicit **Multi-Region Key**, not just any key replicated manually.

**Region-dependent quota:** the symmetric cryptographic-operation request rate is genuinely different by Region — **10,000 req/s** in six primary Regions (us-east-1, us-west-2, eu-west-1, and others) vs. **5,500 req/s** everywhere else. Factor this into Region selection for latency/throughput-sensitive workloads. `UpdatePrimaryRegion` counts as 2 requests (one per affected Region).

**Source:** [KMS quotas](https://docs.aws.amazon.com/kms/latest/developerguide/limits.html)

### 4.2 AWS WAF

**Terraform resources:** `aws_wafv2_web_acl`, `aws_wafv2_rule_group`, `aws_wafv2_web_acl_rule_group_association`, `aws_wafv2_web_acl_logging_configuration`. Geo-matching is a `geo_match_statement` inside a rule's `statement` block, not a standalone resource, and shares the same WCU pool as every other rule.

**Region model:** Regional; quota values are identical across all Regions — a capacity-planning input, not a multi-region design driver.

**Cost note:** usage above 1,500 WCU on a Web ACL bills extra per million requests for every 500 WCU over the default, even though the technical ceiling is 5,000 WCU.

**Source:** [WAF quotas](https://docs.aws.amazon.com/waf/latest/developerguide/limits.html)

### 4.3 AWS Certificate Manager (ACM)

**Terraform resources:** `aws_acm_certificate`, `aws_acm_certificate_validation`.

**Region model:** Regional — the defining fact for ACM. A certificate must be requested **separately in every Region** where it's used (e.g., once per Region behind regional ALBs). There is no cross-account sharing (no export, no RAM) — each account must request its own.

**Multi-region considerations:** the one fixed exception is CloudFront, which always requires the certificate to be issued in **us-east-1**, regardless of where the distribution serves traffic.

**Source:** [ACM quotas](https://docs.aws.amazon.com/acm/latest/userguide/acm-limits.html)

### 4.4 AWS Secrets Manager

**Terraform resources:** `aws_secretsmanager_secret`, `aws_secretsmanager_secret_version`, `aws_secretsmanager_secret_rotation`.

**Region model:** Regional; secrets exist per account, per Region.

**Multi-region considerations:** cross-account requests are billed against the **caller's** account quota, not the secret owner's — relevant for shared-secret architectures. Avoid calling `PutSecretValue`/`UpdateSecret` more than once per 10 minutes; each call creates a new version.

**Source:** [Secrets Manager quotas](https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_limits.html)

### 4.5 Amazon GuardDuty

**Terraform resources:** `aws_guardduty_detector`, `aws_guardduty_organization_configuration`, `aws_guardduty_member`, `aws_guardduty_filter`, `aws_guardduty_ipset`.

**Region model:** Strictly regional, and data does not leave the Region — each Region has its own detector ID, and findings are generated and retained where the underlying activity occurred.

**Multi-region considerations:** aggregate findings across Regions via EventBridge, an S3 fan-in bucket, or — preferably — Security Hub's native cross-Region aggregation. Findings are retained **90 days**, a hard, non-adjustable limit. For S3 export, the destination bucket and KMS key must be in the same Region as the finding; export works commercial-to-commercial but not into opt-in Regions.

**Source:** [GuardDuty quotas](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_limits.html)

### 4.6 AWS Security Hub

**Terraform resources:** `aws_securityhub_account`, `aws_securityhub_standards_subscription`, `aws_securityhub_finding_aggregator`, `aws_securityhub_member`.

**Region model:** Regional, with an explicit cross-Region aggregation feature.

**Multi-region considerations:**
- `BatchImportFindings`/`BatchUpdateFindings` affect both the linked Region and the aggregation Region, and `GetFindings` reads from both. `BatchEnableStandards`/`UpdateStandardsControl` apply per-Region only — aggregation does not propagate them.
- GovCloud (US) aggregates only within GovCloud; China aggregates only within the China partition — no cross-partition aggregation.
- A disabled-by-default Region cannot be chosen as the aggregation Region.
- Some standards/controls are Region-limited: "AWS Control Tower service-managed" only where Control Tower operates; the "AWS Resource Tagging" standard is unavailable in Asia Pacific (Taipei); several individual controls (ECS, EFS, EKS, DocumentDB, DynamoDB, Cognito, and others) are unavailable in specific Regions — verify per control before relying on them.

**API rate limits** (uniform, not Region-varying): `BatchEnableStandards` 1 req/s; `GetFindings` 3 req/s (burst 6); `BatchImportFindings` 10 req/s (burst 30).

**Source:** [Security Hub quotas](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub_limits.html) · [Security Hub Region availability](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-regions.html)

### 4.7 AWS CloudTrail

**Terraform resources:** `aws_cloudtrail`, `aws_cloudtrail_event_data_store`.

**Region model:** Regional trails, with an explicit multi-Region trail option. Security Hub recommends at least one multi-Region trail capturing both read and write management events.

**Cost note:** the first copy of management events per Region is free; additional trails delivering the same data to another destination incur cost.

**Source:** [CloudTrail quotas](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/WhatIsCloudTrail-Limits.html)

### 4.8 AWS Config

**Terraform resources:** `aws_config_configuration_recorder`, `aws_config_config_rule`, `aws_config_conformance_pack`, `aws_config_configuration_aggregator`.

**Region model:** Regional; aggregators are the mechanism for cross-Region/cross-account rollup — up to 10,000 accounts per aggregator, up to 1,000 account adds/removes per week across all aggregators.

**Source:** [AWS Config quotas](https://docs.aws.amazon.com/config/latest/developerguide/configlimits.html)

### 4.9 Amazon Inspector

**Terraform resources:** `aws_inspector2_enabler`, `aws_inspector2_organization_configuration`.

**Region model:** Regional; no Region-varying figures to flag.

**Source:** [Inspector quotas](https://docs.aws.amazon.com/inspector/latest/user/quotas.html)

### 4.10 IAM Access Analyzer

**Terraform resources:** `aws_accessanalyzer_analyzer`, `aws_accessanalyzer_archive_rule`.

**Region-dependent quota:** the clearest region-value example in this entire document — policy generation is capped at **50/day** in most Regions but only **5/day** in Africa (Cape Town), Asia Pacific (Hong Kong/Jakarta), Europe (Milan), and Middle East (Bahrain). Flag this explicitly when choosing Regions for IAM tooling.

**Source:** [IAM Access Analyzer quotas](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-quotas.html)

### 4.11 AWS Network Firewall

**Terraform resources:** `aws_networkfirewall_firewall`, `aws_networkfirewall_firewall_policy`, `aws_networkfirewall_rule_group`, `aws_networkfirewall_tls_inspection_configuration`.

**Region model:** Regional; quotas are uniform across Regions.

**Multi-region considerations:** the "Active Threat Defense" managed rule group consumes 15,000 of the 30,000 default stateful rule-capacity pool — worth knowing before layering additional custom rule groups on top.

**Source:** [Network Firewall quotas](https://docs.aws.amazon.com/network-firewall/latest/developerguide/quotas.html)

### 4.12 AWS Elastic Disaster Recovery

**Terraform resources:** `aws_drs_replication_configuration_template` (provider v5.55.0+) manages the **default replication template only** — source server registration, agent installation, and per-server launch configuration remain outside Terraform and require the AWS CLI/console/agent.

**Multi-region considerations:** environments exceeding 300 source servers need multiple staging accounts/target Regions; moving a source server between accounts requires reinstalling the agent; custom encryption requires sharing the KMS key across accounts.

**Source:** [DRS at scale](https://docs.aws.amazon.com/drs/latest/userguide/drs-at-scale.html) · [aws_drs_replication_configuration_template](https://registry.terraform.io/providers/hashicorp/aws/6.21.0/docs/resources/drs_replication_configuration_template)

---

## 5. Monitoring

### 5.1 Amazon CloudWatch

**Terraform resources:** `aws_cloudwatch_metric_alarm`, `aws_cloudwatch_dashboard`, `aws_cloudwatch_composite_alarm`.

**Region-dependent quota:** Canary limit is **300** in us-east-1 and ap-northeast-1 vs. **500** everywhere else — another concrete example of a value that differs by Region.

**Multi-region considerations:** quotas are defined per account and per Region independently. Aggregating across many Regions/accounts (e.g., via Amazon Managed Grafana) means requesting quota increases individually for every account/Region combination that hits a ceiling — there is no single multi-region increase.

**Source:** [CloudWatch quotas](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_limits.html)

---

## 6. Cross-Cutting

### 6.1 IAM

**Terraform resources:** `aws_iam_policy_document` (data source), `aws_iam_policy`, `aws_iam_role`, `aws_iam_role_policy_attachment`.

**Region model:** Global — one role/policy per account, not tied to any Region. In multi-provider Terraform, create IAM resources **once** and reference the ARN from each regional provider alias; don't recreate per Region.

### 6.2 Account & Metadata Data Sources

| Data source | Region-sensitive? | Notes |
|---|---|---|
| `aws_caller_identity` | No | Account-level output (Account ID/ARN), identical regardless of Region |
| `aws_availability_zones` | **Yes** | AZ list differs by Region — must be called per provider alias |
| `aws_region` | Yes | Returns the current Region of a given provider alias |
| `aws_regions` | No | Full list of Regions enabled for the account — useful for driving checks instead of hardcoding a Region list |

```hcl
data "aws_availability_zones" "this" {
  provider = aws.ap_southeast_1
  state    = "available"
}
```

---

## 7. Operational Recommendations

Static quota tables — including the ones in this document — drift out of date faster than the document itself gets revisited. For a repo that runs Terraform across multiple environments (`dev-*`, `stg-*`, `prd-*`, `shr-*`) and is adding regions over time, prefer checking actual account/Region state at deploy time:

- **Live quota checks via the Service Quotas API**, instead of trusting a static table:
  ```
  aws service-quotas list-service-quotas --service-code <code> --region <region>
  aws service-quotas get-service-quota --service-code <code> --quota-code <quota-code> --region <region>
  ```
  This returns the account's *actual current* quota, including any prior increases. A pre-flight check for the quotas most likely to be hit when multiplying by regions × environments (VPC = 5/Region, EIP = 5/Region, Internet Gateway = 5/Region) catches a hard failure before `terraform apply` runs, not during it.

- **Live service/Region availability check** (distinct from quota):
  ```
  aws ssm get-parameters-by-path --path /aws/service/global-infrastructure/regions/<region>/services
  ```
  The official programmatic way to check "is service X available in Region Y," complementing the static AWS Regional Product Services page in [Section 8](#8-reference-sources).

- Consider wiring both checks into the pipeline for any environment provisioning per-Region resources with low default ceilings — each additional Region added to `dev`/`stg`/`prd`/`shr` (including the new `shr-backup-dr` environment) multiplies exposure to the 5-per-Region defaults called out in [Section 2.1](#21-amazon-vpc-subnets-routing-gateways-endpoints-security-groups-nacls-flow-logs).

---

## 8. Reference Sources

| Purpose | Source |
|---|---|
| Service availability by Region (overview) | `aws.amazon.com/about-aws/global-infrastructure/regional-product-services/` |
| Region & AZ list | `docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions.html` |
| EC2 instance type availability | `docs.aws.amazon.com/ec2/latest/instancetypes/ec2-instance-regions.html` |
| EC2 quotas | `docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-resource-limits.html` |
| EBS volume types & performance | `docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html` |
| VPC quotas | `docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html` |
| ALB quotas | `docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-limits.html` |
| NLB quotas | `docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-limits.html` |
| S3 quotas | `docs.aws.amazon.com/AmazonS3/latest/userguide/BucketRestrictions.html` |
| AWS Backup quotas | `docs.aws.amazon.com/aws-backup/latest/devguide/aws-backup-limits.html` |
| KMS quotas | `docs.aws.amazon.com/kms/latest/developerguide/limits.html` |
| WAF quotas | `docs.aws.amazon.com/waf/latest/developerguide/limits.html` |
| ACM quotas | `docs.aws.amazon.com/acm/latest/userguide/acm-limits.html` |
| Secrets Manager quotas | `docs.aws.amazon.com/secretsmanager/latest/userguide/reference_limits.html` |
| GuardDuty quotas | `docs.aws.amazon.com/guardduty/latest/ug/guardduty_limits.html` |
| Security Hub quotas & Region availability | `docs.aws.amazon.com/securityhub/latest/userguide/securityhub_limits.html`, `securityhub-regions.html` |
| CloudTrail quotas | `docs.aws.amazon.com/awscloudtrail/latest/userguide/WhatIsCloudTrail-Limits.html` |
| AWS Config quotas | `docs.aws.amazon.com/config/latest/developerguide/configlimits.html` |
| Amazon Inspector quotas | `docs.aws.amazon.com/inspector/latest/user/quotas.html` |
| IAM Access Analyzer quotas | `docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-quotas.html` |
| AWS Network Firewall quotas | `docs.aws.amazon.com/network-firewall/latest/developerguide/quotas.html` |
| AWS Elastic Disaster Recovery at scale | `docs.aws.amazon.com/drs/latest/userguide/drs-at-scale.html` |
| CloudWatch quotas | `docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_limits.html` |

*Quota figures should be treated as directional and verified against the Service Quotas console/API before use in production design — see [Section 7](#7-operational-recommendations).*
