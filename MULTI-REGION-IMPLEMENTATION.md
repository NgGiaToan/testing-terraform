# Monitoring & Alerting — Hosted Lighthouse Customer Environments

## Purpose

This document defines the monitoring and alerting standard applied to every hosted Lighthouse customer environment. It covers uptime, remote access (OpenVPN/SSH), performance, application health, backups, security, and cost — what is monitored, the exact trigger conditions, who is notified, and the expected response. Monitoring is deployed automatically at provisioning time and managed as infrastructure as code (Terraform), using the tagging strategy (Customer, Environment, Product, Cost Center, Region) established during provisioning.

**Goal:** detect and respond to issues before customers report them.

## Environment & Customer Identification

Every alert and dashboard identifies the affected environment using the standard provisioning tags:

- **Customer** — customer identifier tag, matches the value used at provisioning
- **Environment** — currently `prod` for all customers
- **Region** — the AWS region the instance is deployed in; this is the key differentiator between customer instances, since environment does not vary
- **Cost Center** — used for cost attribution

## System Overview & Monitored Components

Each customer runs a single-tenant Lighthouse deployment: a dedicated VPC and EC2 instance (built from a Golden AMI) in the Opengear SaaS AWS account, with no shared compute, database, or storage. Web traffic enters through an Application Load Balancer (ALB) protected by AWS WAF. OpenVPN and SSH enter through a Network Load Balancer (NLB). TLS certificates are managed by AWS Certificate Manager (ACM). Regions and ports are set per customer, so every check below uses that customer's configured values. The CloudWatch Agent is already installed on every instance, so CPU, memory, disk, and network error metrics are all live CloudWatch data — not something still to be built.

| Component | What Is Monitored |
| --- | --- |
| Lighthouse EC2 instance | Status checks, CPU, memory, disk, network, monitoring agent |
| Application Load Balancer (ALB) | Target health, 5xx errors, response time |
| AWS WAF | Blocked-request spikes, rate-limit triggers |
| Network Load Balancer (NLB) | Target health, active connections |
| ACM certificates | Days until expiry |
| Daily AMI snapshots | Backup success |
| DNS | Hostname resolution |
| Cost (per customer) | Budget, anomalies, egress |
| Account level | GuardDuty, Security Hub, IAM Access Analyzer, service quotas |

## Monitoring Architecture

Lighthouse instances publish metrics and health data to **Amazon CloudWatch**. CloudWatch alarms evaluate thresholds and notify via **SNS → Slack**. **Grafana** provides consolidated dashboards across all environments, sourced from CloudWatch. AWS Budgets and Cost Anomaly Detection feed into the same alarm/notification pipeline.

```
Lighthouse Instance → CloudWatch → CloudWatch Alarms → SNS → Slack → Support Team
                            ↑                ↑
                       AWS Budgets   Cost Anomaly Detection
                            ↓
                        Grafana Dashboards
```

## Priority, Response & Escalation

| Priority | Customer Impact | Examples | Acknowledge Within | Response Started Within | Initial Owner | Escalation |
| --- | --- | --- | --- | --- | --- | --- |
| **P1 – Critical** | Service unavailable | Instance down, failed health checks, DNS/HTTP failure, no healthy LB targets, certificate about to expire | 5 minutes | 15 minutes | Support Team | Platform Operations → Engineering |
| **P2 – High** | Service degraded, or a limit reached that needs same-day action | CPU/memory/disk at critical level, network errors, slow responses, monitoring agent down, budget at 100% | 30 minutes | 1 hour | Support Team | Engineering |
| **P3 – Medium** | No immediate customer impact | CPU/memory/disk at warning level, budget at 80%, cost anomaly, missed backup, quota at 80% | Next business day | Next business day | Support Team | Normal operational review |

## Monitoring Categories

Each row below follows: **trigger → customer impact → who is notified → what to do.**

### Availability & Uptime

| Metric | Check Frequency & Trigger | Customer Impact | Priority | Notify | Response Action | Why It Matters |
| --- | --- | --- | --- | --- | --- | --- |
| Instance status check | Checked every 1 min; alarms after 5 consecutive minutes of failed status | Cannot access environment | P1 | Support, Platform Ops | Check instance/host status; escalate to Engineering if host-level | Fastest signal that a customer is fully down — nothing else works if this fails |
| HTTP health check | Checked every 1 min; alarms after 3 consecutive failed checks (3 min) | Application unreachable | P1 | Support, Platform Ops | Check app logs, deployment status, LB target health | Instance can be "up" while the application itself has crashed; this catches that gap |
| DNS resolution | Checked every 1 min; alarms after 3 consecutive failures | Cannot reach service by hostname | P1 | Support, Platform Ops | Check DNS records and LB configuration | A DNS/routing issue looks identical to a full outage from the customer's side |
| Load balancer target health | Evaluated every 1 min; alarms if healthy targets \< 3 for 5 consecutive minutes | No healthy backend; app unavailable | P1 | Support, Platform Ops | Check target health and instance availability | LB itself can be healthy while routing to zero working instances |

