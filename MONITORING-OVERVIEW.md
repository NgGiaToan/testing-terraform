# Monitoring: tổng quan setup

Mô tả từng file và tài nguyên của phần monitoring, cách chúng hoạt động và phụ thuộc nhau.
Viết cho người vận hành và những ai sẽ mở rộng hệ thống này.

> **Trạng thái:** chưa có gì được apply lên AWS hay Grafana, và chưa chạy `terraform validate`
> (provider không tải được trên máy viết ra tài liệu này). Phần "hoạt động thế nào" là theo thiết kế
> của code. Các điểm chưa kiểm chứng nằm ở mục 9. Tình trạng từng alert nằm trong
> [MONITORING-ALERTING-IMPLEMENTATION.md](MONITORING-ALERTING-IMPLEMENTATION.md).

## 1. Bức tranh tổng thể

```text
 ACCOUNT KHÁCH (hàng trăm)                                MANAGEMENT ACCOUNT (mỗi môi trường và region một bộ)
 ┌───────────────────────────────────────┐   publish    ┌────────────────────────────────────────────────────┐
 │ module customer-monitoring            │ ───────────► │ module alert-delivery (qua shr-monitoring)        │
 │  - tối đa 22 loại alarm CloudWatch    │ (alarm_actions)│  - SNS topic P1/P2/P3 (policy: mọi account,      │
 │  - agent CloudWatch (SSM + quyền)     │              │    giới hạn theo tên alarm)                        │
 │  - (tag chi phí trên resource)        │              │  - alert delivery Lambda ──► Slack (2 webhook)          │
 │  - (tùy chọn) role Grafana đọc        │              │  - alarm quota đọc metric AWS/Usage (không Lambda)  │
 └───────────────────────────────────────┘              │  - alarm dùng chung: firewall, quota, Lambda, SNS  │
                                                        │  - (tạm tắt) heartbeat Grafana            │
                                                        │  - (tùy chọn) role Grafana đọc CloudWatch          │
                                                        └───────────────▲──────────────┬─────────────────────┘
                                          heartbeat (tạm tắt)             │              │ đọc metric (Lambda, SNS)
                                                        ┌───────────────┴──────────────▼─────────────────────┐
                                                        │ GRAFANA CLOUD (environment/grafana-alerting)        │
                                                        │  - luật theo dõi đường giao tin ──► Slack          │
                                                        │  - (tạm tắt) luật và heartbeat                 │
                                                        │  - 6 dashboard (repo graham-infrastructure)        │
                                                        └─────────────────────────────────────────────────────┘
```

**Hiện tại cả hai khối (khách và management) nằm trong cùng một account.** Tên "account khách" và
"management account" trong tài liệu chỉ phân biệt vai trò (module nào dựng gì), không phải hai account
khác nhau. Grafana đọc CloudWatch của account này và chọn khách theo tag.

Ba ý chính:
- **Account khách không có SNS topic nào.** Mọi alarm đẩy thẳng vào topic của management, nên thêm
  khách mới không phải sửa gì ở phía management.
- **Alert của khách chạy trên CloudWatch, SNS, Lambda**, độc lập với Grafana, và tên khách nằm sẵn
  trong tên alarm và mô tả JSON do Terraform ghi.
- **Hai chiều theo dõi lẫn nhau:** Grafana báo khi SNS, Lambda hỏng; SNS, Lambda báo khi Grafana
  ngừng gửi heartbeat.

## 2. Cây thư mục

```text
environment/
  shr-monitoring/main.tf            # dựng phía management (admin apply tay)
  grafana-datasources/              # Grafana đọc CloudWatch: data source từng khách và management (API Grafana)
     main.tf variables.tf datasource.tf outputs.tf README.md terraform.tfvars.example
  grafana-alerting/                 # Grafana theo dõi đường giao tin: luật, heartbeat (API Grafana, làm sau)
     main.tf variables.tf datasource.tf contact-points.tf rules.tf README.md terraform.tfvars.example
  dev-cus0001/ stg-customer/ prd-customer/
     main.tf  variables.tf  monitoring.tf    # dựng phía khách
modules/
  alert-delivery/                  # phía management
     main.tf role.tf formatter.tf alarms.tf heartbeat.tf grafana.tf variables.tf outputs.tf
     lambda_src/slack_formatter.py
  customer-monitoring/              # phía khách
     main.tf variables.tf alerts.tf sns.tf alarms-availability.tf alarms-performance.tf
     cloudwatch-agent.tf grafana.tf outputs.tf
     grafana-dashboards/*.json      # 6 dashboard (bản bàn giao; nguồn chính ở graham-infrastructure)
```

## 3. Phía management

### 3.1 [environment/shr-monitoring/main.tf](environment/shr-monitoring/main.tf)
Môi trường do admin apply tay. **Một lần apply là một môi trường trong một region**: bạn truyền
`environment` (dev, stg, prd, hoặc tên đầy đủ) và `region`, và không có vòng lặp nào qua môi trường
hay region. Mỗi deployment cần state riêng: dùng **workspace tên `<môi trường>-<region>`** (cùng một
key backend S3). Resource `workspace_guard`, vốn từ chối plan nếu workspace không đúng tên đó, đang **comment**
(bạn tự chọn đúng workspace): chọn nhầm workspace là ghi đè state của môi trường hay region khác.

