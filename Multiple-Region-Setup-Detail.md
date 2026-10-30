# AWS Supported Region List

## 1. Supported Region List

Regions confirmed and documented in the architecture and infrastructure reference document.

| Region code | Region name | Notes |
|---|---|---|
| | | |

---

## 2. IaC Configuration — Region as Per-Customer Variable

| Item | Status | Reference (repo / PR / commit) | Notes |
|---|---|---|---|
| IaC updated to accept `region` as a per-customer config variable | | | |
| Verified with at least one non-default region | | | |

---

## 3. Provisioning & Validation (per supported region)

| Region | All required AWS services available | VPC / EC2 / LB / storage provisioned correctly | Security services active & functioning | WAF Web ACL association working | Network Firewall (NF) working | Geo WAF (geo-match) working | Additional services (if applicable) | Overall status | Evidence / Notes |
|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | |

---

## 3a. Detailed Verification Checklist (per component)

### 3a.1 All required AWS services available in each region

| Thành phần | Cách verify | Ghi chú |
|---|---|---|
| Service availability | Check [AWS Regional Services List](https://aws.amazon.com/about-aws/global-infrastructure/regional-product-services/) hoặc `aws ssm get-parameters-by-path --path /aws/service/global-infrastructure/services` | Một số service (Network Firewall, GuardDuty, WAF managed rules) không có ở tất cả region |
| API endpoint availability | Gọi thử `aws <service> describe-xxx --region <region>` không lỗi `EndpointConnectionError` / `UnsupportedOperation` | Xác nhận endpoint tồn tại và phản hồi |
| Service quota (limits) | `aws service-quotas list-service-quotas --service-code <code> --region <region>` | Quota mặc định có thể khác nhau giữa region (VD: số EIP, số VPC/region) |
| Feature parity | So sánh feature flag / release notes của service giữa các region | Feature mới thường launch trước ở us-east-1 |

### 3a.2 VPC, EC2, Load Balancer, Storage provisioned correctly

| Thành phần | Cách verify |
|---|---|
| VPC & Subnet | `describe-vpcs`, `describe-subnets` — đúng CIDR, đúng số AZ theo thiết kế |
| Availability Zones (AZ) | `describe-availability-zones --region <region>` — một số region chỉ có 2 AZ, verify IaC không hardcode số AZ |
| Route table / NAT Gateway / IGW | `describe-route-tables`, `describe-nat-gateways` — routing đúng, attach đúng VPC |
| EC2 AMI ID | AMI ID khác nhau theo region — verify IaC lookup AMI theo region (data source), không hardcode ID |
| EC2 instance type availability | `describe-instance-type-offerings --region <region>` — instance type có thể không có ở mọi region/AZ |
| Load Balancer (ALB/NLB) | `describe-load-balancers`, `describe-target-groups` — target health check "healthy", listener rule đúng |
| Storage (EBS) | `describe-volumes` — volume type (gp3, io2...) available theo region, IOPS/throughput đúng |
| Storage (S3) | Bucket tạo đúng region, tên global-unique, versioning/encryption đúng |
| DNS / Route53 | Health check, alias record trỏ đúng resource theo region |
| Elastic IP | `describe-addresses` + check service quota EIP — đủ quota cho NAT Gateway/EC2 theo region |
| Transit Gateway / VPC Peering | `describe-transit-gateways`, `describe-vpc-peering-connections` — attachment/route đúng, TGW có sẵn ở region |
| ACM (SSL certificate) | `list-certificates --region <region>` — certificate tạo/validate riêng ở từng region cho ALB HTTPS listener |

### 3a.3 Security services active and functioning

| Thành phần | Cách verify |
|---|---|
| Security Groups | `describe-security-groups` — rule inbound/outbound đúng theo policy |
| IAM Roles/Policies | IAM là global, verify trust policy và resource ARN có đúng region-specific resource không |
| KMS | `describe-key` — key tạo đúng region (không cross-region trừ multi-region key), verify key policy |
| GuardDuty | `get-detector` — detector enable riêng lẻ ở từng region |
| CloudTrail | Verify trail ghi log đúng, multi-region trail hoặc trail riêng theo thiết kế |
| AWS Config | Nếu dùng — verify recorder + rules active ở từng region |
| VPC Flow Logs | Verify enable và log group đích đúng |
| Secrets Manager / SSM Parameter Store | `list-secrets`, `describe-parameters --region <region>` — secret/parameter tồn tại và replicate đúng ở từng region |
| CloudWatch Alarms | `describe-alarms --region <region>` — alarm tạo và trạng thái đúng (không ở `INSUFFICIENT_DATA`) ở từng region |

### 3a.4 WAF Web ACL association

| Thành phần | Cách verify |
|---|---|
| Web ACL creation | `list-web-acls --scope REGIONAL --region <region>` — ACL tồn tại đúng scope |
| Association | `get-web-acl-for-resource --resource-arn <alb-arn>` — ACL gắn đúng vào ALB/API Gateway |
| Rule groups | Verify AWS Managed Rules có sẵn ở region đó — không phải rule nào cũng có ở mọi region |
| Logging | Verify WAF logging destination (Kinesis Firehose/S3) đúng region |

### 3a.5 AWS Network Firewall (NF)

| Thành phần | Cách verify |
|---|---|
| Firewall & Firewall Policy | `describe-firewall`, `describe-firewall-policy` — status "READY" |
| Rule groups | Verify stateful/stateless rule group áp dụng đúng |
| VPC routing | Route table trỏ traffic qua NF endpoint đúng subnet/AZ |
| Endpoint availability | Network Firewall không có ở tất cả region — verify trước khi enable |

### 3a.6 WAF Geo-restriction (Geo WAF)

| Thành phần | Cách verify |
|---|---|
| Geo match rule | Verify rule statement `GeoMatchStatement` với country code đúng |
| Test thực tế | Dùng VPN/proxy từ quốc gia bị chặn để test request bị block (403) |
| CloudFront vs Regional | Xác định đúng scope — WAF Geo cho CloudFront (global) khác với WAF Regional gắn ALB |

---

## 3b. Verification Results (record actual results here)

Legend: ✅ Pass &nbsp; ⚠️ Pass with limitation &nbsp; ❌ Fail / Not available &nbsp; ➖ N/A

### Verified by / Date (per region)

| Region | Verified by | Date |
|---|---|---|
| Region A | | |
| Region B | | |
| Region C | | |

### 3b.1 Service availability

| Thành phần | Region A | Region B | Region C | Evidence / Notes |
|---|---|---|---|---|
| Service availability | | | | |
| API endpoint availability | | | | |
| Service quota (limits) | | | | |
| Feature parity | | | | |

### 3b.2 VPC / EC2 / Load Balancer / Storage

| Thành phần | Region A | Region B | Region C | Evidence / Notes |
|---|---|---|---|---|
| VPC & Subnet | | | | |
| Availability Zones (AZ) | | | | |
| Route table / NAT Gateway / IGW | | | | |
| EC2 AMI ID | | | | |
| EC2 instance type availability | | | | |
| Load Balancer (ALB/NLB) | | | | |
| Storage (EBS) | | | | |
| Storage (S3) | | | | |
| DNS / Route53 | | | | |
| Elastic IP | | | | |
| Transit Gateway / VPC Peering | | | | |
| ACM (SSL certificate) | | | | |

### 3b.3 Security services

| Thành phần | Region A | Region B | Region C | Evidence / Notes |
|---|---|---|---|---|
| Security Groups | | | | |
| IAM Roles/Policies | | | | |
| KMS | | | | |
| GuardDuty | | | | |
| CloudTrail | | | | |
| AWS Config | | | | |
| VPC Flow Logs | | | | |
| Secrets Manager / SSM Parameter Store | | | | |
| CloudWatch Alarms | | | | |

### 3b.4 WAF Web ACL association

| Thành phần | Region A | Region B | Region C | Evidence / Notes |
|---|---|---|---|---|
| Web ACL creation | | | | |
| Association | | | | |
| Rule groups | | | | |
| Logging | | | | |

### 3b.5 Network Firewall (NF)

| Thành phần | Region A | Region B | Region C | Evidence / Notes |
|---|---|---|---|---|
| Firewall & Firewall Policy | | | | |
| Rule groups | | | | |
| VPC routing | | | | |
| Endpoint availability | | | | |

### 3b.6 WAF Geo-restriction (Geo WAF)

| Thành phần | Region A | Region B | Region C | Evidence / Notes |
|---|---|---|---|---|
| Geo match rule | | | | |
| Test thực tế | | | | |
| CloudFront vs Regional | | | | |

---

## 4. Region-Specific Configuration Differences

| Region | Configuration item | Difference identified | Documented (Y/N) | Reference / Link |
|---|---|---|---|---|
| | | | | |

### 4a. Common Differences Checklist

- [ ] Instance type không available ở region nào
- [ ] AMI ID khác nhau — cách IaC resolve (lookup vs hardcode)
- [ ] Số lượng AZ khác nhau giữa các region
- [ ] Service quota mặc định khác nhau (EIP, VPC, ENI...)
- [ ] Managed rule group WAF không available ở region nào
- [ ] Service hoàn toàn không có ở region (Network Firewall, GuardDuty...)
- [ ] Pricing khác biệt đáng kể (note nếu ảnh hưởng proposal)
- [ ] Latency/performance khác biệt nếu có test

---

## 5. Service-to-Region Support Matrix

Service-to-region support matrix documented, detailing the support level of each AWS service used, per region. Chi tiết hóa cho mục 4.

Legend: ✅ Fully supported &nbsp; ⚠️ Partial / limited &nbsp; ❌ Not available &nbsp; 🌐 Global service

> Quy trình sử dụng: điền cột **Region A/B/C** bằng giá trị **declared/expected** (tra từ [AWS Regional Services List](https://aws.amazon.com/about-aws/global-infrastructure/regional-product-services/) hoặc docs) TRƯỚC khi verify. Sau khi verify thực tế (điền kết quả vào các bảng mục 3b), nếu kết quả actual khác với declared thì cập nhật lại giá trị ở đây và ghi rõ trong cột Notes.

| # | Service / Component | Region A | Region B | Region C | Reference (docs link) | Notes |
|---|---|---|---|---|---|---|
| 1 | VPC (incl. Subnet, Route table) | | | | | |
| 2 | Availability Zones (số lượng AZ) | | | | | |
| 3 | NAT Gateway / Internet Gateway | | | | | |
| 4 | EC2 (AMI availability) | | | | | |
| 5 | EC2 Instance Types (theo type đang dùng) | | | | | |
| 6 | Elastic Load Balancing (ALB / NLB) | | | | | |
| 7 | EBS (volume type: gp3/io2...) | | | | | |
| 8 | S3 | | | | | |
| 9 | Route 53 (DNS / health check) | | | | | |
| 10 | Elastic IP | | | | | |
| 11 | Transit Gateway / VPC Peering | | | | | |
| 12 | ACM (SSL certificate) | | | | | |
| 13 | Security Groups | | | | | |
| 14 | IAM | 🌐 | 🌐 | 🌐 | | Global service |
| 15 | KMS | | | | | |
| 16 | GuardDuty | | | | | |
| 17 | CloudTrail | | | | | |
| 18 | AWS Config | | | | | |
| 19 | VPC Flow Logs (+ CloudWatch Logs/S3 destination) | | | | | |
| 20 | Secrets Manager / SSM Parameter Store | | | | | |
| 21 | CloudWatch Alarms | | | | | |
| 22 | WAF (regional) — Web ACL, managed rule groups | | | | | |
| 23 | WAF Logging (Kinesis Data Firehose) | | | | | |
| 24 | AWS Network Firewall (NF) | | | | | |
| 25 | WAF Geo-match (Geo WAF) | | | | | Ghi rõ scope: Regional hay CloudFront (global) |
