# AWS Multi-Region Reference — Review Report

> Review of `aws-multi-region-taxonomy.md` (Terraform resource mapping + region/quota considerations for multi-region AWS design), evaluated against current AWS documentation and the `hashicorp/aws` Terraform provider. Reviewed 2026-08-24.

---

## 1. Overall Assessment

The source document is well-structured and largely accurate as a static reference: the Compute / Networking / Storage / Security / Monitoring taxonomy is sound, the multi-region-specific caveats (ACM is regional except CloudFront's us-east-1 requirement, IAM is global, GuardDuty/Security Hub findings stay in their origin region, S3 bucket management is centralized in us-east-1, KMS keys are single-region unless using multi-region keys) are all correct and are exactly the kind of non-obvious facts worth documenting.

The main gaps are: (1) a handful of quota figures that have changed since the document was last updated, (2) an incomplete Terraform resource mapping (flagged by the document itself in its own "missing" section), and (3) no process for keeping the numbers current — the document only points to static AWS docs pages, not to a way of checking the *actual* quota/availability for a given account/region at the time of deployment.

---

## 2. Accuracy Corrections

| # | Section | Original claim | Correction | Source |
|---|---|---|---|---|
| 1 | 3.1 S3 — bucket quota | General purpose bucket/account default: 10,000 | Still correct as the *default*, but AWS raised the **ceiling to 1,000,000 buckets/account** (via Service Quotas request) as of November 2024. Worth noting explicitly if the design uses a bucket-per-tenant or bucket-per-region-per-tenant pattern. | [Amazon S3 now supports up to 1 million buckets](https://aws.amazon.com/about-aws/whats-new/2024/11/amazon-s3-up-1-million-buckets-per-aws-account/) |
| 2 | 4.2 WAF — WCU | Web ACL WCU default: 5,000 (raised from 1,500) | Confirmed accurate, no change needed. | [AWS WAF increases web ACL capacity units limits](https://aws.amazon.com/about-aws/whats-new/2023/04/aws-waf-web-acl-capacity-units-limits/) |
| 3 | 1.1 EC2 — vCPU quota | "On-Demand vCPU quota auto-increases with usage" | Correct in principle, but missing an important caveat for multi-region rollouts: **auto-increase is based on usage history in that specific Region.** A brand-new Region with no prior workload starts at the low default quota, and the automation has no history to act on yet. On "day 1" of a new-region rollout, do not rely on this — request a quota increase proactively before deployment. | [Amazon EC2 service quotas](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-resource-limits.html) |
| 4 | 4.12 / 8. AWS Elastic Disaster Recovery | "No corresponding Terraform resource" | Not entirely true — `hashicorp/aws` provider (v5.55.0+) has `aws_drs_replication_configuration_template`, which manages the *default replication template* only. Core DRS operations (source server registration, agent installation, per-server launch configuration) remain outside Terraform and require the AWS CLI/console/agent. Recommend rephrasing to "partial Terraform support — template only" rather than "none." | [aws_drs_replication_configuration_template — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/6.21.0/docs/resources/drs_replication_configuration_template) |

---

## 3. Missing Terraform Resources (filling in Section 8 of the source document)

| Service | Terraform resource(s) |
|---|---|
| EC2 instance / autoscaling | `aws_instance`, `aws_launch_template`, `aws_autoscaling_group`, `aws_key_pair` |
| AMI | `data "aws_ami"`, `aws_ami`, `aws_ami_copy` (cross-region AMI copy), `aws_ami_launch_permission` |
| EBS | `aws_ebs_volume`, `aws_volume_attachment`, `aws_ebs_snapshot`, `aws_ebs_snapshot_copy` |
| ALB / NLB | `aws_lb`, `aws_lb_listener`, `aws_lb_listener_rule`, `aws_lb_target_group`, `aws_lb_target_group_attachment` |
| AWS Backup | `aws_backup_vault`, `aws_backup_plan`, `aws_backup_selection`, `aws_backup_vault_policy`, `aws_backup_vault_lock_configuration` |
| ACM | `aws_acm_certificate`, `aws_acm_certificate_validation` |
| AWS Network Firewall | `aws_networkfirewall_firewall`, `aws_networkfirewall_firewall_policy`, `aws_networkfirewall_rule_group`, `aws_networkfirewall_tls_inspection_configuration` |
| Secrets Manager | `aws_secretsmanager_secret`, `aws_secretsmanager_secret_version`, `aws_secretsmanager_secret_rotation` |
| GuardDuty | `aws_guardduty_detector`, `aws_guardduty_organization_configuration`, `aws_guardduty_member`, `aws_guardduty_filter`, `aws_guardduty_ipset` |
| Security Hub | `aws_securityhub_account`, `aws_securityhub_standards_subscription`, `aws_securityhub_finding_aggregator`, `aws_securityhub_member` |
| CloudTrail | `aws_cloudtrail`, `aws_cloudtrail_event_data_store` |
| AWS Config | `aws_config_configuration_recorder`, `aws_config_config_rule`, `aws_config_conformance_pack`, `aws_config_configuration_aggregator` |
| Amazon Inspector | `aws_inspector2_enabler`, `aws_inspector2_organization_configuration` |
| IAM Access Analyzer | `aws_accessanalyzer_analyzer`, `aws_accessanalyzer_archive_rule` |
| AWS Elastic Disaster Recovery | `aws_drs_replication_configuration_template` (limited — see Correction #4 above) |
| CloudWatch | `aws_cloudwatch_metric_alarm`, `aws_cloudwatch_dashboard`, `aws_cloudwatch_composite_alarm` |

---

## 4. Conceptual Gap: Static Quota Tables vs. Live Verification

The source document is strong on *reference* quota tables but weak on *process* — it lists AWS documentation pages as the source of truth, but published quota numbers drift over time while the document itself won't be updated on the same cadence. For a repo that runs Terraform through a CI/CD pipeline across many environments (`dev-*`, `stg-*`, `prd-*`, `shr-*`), it is more valuable to check the *actual* quota/availability for the target account/region at deploy time than to trust a table.

Recommended additions:

- **AWS Service Quotas API as the live source of truth**, not just static doc links:
  ```
  aws service-quotas list-service-quotas --service-code <code> --region <region>
  aws service-quotas get-service-quota --service-code <code> --quota-code <quota-code> --region <region>
  ```
  This returns the account's actual current quota (including any prior increases), not just the AWS default. Wiring a pre-flight check into the pipeline for the quotas most likely to be hit when multiplying by regions × environments (VPC = 5/region, EIP = 5/region, Internet Gateway = 5/region) would catch a hard failure before `terraform apply` rather than during it.

- **Region/service availability check (distinct from quota):**
  ```
  aws ssm get-parameters-by-path --path /aws/service/global-infrastructure/regions/<region>/services
  ```
  This is the official programmatic way to check "is service X available in region Y," complementing the static Regional Product Services page already cited in Section 7 of the source document.

- **Missing Terraform data sources** (Section 6.2 of the source document only covers `aws_caller_identity` and `aws_availability_zones`):
  - `data "aws_region"` — current region of a given provider alias
  - `data "aws_regions"` — full list of regions enabled/available for the account

  Both are useful for driving automated checks instead of hardcoding region lists.

---

## 5. Recommendation

Treat the source document as a design-time reference, but add a pipeline-level pre-flight step (Service Quotas + SSM parameter checks above) for any environment that provisions per-region resources with low default ceilings (VPC/EIP/IGW). This is directly relevant here: the repo currently has environments spanning `dev`, `stg`, `prd`, and `shr` tiers plus a new `shr-backup-dr` environment — each additional region added to any of these multiplies exposure to the 5-per-region defaults called out in Section 2.1 of the source document.