```text
terraform workspace new prd-us-east-1        # lần đầu; sau đó: terraform workspace select
terraform apply -var environment=prd -var region=us-east-1
```

Gồm khối `terraform` (backend S3 với `use_lockfile`), `provider "aws"` theo `var.region`,
**10 biến**, một lần gọi module `alert_delivery`, các output (gồm hai công tắc heartbeat).

Module này trước đây tên `alert-formatter`, nay là `alert-delivery` vì Lambda định dạng tin chỉ là một phần của nó (cùng topic, policy và alarm của đường giao tin). Khối `moved` (`module.alert_formatter` sang `module.alert_delivery`) giữ nguyên state của deployment đã apply. Tên Lambda, role và file `formatter.tf` chưa đổi.

| Biến | Ý nghĩa |
| --- | --- |
| `environment` | Môi trường deployment này phục vụ: 1 đến 13 ký tự (chữ thường, số, gạch ngang). Có Lambda, role, secret và topic riêng |
| `region` | Region đặt Lambda và topic. **Bắt buộc, không có mặc định**. Alarm của khách chỉ publish được vào topic cùng region |
| `grafana_heartbeat_enabled` | Tạo topic heartbeat. Bật **trước**, và chỉ ở **một** deployment (tên topic không có môi trường). Quyền publish cho Grafana đang comment: role của Grafana nằm ở `environment/shr-grafana-federation` |
| `grafana_heartbeat_alarm_enabled` | Tạo alarm "Grafana ngừng gửi heartbeat". Bật **sau**, khi tin đã đến |
| `slack_webhook_secret_arn` | Secret chứa URL webhook của môi trường này. `null` thì module tự tạo secret rỗng `lighthouse-alerting-<môi trường>-<region>-slack-webhooks` |
| `network_firewall_name`, `network_firewall_availability_zones` | Bật alarm firewall dùng chung |
| `dashboard_url` | Link Grafana Platform trong alert của management |
| ~~`grafana_user_enabled`~~ (**đã comment**) | IAM user chỉ-đọc với access key. Đã thay bằng federation (`grafana_azure_*`) |
| (đã chuyển) `grafana_azure_*` | Ba biến này nay thuộc stack riêng `environment/shr-grafana-federation` (xem mục 5.0), không còn ở `shr-monitoring` |
| ~~`grafana_account_id`~~ (**đã comment**, đường role theo account không dùng) | Bật role Grafana assume. Đã thay bằng federation (`grafana_azure_*`) |

Output: `slack_webhook_secret_arn` (đặt URL vào đâu), `formatter_lambda_arn`
(chỉ để tham khảo), `alert_topic_arns`... (và `grafana_heartbeat_topic_arn`),
`alert_topic_arns`, `management_account_id` (khách cần).

### 3.2 [modules/alert-delivery/main.tf](modules/alert-delivery/main.tf)
Không tạo tài nguyên, chỉ dựng nền:
- `data aws_caller_identity`: ID account hiện tại.
- `locals`: `shared_prefix = "lighthouse-alerting"` (cố định; khách và stack Grafana dựng tên từ
  đây), `name_prefix = <shared_prefix>-<môi trường>-<region>` (tên Lambda, role, secret, topic của
  deployment này), `priorities` (P1, P2, P3), `tags`.
- **Danh mục alert của management (7 mục):** `firewall-drops` (P3), `quota-80` (P3), `quota-95`
  (P2) gửi cả Operations và Engineering; `sns-failures`, `grafana-heartbeat`, `lambda-errors`,
  `lambda-throttles` (P2) gửi Engineering.
- `alarm_names` (dạng `shared-<priority>-<môi trường>-<key>`; chữ `shared-` đứng chỗ mã khách để
  tên khớp policy của topic `*-P1-*`) và `alarm_descriptions` (JSON: priority, customer = "shared",
  environment = "management-<môi trường>", alert_type, service, condition, dashboard_url, notify).
  Lambda đọc JSON này để dựng tin.

### 3.3 [role.tf](modules/alert-delivery/role.tf) (4 tài nguyên)
| Tài nguyên | Ý nghĩa |
| --- | --- |
| `data lambda_assume` | Trust policy: chỉ `lambda.amazonaws.com` được mặc role. Dùng cho role của Lambda formatter |
| `aws_iam_role.formatter` | Role của alert delivery Lambda, tên `lighthouse-alerting-<môi trường>-<region>-formatter` (IAM là toàn cầu nên tên có region) |
| `data aws_iam_policy_document.formatter` | Hai quyền: đọc secret webhook (`secretsmanager:GetSecretValue`, chỉ đúng secret đó) và ghi log (chỉ đúng log group) |
| `aws_iam_role_policy.formatter` | Gắn quyền vào role |