**Troubleshooting:** `aws ec2 describe-instance-status`, check target group health in EC2 console, review Grafana "Environment Overview" panel. **First mitigation:** restart the affected instance/service; if LB targets are unhealthy, verify recent deploys before restarting. **Known noise:** a single missed check during a scheduled deploy is expected — alarms only fire after 3–5 consecutive failures to avoid false pages.

### Performance

| Metric | Check Frequency & Trigger | Customer Impact | Priority | Notify | Response Action | Why It Matters |
| --- | --- | --- | --- | --- | --- | --- |
| CPU utilisation | Checked every 1 min; Warning >70% = P3, Critical >90% = P2, sustained 15 min | Slower response times | P3 (Warning), P2 (Critical) | Support, Platform Ops | Review CPU metrics and workload demand | Early warning of workload spikes or undersized instances before response times degrade |
| Memory utilisation | Checked every 1 min; Warning >70% = P3, Critical >85% = P2, sustained 15 min | Instability / restarts | P3 (Warning), P2 (Critical) | Support, Platform Ops | Review memory consumption and running processes | Flags leaks or resource exhaustion before the app becomes unstable or restarts |
| Disk utilisation | Checked every 5 min; Warning >80% = P3, Critical >90% = P2, sustained 15 min | Degradation or outage risk | P3 (Warning), P2 (Critical) | Support, Platform Ops | Identify large files; review growth trend | Prevents disk-full conditions that can block application updates or normal operation entirely |
| Network errors | Checked every 1 min via CloudWatch Agent (procstat/netstat metrics); 5xx rate or error count above baseline, sustained 15 min | Slow performance / intermittent outages | P2 | Support, Platform Ops | Check network metrics and infra config | Surfaces connectivity problems or unusual traffic (e.g. high egress) even when compute looks fine |
| Network egress (NetworkOut) | Evaluated every 5 min; above expected range (CloudWatch anomaly detection) for 30 min | Higher AWS cost, possible unusual data transfer | P3 | Support, Platform Ops | Check what is driving traffic (VPC flow logs, ALB/NLB logs); confirm with the customer | Egress spikes are a known cost risk; catching them early limits the bill |

**Troubleshooting:** Grafana "Infrastructure" dashboard; `top` / `htop` on the instance; `df -h` for disk; CloudWatch Logs Insights query filtered by instance ID. **First mitigation:** CPU/memory — restart the service process before restarting the instance; disk — clear temp/log files, then investigate growth trend; network errors — check recent deploys and security group changes. **Known noise:** brief CPU spikes during scheduled deploys or backups are expected and typically self-resolve within 5 minutes; only escalate if sustained past the 15-minute window.

### Application Health

| Metric | Check Frequency & Trigger | Customer Impact | Priority | Notify | Response Action | Why It Matters |
| --- | --- | --- | --- | --- | --- | --- |
| Application health endpoint | Checked every 1 min; alarms after 3 consecutive failed checks (3 min) | Customer-facing feature failure | P1 | Support, Platform Ops | Check app logs and recent deployments | Confirms the Lighthouse application itself is functioning, not just the underlying VM |
| Synthetic monitoring (canaries) | Runs every 5 min; alarms after 2 consecutive failed runs (10 min) | Early warning, pre customer impact | P2 | Support | Review canary results and affected workflow | Catches issues along real user workflows before a customer hits them |

**Troubleshooting:** application logs (CloudWatch Logs), Grafana "Application" dashboard, canary run history in CloudWatch Synthetics console. **First mitigation:** roll back the most recent deployment if the failure correlates with a release; restart the application service otherwise.

### Cost Monitoring

Costs are attributed using the same provisioning tags (Customer, Environment, Product, Cost Center, Region).

| Metric | Check Frequency & Trigger | Customer Impact | Priority | Notify | Response Action | Why It Matters |
| --- | --- | --- | --- | --- | --- | --- |
| AWS budget threshold | Evaluated daily; 80% of monthly budget = P3, 100% = P2 | None immediate | P3 (80%), P2 (100%) | Support, Platform Ops | Investigate spend drivers vs. expected usage | Flags spend trending past the expected budget before it shows up on the invoice |
| Cost anomaly detection | AWS Cost Anomaly Detection runs daily; alerts typically within 1–3 days of anomaly onset (billing data lag) | None immediate | P3 | Support, Platform Ops | Investigate anomalous resource usage and recent changes | Flags spend that deviates from historical patterns (e.g. an egress spike) — often a sign of misconfiguration or a security issue, not just steady growth |

