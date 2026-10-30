## 4. Verification Methodology (applies to every region)

This section defines the **shared verification method**: what to check and how to check it. It is a reference checklist, not a results log — actual, region-specific results are recorded in [Section 5, Per-Region Reports](#5-per-region-reports), under the matching sub-section referenced below.

### 4.1 All required AWS services available in each region

| Component | How to verify | Notes |
|---|---|---|
| Service availability | Check the [AWS Regional Services List](https://aws.amazon.com/about-aws/global-infrastructure/regional-product-services/), or run `aws ssm get-parameters-by-path --path /aws/service/global-infrastructure/services` | Some services (Network Firewall, GuardDuty, WAF managed rules) are not available in every region |
| API endpoint availability | Call `aws <service> describe-xxx --region <region>` and confirm it does not return `EndpointConnectionError` / `UnsupportedOperation` | Confirms the endpoint exists and responds |
| Service quota (limits) | `aws service-quotas list-service-quotas --service-code <code> --region <region>` | Default quotas can differ between regions (e.g. number of EIPs or VPCs per region) |
| Feature parity | Compare feature flags and release notes for the service across regions | New features typically launch in us-east-1 first |

### 4.2 VPC, EC2, load balancer, and storage provisioned correctly

| Component | How to verify |
|---|---|
| VPC & Subnet | `describe-vpcs`, `describe-subnets` — correct CIDR, correct number of AZs per design |
| Availability Zones (AZ) | `describe-availability-zones --region <region>` — some regions have only 2 AZs; verify IaC does not hardcode the AZ count |
| Route table / NAT Gateway / IGW | `describe-route-tables`, `describe-nat-gateways` — routing is correct and attached to the right VPC |
| EC2 AMI ID | AMI IDs differ per region — verify IaC looks up the AMI per region (data source) rather than hardcoding the ID |
| EC2 instance type availability | `describe-instance-type-offerings --region <region>` — an instance type may not be available in every region or AZ |
| Load balancer (ALB/NLB) | `describe-load-balancers`, `describe-target-groups` — target health checks report "healthy", listener rules are correct |
| Storage (EBS) | `describe-volumes` — volume type (gp3, io2, etc.) is available in the region, with correct IOPS/throughput |
| Storage (S3) | Bucket is created in the correct region, has a globally unique name, and has correct versioning/encryption settings |
| DNS / Route 53 | Health check and alias record point to the correct resource per region |
| Elastic IP | `describe-addresses` plus a check of the EIP service quota — sufficient quota for NAT Gateway/EC2 in the region |
| Transit Gateway / VPC Peering | `describe-transit-gateways`, `describe-vpc-peering-connections` — attachment and routing are correct; TGW is available in the region |
| ACM (SSL certificate) | `list-certificates --region <region>` — the certificate must be created and validated per region for the ALB HTTPS listener |

### 4.3 Security services active and functioning

| Component | How to verify |
|---|---|
| Security Groups | `describe-security-groups` — inbound/outbound rules match policy |
| IAM roles/policies | IAM is a global service; verify that trust policies and resource ARNs reference the correct region-specific resource |
| KMS | `describe-key` — key is created in the correct region (not cross-region, unless it is a multi-region key); verify the key policy |
| GuardDuty | `get-detector` — detector is enabled individually in each region |
| CloudTrail | Verify the trail logs correctly, whether as a multi-region trail or a per-region trail, per design |
| AWS Config | If used, verify the recorder and rules are active in each region |
| VPC Flow Logs | Verify logging is enabled and points to the correct log destination |
| Secrets Manager / SSM Parameter Store | `list-secrets`, `describe-parameters --region <region>` — secret/parameter exists and replicates correctly per region |
| CloudWatch Alarms | `describe-alarms --region <region>` — alarm is created and in the correct state (not `INSUFFICIENT_DATA`) per region |

### 4.4 WAF Web ACL association

| Component | How to verify |
|---|---|
| Web ACL creation | `list-web-acls --scope REGIONAL --region <region>` — ACL exists with the correct scope |
| Association | `get-web-acl-for-resource --resource-arn <alb-arn>` — ACL is correctly attached to the ALB/API Gateway |
| Rule groups | Verify the AWS Managed Rules are available in that region — not every managed rule exists in every region |
| Logging | Verify the WAF logging destination (Kinesis Data Firehose/S3) is correct for the region |

### 4.5 AWS Network Firewall (NF)

| Component | How to verify |
|---|---|
| Firewall & firewall policy | `describe-firewall`, `describe-firewall-policy` — status is "READY" |
| Rule groups | Verify stateful/stateless rule groups are applied correctly |
| VPC routing | Route table sends traffic through the NF endpoint via the correct subnet/AZ |
| Endpoint availability | Network Firewall is not available in every region — verify availability before enabling |

### 4.6 WAF Geo-restriction (Geo WAF)

| Component | How to verify |
|---|---|
| Geo match rule | Verify the `GeoMatchStatement` rule statement uses the correct country codes |
| Real-world test | Use a VPN/proxy from a blocked country to confirm the request is blocked (HTTP 403) |
| CloudFront vs. Regional | Confirm the correct scope — WAF Geo for CloudFront (global) differs from Regional WAF attached to an ALB |

### 4.7 Common configuration differences to check

- [ ] Instance type not available in a given region
- [ ] AMI ID differences, and how IaC resolves them (lookup vs. hardcoded)
- [ ] Different number of AZs between regions
- [ ] Different default service quotas (EIP, VPC, ENI, etc.)
- [ ] WAF managed rule group not available in a given region
- [ ] Service not available at all in a given region (Network Firewall, GuardDuty, etc.)
- [ ] Significant pricing difference (note if it affects the proposal)
- [ ] Latency/performance difference, if tested

---