### 3.4 [formatter.tf](modules/alert-delivery/formatter.tf) (11 mục)
| Tài nguyên | Ý nghĩa |
| --- | --- |
| `data archive_file.formatter` | Nén `slack_formatter.py` thành zip; hash của file làm Terraform redeploy khi code đổi |
| `aws_secretsmanager_secret.slack_webhooks` (khi `slack_webhook_secret_arn` là `null`) | Secret **rỗng** `lighthouse-alerting-<môi trường>-<region>-slack-webhooks`, mỗi deployment một secret, chỉ Lambda của nó đọc. URL đặt tay bằng CLI nên không vào state |
| `local.slack_webhook_secret_arn` | ARN của secret được dùng (tự tạo hoặc truyền vào) |
| `aws_cloudwatch_log_group.formatter` | Log của Lambda, giữ 30 ngày |
| `aws_lambda_function.formatter` | Lambda `lighthouse-alerting-<môi trường>-<region>-formatter`, Python 3.12, timeout 15 giây, handler `slack_formatter.handler`, biến môi trường `SLACK_WEBHOOK_SECRET_ARN`, không nằm trong VPC |
| `aws_lambda_permission.own_topics` (x3) | Cho đúng 3 topic P1/P2/P3 gọi Lambda |
| `aws_sns_topic.alerts` (x3) | Topic `lighthouse-alerting-<môi trường>-<region>-alerts-p1/p2/p3`, **không mã hóa bằng khóa riêng**. Nơi alarm của các môi trường khách nối vào deployment này publish |
| `data alerts_topic` + `aws_sns_topic_policy.alerts` (x3) | **Ba** câu lệnh: `AllowAccountOwner` (`Publish`, `ListSubscriptionsByTopic`, `GetTopicAttributes`, chỉ yêu cầu từ account này); `AllowSubscribeFormatterOnly` (`Subscribe`, chỉ giao thức `lambda` và chỉ endpoint là đúng alert delivery Lambda này); và `AllowAlarmsFromAnyAccount` (chỉ `Publish`, chỉ do dịch vụ CloudWatch, chỉ alarm ở region này, tên khớp priority: topic P1 nhận `*-P1-*`, P2 nhận `*-P2-*`, P3 nhận `*-P3-*`). Policy **không kiểm tra môi trường** |
| `aws_sns_topic_subscription.alerts_formatter` (x3) | Đăng ký Lambda vào từng topic |
| `aws_sns_topic.pipeline` | Topic `lighthouse-alerting-<môi trường>-<region>-pipeline` nhận các alarm theo dõi hệ thống alert. **Không có subscriber** |

### 3.5 [alarms.tf](modules/alert-delivery/alarms.tf) (17 mục)
| Tài nguyên | Ý nghĩa |
| --- | --- |
| `local.alarm_actions` | Mỗi alert publish vào topic đúng priority |
| `local.firewall_metrics` | Tổ hợp (AZ x engine Stateful/Stateless) cho metric math, tối đa 4 AZ (CloudWatch cho 10 metric mỗi alarm) |
| `aws_cloudwatch_metric_alarm.firewall_drops` | P3. Cộng `DroppedPackets` mọi AZ và engine (hàm `FILL` giữ tổng khi một vùng im lặng), so với **khoảng bình thường** (độ rộng 3); 2/2 chu kỳ 5 phút. Chỉ tạo khi có tên firewall và AZ |
| `quota_warning`, `quota_critical` (mỗi quota một cặp) | metric math `ResourceCount` (`AWS/Usage`) / giới hạn x 100 > 80 (P3) và > 95 (P2), Maximum 5 phút, 1/1. Giới hạn là `SERVICE_QUOTA()` nếu quota không khai `limit`, hoặc số cố định `limit` (WAF không hỗ trợ `SERVICE_QUOTA()`, nên phải sửa `limit` khi quota được nâng). Mặc định 4 quota WAF theo region: web ACL, rule group, IP set (limit 100 mỗi loại) và regex pattern set (limit 10). VPC và Elastic IP **không có** metric `AWS/Usage`, ALB/NLB chưa xác nhận, nên chưa theo dõi được nếu không dùng Lambda. **Chưa xác minh** chiều của metric WAF (chỉ `Resource`) và việc nó có trong account (xem `aws cloudwatch list-metrics --namespace AWS/Usage`) |
| `sns_failures` (x3, mỗi topic một alarm) | P2. `NumberOfNotificationsFailed` ≥ 1: SNS không giao được tới Lambda. Gửi vào topic pipeline |
| `lambda_errors`, `lambda_throttles`, `quota_job_errors` | P2. `Errors` hoặc `Throttles` ≥ 1 của hai Lambda. Gửi vào topic pipeline |

Bốn nhóm alarm cuối ghi vào topic pipeline **không ai nhận**, và đã được thay bằng luật Grafana
(mục 5). Chúng chưa được gỡ khỏi code.

### 3.6 [heartbeat.tf](modules/alert-delivery/heartbeat.tf) (5 mục; topic và quyền publish chạy khi bật `grafana_heartbeat_enabled`, alarm khi bật thêm `grafana_heartbeat_alarm_enabled`)

> **Phía AWS đã bật, phía Grafana chưa.** `heartbeat.tf` chạy khi bật `grafana_heartbeat_enabled` (quyền publish cho Grafana đang comment: role nằm ở stack riêng).
> Stack Grafana `grafana-alerting` (gửi heartbeat) vẫn tắt, xem [grafana-alerting/README.md](environment/grafana-alerting/README.md).
Cho chiều "SNS, Lambda biết khi Grafana hỏng".