**Troubleshooting:** AWS Cost Explorer filtered by customer tag; Grafana "Cost" dashboard for spend trend and top cost drivers. **First mitigation:** identify the specific resource driving spend (usually egress or an oversized instance); confirm with the customer or recent change log before taking action.

### Remote Access (OpenVPN & SSH via NLB)

| Metric | Check Frequency & Trigger | Customer Impact | Priority | Notify | Response Action | Why It Matters |
| --- | --- | --- | --- | --- | --- | --- |
| NLB target health (OpenVPN) | Evaluated every 1 min; alarms if healthy targets \< 1 for 3 consecutive minutes | No backend for VPN connections | P1 | Support, Platform Ops | Check instance status and OpenVPN service; confirm the health check port matches the customer's port | Confirms the NLB has a working target, not just that the NLB exists |
| Active VPN connections | NLB active flow count evaluated every 5 min; alarms if below expected range (anomaly detection) for 10 min | Devices disconnected | P2 | Support, Platform Ops | Check OpenVPN logs, NLB metrics, and recent port or config changes | A sudden drop can reveal a VPN problem even when port checks pass |

**Troubleshooting:** NLB target group health in the EC2 console; OpenVPN and sshd service status on the instance. **First mitigation:** check for a recent port or allowlist change first; restart the OpenVPN service before restarting the instance.

### Web Access (ALB, WAF & Certificates)

| Metric | Check Frequency & Trigger | Customer Impact | Priority | Notify | Response Action | Why It Matters |
| --- | --- | --- | --- | --- | --- | --- |
| ALB target response time | Evaluated every 1 min; p95 above 2 seconds for 10 consecutive minutes | Slow application | P2 | Support, Platform Ops | Check CPU/memory, recent deploys, target health | Slowness is often the first sign before an outage |
| WAF blocked requests | Evaluated every 5 min; blocked requests above 5x normal for 10 min (any rule group, including rate limiting) | Possible attack, or legitimate traffic blocked | P3 | Support, Platform Ops | Check which WAF rule blocked, source IPs, and the customer IP allowlist; unblock if legitimate | A spike means either an attack or a customer wrongly blocked |
| TLS certificate expiry | Checked daily; Warning \< 30 days = P2, Critical \< 7 days = P1 | Certificate errors; effectively an outage once expired | P2 (Warning), P1 (Critical) | Support, Platform Ops | Check ACM renewal status and the DNS validation record; renew manually if needed | ACM auto-renews about 60 days before expiry, so under 30 days left means renewal is failing |

**Troubleshooting:** WAF sampled requests and metrics in the console; ALB access logs; ACM certificate status. **First mitigation:** add a legitimately blocked customer IP to the WAF IP set; fix the DNS validation record for a failing renewal.

### Backup & Monitoring Agent

The CloudWatch Agent is already deployed to every instance as part of the Golden AMI, publishing memory, disk, and network error metrics. The heartbeat check below exists to catch the agent dying after deployment, not to confirm initial installation.

| Metric | Check Frequency & Trigger | Customer Impact | Priority | Notify | Response Action | Why It Matters |
| --- | --- | --- | --- | --- | --- | --- |
| Daily AMI snapshot | Checked daily; alarms if no successful snapshot in 26 hours (24 h schedule + 2 h grace) | None immediate; recovery point at risk | P3 (P2 if missed 2 days in a row) | Platform Ops | Check backup job errors, IAM permissions, snapshot quota; rerun the job | A backup is only trustworthy if failures are noticed |
| Monitoring agent heartbeat | Evaluated every 5 min; alarms if no memory/disk metrics received for 10 min | None immediate; memory and disk alarms stop working | P2 | Platform Ops | Check the CloudWatch agent service on the instance; restart it; verify the IAM role | Missing data looks like "healthy" unless treated as a failure |

**First mitigation:** `sudo systemctl restart amazon-cloudwatch-agent` for the agent; rerun the failed snapshot job.

### Account-Level Security & Capacity

These apply to the whole AWS account, not one customer. Findings are events, not metrics, so they reach Slack through EventBridge rules rather than metric alarms.

| Metric | Check Frequency & Trigger | Customer Impact | Priority | Notify | Response Action | Why It Matters |
| --- | --- | --- | --- | --- | --- | --- |
| GuardDuty findings | Event-driven, delivered within about 5 min; High severity (7.0+) = P1, Medium (4.0–6.9) = P3 | Possible compromise | P1 (High), P3 (Medium) | Platform Ops, Engineering | Review the finding, identify the affected resource and customer, isolate the instance if compromised | Detects threats that health checks cannot see, such as compromised credentials |
| Security Hub findings | Event-driven; new Critical = P2, new High = P3 | Failing security control | P2 (Critical), P3 (High) | Platform Ops | Review the failed control and assign a fix | Shows drift from the security baseline |
| IAM Access Analyzer | Event-driven; any new finding (public or cross-account access) | Data exposure risk | P2 | Platform Ops | Review the policy and remove access if unintended | Catches overly permissive policies early |
| Service quotas (AWS WAF: web ACLs, rule groups, IP sets, regex pattern sets; VPCs and Elastic IPs are not covered: AWS publishes no usage metric for them) | Alarm period 5 min on the `AWS/Usage` metric; 80% of quota = P3, 95% = P2 | None immediate; new customer provisioning blocked | P3 (80%), P2 (95%) | Platform Ops | Request a quota increase in Service Quotas | Quotas limit onboarding (see modules/alert-delivery/README.md, Quota monitoring) |