| Tài nguyên | Ý nghĩa |
| --- | --- |
| `aws_sns_topic.grafana_heartbeat` (khi `grafana_heartbeat_enabled`) | Topic `lighthouse-alerting-grafana-heartbeat` (tên không có môi trường, nên chỉ bật ở **một** deployment). Không cần subscriber: CloudWatch tự đếm số tin gửi vào (`AWS/SNS NumberOfMessagesPublished`) |
| `data` policy + `aws_iam_role_policy.grafana_heartbeat` | Thêm vào **role federation của Grafana** (`grafana.tf`) quyền `sns:Publish` trên **đúng topic này**. Không có access key |
| `aws_cloudwatch_metric_alarm.grafana_heartbeat` (khi cả hai công tắc bật) | P2, gửi Engineering. `NumberOfMessagesPublished` < 1 trong 3 chu kỳ 5 phút liên tiếp (15 phút), thiếu dữ liệu coi là vi phạm. Đi qua topic alert, Lambda, Slack |

Hai công tắc vì topic phải có trước khi Grafana gửi được, còn alarm tạo sớm sẽ báo ngay. Bật alarm
mà chưa bật topic thì Terraform từ chối.

### 3.7 [grafana.tf](modules/alert-delivery/grafana.tf) (**đã chuyển ra stack riêng**; phần còn lại đang comment)
Quyền đọc của Grafana (role federation cho Managed Identity của Azure VM) nay nằm ở `environment/shr-grafana-federation`, vì IAM là toàn cục nên một role cho cả account, không gắn vào deployment theo môi trường và region. File này chỉ còn các cách khác đã comment (role theo account, IAM user với access key).

### 3.8 [variables.tf](modules/alert-delivery/variables.tf) (14 biến) và [outputs.tf](modules/alert-delivery/outputs.tf) (6 output)
Biến: `region`, `environment`, `grafana_heartbeat_enabled`, `grafana_heartbeat_alarm_enabled`, `slack_webhook_secret_arn`, `dashboard_url`,
`network_firewall_name`, `network_firewall_availability_zones` (tối đa 4), `anomaly_band_width`,
`quotas`, `quota_warning_percent` (80), `quota_critical_percent` (95), `tags`.
Output: `formatter_lambda_arn`,
`management_account_id`, `alert_topic_arns`, `pipeline_topic_arn`,
`slack_webhook_secret_arn`, `grafana_heartbeat_topic_arn`.

### 3.9 Hai file Python
**[slack_formatter.py](modules/alert-delivery/lambda_src/slack_formatter.py)**:

| Hàm hoặc hằng | Việc làm |
| --- | --- |
| `_get_webhooks()` | Đọc secret (một lần mỗi container). Phải là JSON có đủ `Operations` và `Engineering`; thiếu thì báo lỗi rõ, không tự chuyển sang channel khác |
| `TEAMS`, `Operations_TEAMS` | Hai team; alert không nêu team (Budgets, Cost Anomaly, alarm không có mô tả) đi vào Operations |
| `_priority_from_topic` | Suy ra priority từ tên topic cho alert không có mô tả |
| `_parse_description`, `_alarm_alert` | Đọc JSON mô tả alarm, dựng tin: Customer, Environment, Region, Service, Alert, Condition, State, Time, Dashboard; tiêu đề có `[môi trường]`; màu theo priority, xanh khi hồi phục |
| `_region_from_arn` | Lấy region từ ARN alarm nếu tin SNS không có |
| `_generic_alert`, `_build_alert` | Chọn dạng tin: alarm hay văn bản tự do |
| `_post_to_slack` | POST bằng `urllib3`, ghi log tiêu đề, mã trạng thái, phản hồi; mã khác 200 thì báo lỗi |
| `_redact` | Che URL webhook (và đường dẫn bí mật) khỏi thông báo lỗi |
| `handler` | Duyệt mọi bản ghi, gửi tới webhook của từng team (trùng URL chỉ gửi một lần), gom lỗi rồi báo sau cùng |

### 3.10 Một account cho mọi khách
Monitoring và mọi khách nằm **cùng một account**, nên CloudWatch của account đó đã có metric của tất cả.
Grafana đọc account này qua role federation (mục 5.0) và chọn khách theo **tag** (`Customer`, `Environment`).
Không có sink hay link CloudWatch cross-account observability (OAM): nếu sau này tách khách ra account riêng
thì cần thêm lại.

## 4. Phía khách

### 4.1 Module [customer-monitoring](modules/customer-monitoring)

**[main.tf](modules/customer-monitoring/main.tf)**: lấy ID account; `common_tags` (Customer,
Environment, Product, CostCenter, Region, ManagedBy); `name_prefix`; và các **cờ bật nhóm alarm**
(`instance_enabled`, `alb_enabled`, `nlb_enabled`, `waf_enabled`, `acm_enabled`,
`https_canary_enabled`, `workflow_canary_enabled`): theo biến `enable_*` nếu có, không thì bật khi
giá trị tương ứng được đặt. Có cờ để dùng được khi tài nguyên tạo trong cùng lần apply.

**[sns.tf](modules/customer-monitoring/sns.tf)**: tính ARN topic của management theo dạng
`arn:aws:sns:<region>:<management_account_id>:<prefix>-<môi trường alert>-<region>-alerts-p1/p2/p3`
(hoặc map ghi đè). **Môi trường alert** suy ra từ `environment` của khách: `dev-*` thành `dev`,
`staging-*` thành `stg`, `prod-*` thành `prd`, tên khác giữ nguyên. Đó là chỗ nối môi trường khách
với deployment `shr-monitoring` cùng tên và cùng region. Thiếu `management_account_id` thì alarm
được tạo không có action. Resource `terraform_data.alert_environment_check` làm plan thất bại nếu
môi trường alert không thể là tên của một deployment (quá 13 ký tự hoặc ký tự không hợp lệ). Nó
**không kiểm tra được deployment có tồn tại không**: phải apply `shr-monitoring` cho môi trường và
region đó trước.

**[alerts.tf](modules/customer-monitoring/alerts.tf)**: **danh mục 22 alert** ở một chỗ duy nhất
(priority, người nhận, nội dung điều kiện viết từ cùng biến với alarm nên không lệch), cùng
`alarm_names` (`<khách>-<priority>-<môi trường alert>-<key>`, ví dụ `acme-P1-prd-https-canary`; có
môi trường để hai môi trường của một khách trong cùng account và region không ghi đè alarm của nhau),
`alarm_descriptions` (JSON, có trường `environment`) và `alarm_actions`.

| Nhóm | Alert (priority, người nhận) |
| --- | --- |
| Availability | `status-check` P1, `https-canary` P1, `alb-healthy` P1, `alb-5xx` P2, `workflow-canary` P2, `ebs-status` P2 (đều Operations) |
| Performance | `cpu-warning` P3, `cpu-critical` P2, `memory-warning` P3, `memory-critical` P2, `disk-warning` P3, `disk-critical` P2, `alb-latency` P2, `alb-request-rate` P3, `network-egress` P3 (Operations); `agent-heartbeat` P2 (Engineering) |
| VPN | `vpn-healthy` P1, `vpn-connections` P2 |
| Web | `waf-blocked` P3, `cert-warning` P2, `cert-critical` P1 |
| Nền tảng | `backup-25h` P1 (Engineering) |

**[alarms-availability.tf](modules/customer-monitoring/alarms-availability.tf)** (11 alarm):

| Alarm | Metric, điều kiện | Khi thiếu dữ liệu |
| --- | --- | --- |
| `status_check` | `StatusCheckFailed` Max 60 s, 3/3 ≥ 1 | bỏ qua |
| `https_canary` | `SuccessPercent` Avg 60 s, 3/3 < 100 | coi là vi phạm |
| `alb_healthy` | `UnHealthyHostCount` Min 60 s, 3/3 ≥ 1 | không vi phạm |
| `alb_5xx` | (5xx đích + 5xx ALB) ÷ số request x 100, chỉ khi ≥ 50 request/phút; 5/5 > 5% | không vi phạm |
| `workflow_canary` | `SuccessPercent` Avg 300 s, 2/2 < 100 | coi là vi phạm |
| `ebs_status` | `StatusCheckFailed_AttachedEBS` Max 60 s, 3/3 ≥ 1 (chỉ Nitro) | bỏ qua |
| `vpn_healthy` | NLB `UnHealthyHostCount` **Max** 60 s, 3/3 ≥ 1 | không vi phạm |
| `vpn_connections` | `ActiveFlowCount` dưới khoảng bình thường, 3/3 | không vi phạm |
| `waf_blocked` | `BlockedRequests` trên khoảng bình thường, 2/2 | không vi phạm |
| `cert_warning`, `cert_critical` | `DaysToExpiry` Min 1 ngày < 30 và < 7 | coi là vi phạm |

**[alarms-performance.tf](modules/customer-monitoring/alarms-performance.tf)** (11 mục):
`cpu_warning` (15/15 > 70 %), `cpu_critical` (10/10 > 90 %), `memory_warning` (15/15 > 70 %),
`memory_critical` (10/10 > 85 %), `disk_warning`/`disk_critical` (3/3 > 80 và 90 %, **mỗi mount
point một cặp**), `alb_latency` (p95 > 0,3 s, 10/10), `alb_request_rate`, `network_egress` (trên
khoảng bình thường), `agent_heartbeat` (mẫu `mem_used_percent` < 1, thiếu dữ liệu thì báo),
`backup` (`SnapshotSucceeded` Sum 1 giờ < 1 trong 25 giờ liên tiếp, mặc định tắt).

**[cloudwatch-agent.tf](modules/customer-monitoring/cloudwatch-agent.tf)** (2 tài nguyên): gắn
`CloudWatchAgentServerPolicy` vào role có sẵn của instance (dùng đúng tên role truyền vào); tạo SSM
parameter `/<environment>/cloudwatch-agent/config` (bộ nhớ và từng mount point, gắn chiều
`InstanceId = ${aws:InstanceId}` nên agent tự biết ID).

**Budget và cost anomaly không nằm ở module này.** Chúng được quản lý tập trung ở [modules/cost-monitoring](modules/cost-monitoring), gọi từ `shr-monitoring` (biến `cost_customers`): mỗi khách một budget tháng lọc theo tag `CostCenter` và một anomaly monitor, gửi vào topic P3 (80%, dự báo, anomaly) và P2 (100%) của deployment. Môi trường khách chỉ gắn tag bằng `default_tags` (`Customer`, `Environment`, `CostCenter`).

**[grafana.tf](modules/customer-monitoring/grafana.tf)** (đã comment, không dùng): role đọc CloudWatch cho
Grafana theo từng khách. Không cần vì mọi khách cùng account với monitoring và Grafana đọc bằng role federation. **[outputs.tf](modules/customer-monitoring/outputs.tf)**:
`alert_topic_arns`, `alarm_names`, `cloudwatch_agent_config_ssm_parameter`.
**[variables.tf](modules/customer-monitoring/variables.tf)**: 48 biến (định danh, gửi alert,
Grafana, tài nguyên cần theo dõi, 7 cờ `enable_*`, ngưỡng, chi phí).