**First mitigation:** for a High GuardDuty finding, isolate the instance with a restrictive security group and preserve it for investigation before rebuilding from the Golden AMI.

## Notification Routing

```
CloudWatch Alarm → Amazon SNS → Slack Channel → Support Team
```

Every notification includes: severity, customer, region, alert type, affected service, timestamp, dashboard link.

Account-level alerts (security findings, quotas) have no customer or region field. Security findings and backup failures are events, so they reach the same SNS topics through Amazon EventBridge rules.

## Notification Audience & Access

| Team | Responsibility |
| --- | --- |
| Support Team | Alert triage, initial customer impact assessment |
| Platform Operations | Infrastructure and monitoring platform management |
| Engineering | Escalated investigation and remediation |

A broad, engineering-wide channel receives a simple "something is wrong" signal without customer or region detail. Full platform-health detail (customer identity, region) is limited to Support and Platform Operations.

## Resolution Workflow

1. CloudWatch generates an alert.
2. Notification sent to Slack.
3. Support performs initial triage.
4. Customer impact is assessed.
5. Engineering is engaged if required.
6. Issue is investigated and resolved.
7. Monitoring confirms recovery.

Monitoring provides visibility and alerting; it does not automatically remediate issues.

## Alert Silencing & Scheduled Maintenance

A **maintenance window** here means a scheduled block of time (a start time and an end time, e.g. "Saturday 2:00–2:30 AM") during which planned work happens — it is not related to any operating system.

For planned maintenance or deploys, suppress alerts in advance for that time period, rather than letting the team absorb expected noise:

1. Create a CloudWatch alarm suppression (or Grafana silence) scoped to the specific instance/region tag.
2. Set the suppression to end automatically when the scheduled maintenance period ends — never leave it open-ended, or a real issue after that point could go undetected.
3. Post in the ops Slack channel noting what's silenced and for how long, so no one mistakes a real issue for expected noise.

## Grafana Dashboards

Grafana provides the consolidated view across all customers. CloudWatch remains the source of truth for metrics and alarms; Grafana is for visualisation and investigation. Every dashboard has **Customer** and **Region** filters at the top, populated from the standard provisioning tags, so an operator can view one customer or all of them.

| Dashboard | Purpose | Panels |
| --- | --- | --- |
| Environment Overview | Status, active alerts, uptime, health checks | Uptime % over 24 h / 7 d / 30 d, HTTP/DNS/canary check results |
| Infrastructure | Instance health and capacity | EC2 status checks, CPU, memory, disk used %, network in/out, network errors, CloudWatch agent heartbeat |
| Remote Access | OpenVPN and SSH availability | NLB healthy targets per target group, active VPN connections, new connections per hour |
| Application | Lighthouse application health | Health endpoint status, ALB response time, ALB 5xx rate, healthy targets, synthetic canary results |
| Security & Access | Web protection and certificates | WAF allowed vs blocked requests, blocked requests by rule group, rate-limit triggers, certificate days to expiry per customer |
| Account & Capacity | Account-wide security and limits (not per customer) | GuardDuty findings, Security Hub findings, Access Analyzer findings, WAF quota usage %, last successful AMI snapshot per customer |
| Cost | Per-customer spend | Spend per customer, monthly trend, budget utilisation %, cost anomalies, top cost drivers, network egress |

**Conventions**

- Thresholds are drawn on every panel using the same values as the alarms (for example CPU warning at 70% and critical at 90%), so operators can see how close a metric is to alerting.
- Colours follow priority: red for P1/critical, orange for P2/warning, yellow for P3.
- Every alert message links to the Environment Overview dashboard filtered to the affected customer and region.
- Account & Capacity findings come from AWS event data and have no customer filter.

Grafana auto-discovers resources through the standard provisioning tags (Customer, Region, Product, Cost Center), so a newly provisioned customer appears on the dashboards without manual setup.

## Implementation Notes

- All monitoring, alerting, and cost-tracking resources (CloudWatch metrics/alarms/dashboards, Synthetics canaries, SNS, Slack integration, AWS Budgets) are managed via Terraform, consistent with the existing IaC framework.
- Deployed automatically as part of customer environment provisioning — no manual per-customer setup.