### 4.2 Môi trường khách
`dev-cus0001`, `stg-customer`, `prd-customer` mỗi nơi có ba file: **main.tf** (`terraform` +
backend S3, `provider`, `locals`, bucket S3 và security group mẫu), **variables.tf** (15 biến ở
`dev`, 16 biến ở `stg` và `prd` lúc đầu; nay có thêm biến Grafana (đã comment)), **monitoring.tf** (một lần gọi module). `stg` và `prd` nhận key
state lúc `init` vì dùng chung cho nhiều khách.

## 5. Grafana Cloud

### 5.0 [environment/shr-grafana-federation](environment/shr-grafana-federation/README.md) (stack riêng, một lần cho cả account)
Phía AWS để **Grafana trên Azure VM đọc CloudWatch không dùng access key**: một OIDC provider tin Microsoft Entra ID và một role chỉ-đọc mà chỉ Managed Identity của VM mới assume được (`AssumeRoleWithWebIdentity`). IAM là toàn cục nên chỉ một deployment, một state, không workspace; admin apply tay như `shr-iam`.

| Tệp | Nội dung |
| --- | --- |
| `main.tf` | Terraform ≥ 1.10, backend S3 riêng (`shr-grafana-federation/terraform.tfstate`), provider AWS |
| `variables.tf` | `grafana_azure_tenant_id`, `grafana_azure_audience`, `grafana_azure_subject` (đều bắt buộc, kiểm tra dạng GUID), `region`, `role_name` |
| `federation.tf` | OIDC provider, trust (điều kiện `aud` và `sub`), role `lighthouse-alerting-grafana-federated`, policy chỉ-đọc |
| `outputs.tf` | `grafana_federated_role_arn` (giá trị `AWS_ROLE_ARN` cho tiến trình Grafana), `oidc_provider_arn` |
| `terraform.tfvars.example` | Mẫu ba giá trị (không bí mật) |

### 5.1 Grafana đọc CloudWatch: [environment/grafana-datasources](environment/grafana-datasources)
Bước Grafana **đầu tiên và duy nhất cần để đọc CloudWatch**. Grafana Cloud không nạp bằng file cấu hình,
nên đây là Terraform với provider `grafana/grafana`, dùng token của service account; stack không cần
thông tin đăng nhập AWS (trừ bucket state). Nó không tạo tài nguyên AWS: các role chỉ-đọc mà data source
dùng được tạo ở account khách (`modules/customer-monitoring`) và management (`modules/alert-delivery`).

| File | Tài nguyên | Ý nghĩa |
| --- | --- | --- |
| `main.tf` | `provider "grafana"`, backend S3 (key `grafana-datasources/...`) | Kết nối bằng `grafana_url` và `grafana_token` |
| `datasource.tf` | `grafana_data_source.customer` | **Một data source CloudWatch cho mỗi khách** trong biến `customers`, assume role `<environment>-monitoring-grafana-read` của account khách. Dashboard liệt kê chúng trong ô **Customer** |
| | `grafana_data_source.cloudwatch_management` | Data source của management (uid `lighthouse-cw-management`), **chỉ khi** có `management_grafana_role_arn` |
| `variables.tf` | 6 biến | `grafana_url`, `grafana_token` (bí mật), `customers`, `management_grafana_role_arn` (tùy chọn), `region`, `authentication_provider` (mặc định **`default` = AWS SDK Default**: Grafana tự chạy dùng danh tính AWS của máy chủ để assume role; `grafana_assume_role` chỉ cho Grafana Cloud), |
| `outputs.tf` | 2 output | Danh sách data source của khách và uid của data source management |

Stack này chỉ dành cho **đường role** (đã comment ở phía AWS), không dùng với federation: data source tạo tay trên giao diện. Chi tiết và các điểm chưa kiểm chứng nằm trong
[README](environment/grafana-datasources/README.md) của stack.

### 5.2 Grafana theo dõi đường giao tin: [environment/grafana-alerting](environment/grafana-alerting) (**tạm tắt, toàn bộ đang comment**)

> **Tạm tắt.** `contact-points.tf`, `rules.tf`, `datasource.tf` và phần lớn `variables.tf` đã nằm trong
> `/* ... */` vì chưa cần Grafana theo dõi đường giao tin. Stack chỉ còn provider và hai biến `grafana_url`,
> `grafana_token`. Bảng dưới mô tả phần đã comment, để bật lại khi cần.

Grafana Cloud **không nạp bằng file cấu hình**, nên đây là Terraform với provider
`grafana/grafana`, dùng token của service account.

| File | Tài nguyên | Ý nghĩa |
| --- | --- | --- |
| `main.tf` | `provider "grafana"` | Kết nối bằng `grafana_url` và `grafana_token` |
| `datasource.tf` | `grafana_folder.lighthouse` | Thư mục chứa luật. Data source **không** tạo ở đây: xem `environment/grafana-datasources`, apply trước |
| `contact-points.tf` (comment) | `grafana_contact_point.heartbeat` | Contact point SNS gửi heartbeat vào topic AWS, dùng khóa truy cập của IAM user |
| `rules.tf` | `grafana_rule_group.pipeline_health` | **Luật theo từng môi trường** trong `alert_environments` (mặc định dev, stg, prd): với mỗi môi trường có alert delivery Lambda lỗi, alert delivery Lambda bị throttle, và giao tin thất bại của topic P1, P2, P3 (5 luật mỗi môi trường). Mặc định là 15 luật. Môi trường chưa được deploy không có metric, và "không có dữ liệu" được coi là bình thường, nên **không báo gì**. Mỗi luật: `Sum` > 0 trong 10 phút gần nhất, gửi vào contact point Slack **có sẵn** qua cài đặt theo từng luật (không đụng cây notification policy) |
| (comment) | `grafana_rule_group.heartbeat` | **1 luật luôn bật**; thông báo của nó (lặp mỗi 5 phút) chính là heartbeat |
| `variables.tf` | 11 biến (**chỉ còn `grafana_url` và `grafana_token` đang chạy**, chín biến còn lại đã comment) | `grafana_url`, `grafana_token` (bí mật), `region`, `name_prefix`, `alert_environments` (môi trường có deployment, mặc định dev, stg, prd), `management_data_source_uid` (uid data source management, mặc định `lighthouse-cw-management`), `slack_contact_point_name`, `heartbeat_topic_arn`, `heartbeat_access_key`, `heartbeat_secret_key` (bí mật) |

### 5.3 Dashboard (quản lý ở repo graham-infrastructure)

Sáu file dưới đây là **bản bàn giao**; repo `graham-infrastructure` quản lý dashboard. **Dashboard
mới được thêm vào `graham-infrastructure`**, không thêm ở đây. Chi tiết về data source cần có và các
giá trị phải bàn giao nằm trong [grafana-dashboards/README.md](modules/customer-monitoring/grafana-dashboards/README.md).

| File | Panel |
| --- | --- |
| [env-overview.json](modules/customer-monitoring/grafana-dashboards/env-overview.json) | 5: uptime 24 giờ, 7 ngày, 30 ngày, canary HTTPS, canary workflow |
| [infrastructure.json](modules/customer-monitoring/grafana-dashboards/infrastructure.json) | 14: status check, CPU, bộ nhớ, đĩa, đọc/ghi đĩa (instance và volume), mạng, heartbeat agent |
| [remote-access.json](modules/customer-monitoring/grafana-dashboards/remote-access.json) | 3: target khỏe, kết nối VPN, kết nối mới mỗi giờ (chọn được nhiều target group OpenVPN) |
| [application.json](modules/customer-monitoring/grafana-dashboards/application.json) | 6: canary, p95, request rate, 5xx, target khỏe, canary workflow |
| [web-protection.json](modules/customer-monitoring/grafana-dashboards/web-protection.json) | 4: WAF cho phép và chặn, chặn theo rule, firewall, ngày còn lại của certificate |
| [platform.json](modules/customer-monitoring/grafana-dashboards/platform.json) | 5: quota, snapshot, lỗi và throttle của Lambda, lỗi giao SNS (data source management) |

Ngưỡng alarm được vẽ lên panel, màu theo priority (đỏ P1, cam P2, vàng P3). Dropdown **Customer**
chọn data source CloudWatch của khách.

## 6. Ba đường cảnh báo
1. **Alert của khách (đường chính):** metric vượt ngưỡng, alarm ở account khách đổi trạng thái,
   publish vào topic P1, P2, P3 ở management (policy cho phép theo tên alarm), topic gọi Lambda,
   Lambda đọc secret rồi gửi tới webhook của team trong `notify`.
2. **Grafana báo khi đường chính hỏng:** luật đọc metric Lambda và SNS của management, gửi Slack
   bằng contact point của Grafana.
3. **Đường chính báo khi Grafana hỏng:** luật luôn bật gửi heartbeat mỗi 5 phút vào topic heartbeat;
   khi 15 phút không có tin, alarm `grafana-heartbeat` kích hoạt và đi qua đường chính tới Slack.

## 7. Thứ tự apply lần đầu
1. Tạo hai webhook Slack (Operations, Engineering) và thử từng URL.
2. Apply `environment/shr-monitoring` **cho từng môi trường và region có khách** (ví dụ dev, stg và
   prd ở `us-east-1`), mỗi lần một workspace `<môi trường>-<region>` (Terraform tạo secret rỗng,
   Lambda, topic riêng). Bật heartbeat và role Grafana ở **một** deployment mỗi region.
3. Đặt URL vào **từng** secret bằng CLI (JSON có đủ hai team). Mỗi deployment một secret.
4. Apply môi trường khách với `management_account_id` (dev trước). Môi trường alert của khách (dev,
   stg, prd) phải có deployment ở bước 2, cùng region. Rồi thử bằng `aws cloudwatch set-alarm-state`.
5. **Grafana đọc CloudWatch:** apply stack riêng `environment/shr-grafana-federation` (ba giá trị Azure), cấu hình VM Azure (token,
   `AWS_ROLE_ARN`) và tạo data source CloudWatch trên giao diện (AWS SDK Default).
6. Đưa dashboard vào Grafana qua repo `graham-infrastructure` (chúng liệt kê các data source ở bước 5).
7. **Heartbeat:** topic phía AWS có sẵn (`grafana_heartbeat_enabled`); quyền publish cho Grafana đang comment (role ở stack riêng, cần thêm vào đó khi bật). Phần Grafana theo dõi đường giao tin (`environment/grafana-alerting`) **vẫn tắt (code đã comment)**: khi bật thì apply
   stack đó, chờ heartbeat đến, rồi bật `grafana_heartbeat_alarm_enabled` (xem `environment/grafana-alerting/README.md`).

## 8. Khi có khách mới
Chỉ cần chạy môi trường của khách (module monitoring) với `management_account_id` và các ID tài
nguyên của họ:
- Alarm được tạo trong account khách, mang sẵn mã khách và `notify`.
- Alarm publish vào topic của management; policy cho phép mọi account, **không thêm account vào đâu**.
- Lambda dựng tin có tên khách và gửi đúng team.

Phía management, Lambda và Slack không phải sửa gì. Ba trường hợp cần làm thêm:

| Trường hợp | Việc cần |
| --- | --- |
| Khách ở môi trường hoặc region mà management chưa có deployment | Chạy `environment/shr-monitoring` cho cặp (môi trường, region) đó, với workspace `<môi trường>-<region>`. Nếu chưa làm, alarm của khách trỏ tới topic không tồn tại và **không báo gì, cũng không có lỗi apply** |
| ID tài nguyên (instance, ALB, NLB...) chưa có trong môi trường khách | Tạo cùng lần apply thì truyền thuộc tính kèm cờ `enable_*`; tạo nơi khác thì CI đưa giá trị vào |
| Dashboard Grafana cho khách | Gắn tag `Customer` và `Environment` lên resource của khách (`default_tags`). Data source không phải sửa, dashboard chọn khách theo tag. Alert không cần việc này |

## 9. Điều chưa kiểm chứng và giới hạn
- **Chưa chạy trên AWS, chưa chạy Grafana, chưa `terraform validate`.** Stack Grafana viết theo tài
  liệu và **chưa được kiểm tra gì cả**.
- **Chưa kiểm chứng:** alarm của account khác có publish được vào topic với policy này không; alarm
  và topic có bắt buộc cùng region không; contact point SNS của Grafana có chạy trên Grafana Cloud và
  dùng region nào; luật heartbeat với biểu thức hằng `1`; cài đặt thông báo theo luật với chu kỳ lặp
  5 phút; định dạng truy vấn CloudWatch trong luật; data source chỉ cần `assumeRoleArn`.
- **Topic mở cho mọi account AWS**, chỉ giới hạn theo tên alarm. Đó là quy tắc đặt tên, không phải
  ranh giới bảo mật: ai biết ARN topic cũng gửi được tin vào Slack, và có thể làm Lambda quá tải
  (mặc định 1000 lần chạy đồng thời mỗi region). URL webhook kín không ngăn được điều này.
- **Cách ly giữa các môi trường chỉ do cách nối tên, không do policy.** Mỗi môi trường có Lambda,
  secret, topic riêng, và khách chọn topic theo `environment` của mình. Nhưng policy của topic vẫn
  nhận alarm của **mọi account** theo tên alarm và không kiểm tra môi trường, nên một alarm nối sai
  (hay của account lạ) vẫn gửi được vào topic của môi trường khác.
- **Phần dùng chung theo region chỉ bật ở một deployment:** heartbeat và role Grafana. Không có gì kiểm tra việc này giữa các state.
- **Alarm quota được tạo ở mọi deployment** (không còn công tắc): trong một region có nhiều môi trường thì cùng một quota bị báo một lần cho mỗi môi trường, vào kênh Slack của môi trường đó. Tên alarm có môi trường nên không trùng tên.
  Không có gì kiểm tra quy tắc "một deployment" (`workspace_guard` đang comment, và nó cũng chỉ bảo đảm workspace khớp biến).
- **Ba nhóm alarm cũ** (`lambda-errors`, `lambda-throttles`, `sns-failures`) và
  topic pipeline vẫn còn trong code, ghi vào topic không ai nhận, và thừa nếu Grafana chạy ổn.
- **Alarm của khách gần như chưa được tạo**, vì các biến tài nguyên còn `null`.
- **Chưa làm:** job snapshot cho `backup-25h`, budget cho chính management (`platform-monitoring`), multi-region (`region_abbrev`
  chưa dùng), tín hiệu "Grafana còn sống" ngoài heartbeat, và theo dõi khi Lambda không bao giờ được
  gọi.
- **`environment/shr-iam`:** quyền SNS, KMS và Lambda ở account khách đã được gỡ khỏi policy
  `monitoring_module`. Quyền cho Budgets chỉ có hai hành động `budgets:ModifyBudget` (tạo, sửa,
  xóa) và `budgets:ViewBudget`; vì budget nay do admin tạo ở `shr-monitoring` nên quyền ghi này của CI là thừa. Policy theo từng môi trường (`monitoring_module_env`) chưa được rà
  lại trong lần cập nhật tài liệu này.
- **Lambda Python chưa được chạy lần nào**, kể cả việc `urllib3` có sẵn trong runtime hay không.
- **Cả Grafana và đường AWS cùng hỏng thì không ai được báo.** Code Grafana đang comment (`grafana-alerting`) vẫn
  dùng access key tĩnh cho contact point heartbeat; với federation cần sửa lại để dùng credential mặc định.
