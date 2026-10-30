# Implement: tích hợp Grafana và cost monitoring

Tài liệu này gom những việc cần làm để đưa hai phần vào chạy: **A. tích hợp Grafana** và **B. cost
monitoring**. Nó là danh sách việc, thứ tự, lệnh và cách kiểm tra. Mô tả từng file và resource nằm
ở [MONITORING-OVERVIEW.md](MONITORING-OVERVIEW.md).

**Chưa có gì được chạy trên AWS hay Grafana thật.** Mọi bước dưới đây viết theo code và tài liệu;
mục "Chưa kiểm chứng" ở cuối liệt kê những điểm chỉ lộ ra khi chạy thật.

Ký hiệu: **Code** là việc làm bằng Terraform trong repo; **Tay** là việc làm trên giao diện hoặc CLI;
**Admin** là việc cần quyền quản trị billing.

---

## 0. Mô hình: một account chứa tất cả

Hiện tại **một account duy nhất** chứa mọi resource của mọi khách và cả phần monitoring. Grafana chỉ
đọc CloudWatch của account này. Hệ quả:

| Chủ đề | Với một account |
| --- | --- |
| CloudWatch cross-account observability (OAM) | **Không dùng, đã xóa khỏi code.** Metric của khách đã nằm sẵn trong account, không cần sink hay link. Đã bỏ `oam-sink.tf`, `oam-link.tf`, các biến `oam_sink_enabled`, `oam_sink_arn`, `oam_label_template`, output `oam_sink_arn`, và quyền `oam:*` ở `shr-iam` và role federation |
| Data source Grafana | **Một** data source CloudWatch cho account này (tạo tay, AWS SDK Default) |
| Tách khách trong dashboard | Không còn "account" để tách. Phải tách theo **tag hoặc ID resource** (xem D9 và A9) |
| Tách chi phí theo khách | **Chỉ tag mới tách được.** Tag trên resource là bắt buộc, không có tag thì budget và anomaly không phân biệt được khách |
| `management_account_id` ở môi trường khách | Chính là ID của account này. Alarm publish vào topic cùng account |
| Topic policy và key policy cho Budgets và Cost Anomaly | **Có trong code, luôn bật** (không còn công tắc), chưa apply |

Nếu sau này tách khách ra account riêng thì phải làm lại phần chia sẻ metric giữa các account (OAM hoặc role
theo account); code OAM đã xóa nên không còn sẵn, nhưng nằm trong lịch sử git nếu đã commit (hiện hai file
đó là file chưa theo dõi nên **không có** trong git).

---

## 1. Hiện trạng

| Phần | Tình trạng |
| --- | --- |
| Deployment `shr-monitoring` | **Mỗi môi trường và region một deployment** (Lambda, secret, topic riêng; workspace `<môi trường>-<region>`). Khách chọn topic theo `environment` của mình |
| Quyền đọc cho Grafana | Role federation `lighthouse-alerting-grafana-federated` (Managed Identity của Azure VM, không key) ở stack riêng `environment/shr-grafana-federation`. Ba giá trị Azure trong `terraform.tfvars`. Chưa apply |
| Data source CloudWatch | Tạo **tay trên giao diện Grafana** với AWS SDK Default. Stack `environment/grafana-datasources` chỉ dành cho đường role theo account, **không dùng** |
| OAM sink và link | **Đã xóa khỏi code** (mục 0) |
| Role Grafana theo từng khách (`modules/customer-monitoring/grafana.tf`) | Đã comment, không dùng |
| Sáu dashboard | **Năm dashboard còn ba ô chọn `region`, `environment`, `instance`; panel lọc theo dimension `Environment`, `Instance` và `region`** (bản bàn giao ở repo này). Chưa thử trên Grafana, chưa đồng bộ sang `graham-infrastructure` (A9) |
| Luật cảnh báo pipeline và heartbeat hai chiều | Có (`grafana-alerting`, `shr-monitoring`), toàn bộ đang comment, chưa validate. **Làm sau** |
| Budget và cost anomaly cho từng khách | **Code đã viết, tập trung** ở module `cost-monitoring` gọi từ `shr-monitoring` (`cost_customers`), chưa apply. Đã xóa khỏi `customer-monitoring` |
| Tag chi phí trên resource | **`default_tags` đã có trong code** ở ba environment khách (`Customer`, `Environment`, `CostCenter`, `ManagedBy`), chưa apply. Tag **`Instance`** (duy nhất cho từng khách, budget lọc theo tag này) đã có sẵn trên resource, không do code này gắn. Tag chưa kích hoạt ở Billing |
| Topic policy cho Budgets và Cost Anomaly | **Chưa có** |
| Quyền ghi billing cho pipeline | **Không cần nữa:** budget do admin apply ở `shr-monitoring`. Quyền Budgets và Cost Anomaly còn trong policy CI ở `shr-iam` là thừa (B10) |

---

## 2. Quyết định cần chốt trước

| # | Quyết định | Ảnh hưởng | Hướng đề nghị |
| --- | --- | --- | --- |
| D1 | ~~Tag tính chi phí~~ | | **Đã chốt (đã đổi):** budget và anomaly lọc theo tag **`Instance`**, có giá trị **duy nhất cho từng khách** (một tag, một bộ lọc). `CostCenter` dùng chung giữa các khách nên **không dùng để lọc**, cùng `Customer` và `Environment` để dashboard chọn khách |
| D2 | ~~Mỗi khách một account hay chung account~~ | | **Đã chốt: chung một account.** Tag là bắt buộc |
| D3 | Có theo dõi chi phí của management (firewall chung) không | Có thêm budget ở `shr-monitoring` | Ngoài ticket, trừ khi bạn muốn |
| D4 | ~~Topic nhận tin Budgets, Cost Anomaly mở hay giới hạn~~ | | **Đã chốt:** giới hạn theo account này bằng `aws:SourceAccount` |
| D5 | ~~Deny billing: miễn trừ role CI~~ | | **Không còn cần:** budget do admin apply, CI không tạo budget |
| D6 | ~~Staging dùng chung `CostCenter = demo-testing`~~ | | **Không còn cần:** budget lọc theo `Instance`, không theo `CostCenter` |
| D7 | ~~Data source do repo nào giữ~~ | | **Đã chốt:** tạo tay trên giao diện Grafana, không dùng stack `grafana-datasources` |
| D8 | State của `grafana-alerting` lưu ở đâu | State chứa secret key của heartbeat | Backend S3 riêng tư. Chỉ cần khi bật `grafana-alerting` |
| D9 | ~~Dashboard tách khách bằng gì khi không còn account~~ | | **Đã chốt và đã sửa JSON:** template chỉ còn `region`, `environment`, `instance` (`region`, `environment` và `instance` đều lấy từ tag trên EC2; `region` chỉ liệt kê được giá trị tag của instance nằm ở region mặc định của data source; mặc định `ap-southeast-2`, `production`, và `instance` là All = `*`, chọn được nhiều); mọi panel lọc metric theo dimension `Environment`, `Instance` và `region`. Giả định metric có ba dimension này (chưa kiểm chứng) |

---

## 3. Phần A: tích hợp Grafana

### 3.1 Việc làm

| # | Việc | Loại | Phụ thuộc |
| --- | --- | --- | --- |
| A1 | **Phía Azure:** gắn Managed Identity cho VM Grafana (lấy tenant ID và object ID); tạo app registration làm audience (Application ID URI, ví dụ `api://aws-sts`) | Tay (Azure) | |
| A2 | Stack riêng `environment/shr-grafana-federation`: điền ba giá trị Azure vào `terraform.tfvars`, `terraform init`, `plan`, `apply`. Ghi lại output `grafana_federated_role_arn` (xem README của stack) | Admin AWS | A1 |
| A3 | **Phía VM:** timer ghi token Azure ra file; đặt `AWS_ROLE_ARN` (output A2), `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_REGION` cho tiến trình Grafana; khởi động lại (xem `environment/grafana-datasources/README.md`, phần VM; vai trò Ansible ở `ngcs-metrics-server-roles`) | Người vào VM | A2 |
| A4 | Apply `shr-monitoring` cho từng môi trường và region cần theo dõi (workspace `<môi trường>-<region>`). Alarm quota được tạo ở mọi deployment. (Không còn công tắc OAM) | Code | |
| A5 | Môi trường khách: điền `management_account_id` = ID của account này (alarm publish vào topic của A4, cùng region). | Code | A4 |
| A6 | Tạo data source CloudWatch **trên giao diện Grafana** với **AWS SDK Default** (Assume Role ARN để trống), region mặc định chọn theo nơi có khách. Lấy uid của data source | Tay | A3 |
| A7 | Kiểm tra Save & test: "Data source is working" | Tay | A6 |
| A8 | **Đã làm trong code:** role federation có thêm `ec2:DescribeInstances` (cùng `tag:GetResources`, `ec2:DescribeRegions`) để biến EC2 đọc theo tag. Có hiệu lực khi apply `shr-grafana-federation` ở A2 | Code | D9 |
| A9 | **Dashboard: đã sửa bản bàn giao ở repo này** (`modules/customer-monitoring/grafana-dashboards/`): bỏ biến `account`, `accountId` và các biến resource (canary, ALB, NLB, WAF, volume, target group); năm dashboard còn `region`, `environment`, `instance`. **Còn lại:** kiểm tra metric có dimension `Environment`, `Instance` và `region` (`aws cloudwatch list-metrics`); tách canary HTTPS và workflow nếu cần; đồng bộ sang `graham-infrastructure`; thử trên Grafana thật | Phía repo kia, Tay | D9 |
| A10 | Nạp sáu dashboard vào Grafana, thay uid data source (`8s123msinglish` đang viết cứng trong từng file) bằng uid ở A6 nếu khác | Tay | A6, A9 |
| A11 | **Làm sau:** `grafana-alerting` (luật theo dõi đường giao tin) và heartbeat: bỏ comment, validate và ghim phiên bản provider (**quan trọng**: chưa từng chạy `terraform validate`), chốt backend (D8), apply, chờ heartbeat tới, rồi bật `grafana_heartbeat_alarm_enabled` ở `shr-monitoring` | Code, Tay | A6, D8 |
| A12 | Cấp `management_account_id` cho CI của `stg` và `prd` (workflow chưa truyền biến này) | Tay (CI) | A4 |

Không còn trong danh sách so với bản trước: sink và link OAM (đã xóa khỏi code), `oam_source_organization_id`,
thêm khách vào `customers` của `grafana-datasources`, truyền `oam_sink_arn` cho CI.

### 3.2 Lệnh

```powershell
# A2: federation (một lần cho cả account)
cd environment\shr-grafana-federation
terraform init
terraform plan
terraform apply
terraform output grafana_federated_role_arn

# A4: management, mỗi môi trường và region một lần, mỗi lần một workspace <môi trường>-<region>
# (workspace_guard đang comment: tự chọn đúng workspace).
cd ..\shr-monitoring
terraform workspace new prd-us-east-1          # lần đầu; sau đó: terraform workspace select prd-us-east-1
terraform plan  -var environment=prd -var region=us-east-1
terraform apply -var environment=prd -var region=us-east-1

# A5: môi trường khách (management_account_id = ID account này)
cd ..\dev-cus0001
terraform apply

# A11 (làm sau, code đang comment): Grafana theo dõi đường giao tin; bí mật chỉ truyền bằng biến môi trường
cd ..\grafana-alerting
$env:TF_VAR_grafana_token         = "<service account token>"
$env:TF_VAR_heartbeat_access_key  = "<access key id>"
$env:TF_VAR_heartbeat_secret_key  = "<secret access key>"
terraform init
terraform plan         # đọc kỹ trước khi apply
terraform apply
```

### 3.3 Thứ tự

```text
A1 (Azure) → A2 (federation) → A3 (VM) → A6, A7 (data source)
A4 (shr-monitoring) → A5 (khách)                       ┐ song song
B1 (tag lên resource) → A8, A9 (sửa dashboard) → A10    ┘ A9 cần tag
A11 (alerting, heartbeat) sau cùng
```

### 3.4 Kiểm tra

| Kiểm tra | Kết quả mong đợi |
| --- | --- |
| Save & test data source | "Data source is working" |
| Dashboard Platform, chọn Environment và Region | Quota, Lambda, SNS có số liệu |
| Dashboard Environment Overview, biến **Customer** (sau A9) | Liệt kê các khách có tag `Customer`; chọn một khách thì panel có số liệu |
| Chọn khách khác | Số liệu đổi theo, không lẫn khách |
| Heartbeat (sau A11): metric `NumberOfMessagesPublished` của topic heartbeat | Lớn hơn 0 sau 5 đến 10 phút |
| Dừng heartbeat 15 phút | Alarm `grafana-heartbeat` báo vào Slack |
| Tắt tạm Lambda gửi Slack | Luật Grafana báo vào Slack |

---

## 4. Phần B: cost monitoring

Cả khách và monitoring chung một account, nên **tag là cách duy nhất** để tách chi phí. Budget và anomaly của
mọi khách được quản lý **tập trung** trong `shr-monitoring` (như quota), admin apply tay, nên pipeline CI và các
environment khách **không cần quyền billing**. Cost monitoring **luôn bật**: không có công tắc nào, topic và khóa
KMS luôn cho Budgets và Cost Anomaly của account này publish; budget chỉ được tạo cho khách có trong `cost_customers`.

Code đã viết, **chưa apply và chưa chạy `terraform validate`** (plugin provider không chạy được trên máy viết code).

### 4.1 Cách các file nối với nhau

```text
environment/dev-cus0001, stg-customer, prd-customer      (tag Instance có sẵn trên resource)
                                   │  tag chi phí
environment/shr-monitoring/main.tf (biến cost_customers từ file .tfvars)
        ├─► module alert_delivery ─► modules/alert-delivery/formatter.tf + kms.tf
        │                              (mở topic P2, P3 và khóa KMS cho Budgets, Cost Anomaly)
        └─► module cost_monitoring ─► modules/cost-monitoring/budgets.tf + anomaly.tf
                                       (mỗi khách: 1 budget, 1 anomaly monitor, 1 subscription → topic P3 và P2)
                                                 │
                       topic ─► alert delivery Lambda ─► Slack kênh Operations
```

### 4.2 Bảng file theo từng bước

| Bước | File cần xem hoặc sửa | Nội dung |
| --- | --- | --- |
| B1 | [dev-cus0001/main.tf:27](environment/dev-cus0001/main.tf#L27), [stg-customer/main.tf:30](environment/stg-customer/main.tf#L30), [prd-customer/main.tf:30](environment/prd-customer/main.tf#L30) | Khối `default_tags` (`Customer`, `Environment`, `CostCenter`, `ManagedBy`); `Instance` không đặt ở đây |
| B1, B2 | [dev-cus0001/main.tf:40](environment/dev-cus0001/main.tf#L40), [stg-customer/main.tf:42](environment/stg-customer/main.tf#L42), [prd-customer/main.tf:42](environment/prd-customer/main.tf#L42) | Giá trị tag `CostCenter` (chỉ để nhóm, không dùng cho budget; staging dùng chung `demo-testing`) |
| B1 | [dev-cus0001/monitoring.tf:7](environment/dev-cus0001/monitoring.tf#L7), [stg-customer/monitoring.tf:9](environment/stg-customer/monitoring.tf#L9), [prd-customer/monitoring.tf:7](environment/prd-customer/monitoring.tf#L7) | Cùng giá trị đó truyền vào module `customer-monitoring` (chỉ cho tag của alarm) |
| B5 | [terraform.tfvars.example](environment/shr-monitoring/terraform.tfvars.example) | Mẫu `cost_customers` để copy thành file `.tfvars` |
| B5 | [shr-monitoring/main.tf:113](environment/shr-monitoring/main.tf#L113), [:123](environment/shr-monitoring/main.tf#L123) | Biến `cost_customers` và `cost_default_anomaly_threshold_usd` |
| B6 | [shr-monitoring/main.tf:169](environment/shr-monitoring/main.tf#L169) | Module `cost_monitoring`, có `depends_on` ở [dòng 177](environment/shr-monitoring/main.tf#L177) để topic policy và key policy có trước |
| B6 | [shr-monitoring/main.tf:216](environment/shr-monitoring/main.tf#L216) | Output `cost_budget_names` |
| B6 | [budgets.tf:4](modules/cost-monitoring/budgets.tf#L4) | Budget: [bộ lọc tag ở dòng 13](modules/cost-monitoring/budgets.tf#L13), [thông báo 80% ở dòng 18](modules/cost-monitoring/budgets.tf#L18), [thông báo 100% ở dòng 37](modules/cost-monitoring/budgets.tf#L37), dự báo nằm giữa hai dòng đó |
| B6 | [anomaly.tf:5](modules/cost-monitoring/anomaly.tf#L5) và [:22](modules/cost-monitoring/anomaly.tf#L22) | Anomaly monitor và subscription (người nhận SNS ở [dòng 29](modules/cost-monitoring/anomaly.tf#L29), ngưỡng ở [dòng 34](modules/cost-monitoring/anomaly.tf#L34)) |
| B6 | [cost-monitoring/variables.tf](modules/cost-monitoring/variables.tf) | `customers` ([dòng 16](modules/cost-monitoring/variables.tf#L16), kiểm tra `instance` không trùng), `cost_tag_key`, mặc định `Instance` ([41](modules/cost-monitoring/variables.tf#L41)), `warning_percent` ([47](modules/cost-monitoring/variables.tf#L47)), `critical_percent` ([53](modules/cost-monitoring/variables.tf#L53)), `default_anomaly_threshold_usd` ([65](modules/cost-monitoring/variables.tf#L65)) |
| B6, B7 | [formatter.tf:160](modules/alert-delivery/formatter.tf#L160) và [:186](modules/alert-delivery/formatter.tf#L186) | Topic policy cho `budgets.amazonaws.com` và `costalerts.amazonaws.com` (chỉ topic P2 và P3, giới hạn theo account) |
| B6, B7 | [kms.tf:54](modules/alert-delivery/kms.tf#L54) | Key KMS của topic cho hai dịch vụ trên |
| B7 | [slack_formatter.py](modules/alert-delivery/lambda_src/slack_formatter.py) | Lambda dựng tin Slack; tin Budgets và Cost Anomaly không nêu team nên vào **Operations** |
| B8 | file `.tfvars` của bạn | Sửa `monthly_budget_usd` thật, thêm khách |

### 4.3 Các bước chi tiết

#### B0. Chuẩn bị
- Biết account này là **account payer** (management của Organization) hay account đứng riêng. Chỉ account payer hoặc account đứng riêng mới vào được trang cost allocation tag; nếu account này là member thì B3 làm ở account payer.
- Đường cảnh báo Slack của môi trường đó đã chạy: đã apply `shr-monitoring` và secret webhook đã có URL (`aws secretsmanager put-secret-value`). Không có thì tin cost vào topic nhưng không tới Slack.
- Tài khoản admin có quyền tạo Budgets, Cost Explorer (anomaly), SNS và KMS.

#### B1. Kiểm tra tag Instance trên resource
- **Tag dùng để lọc:** `Instance`, duy nhất cho từng khách. Tag này đã có sẵn trên resource của khách, nên **không cần apply lại** môi trường khách. `CostCenter` dùng chung giữa các khách, budget không dùng.
- **Làm:** lấy giá trị `Instance` của từng khách và kiểm tra tag có trên resource tính tiền.
  ```powershell
  aws ec2 describe-tags --filters "Name=key,Values=Instance" --query "Tags[].[ResourceId,Value]" --output table
  ```
- **Kết quả:** mỗi khách có đúng một giá trị `Instance`, không trùng giữa hai khách.

#### B2. Staging
Không cần làm gì: staging dùng chung `CostCenter` nhưng budget lọc theo `Instance`, nên vẫn tách được theo từng khách.

#### B3. Kích hoạt cost allocation tag
Tag chỉ kích hoạt được sau khi **xuất hiện** trong Billing (tới 24 giờ sau khi resource có tag), rồi tới 24 giờ nữa mới có hiệu lực trong Cost Explorer. Làm ở account payer nếu thuộc Organization.
```powershell
# 1. Tag đã xuất hiện chưa
aws ce list-cost-allocation-tags --region us-east-1 --status Inactive --query "CostAllocationTags[?TagKey=='Instance']"
# 2. Kích hoạt
aws ce update-cost-allocation-tags-status --region us-east-1 `
  --cost-allocation-tags-status TagKey=Instance,Status=Active TagKey=Environment,Status=Active
# 3. Kiểm tra
aws ce list-cost-allocation-tags --region us-east-1 --status Active --query "CostAllocationTags[].TagKey"
```
Tag không áp dụng ngược cho chi phí trước ngày kích hoạt.

#### B4. Kiểm tra Cost Explorer (sau khoảng 1 ngày)
Lọc theo tag `Instance = <giá trị Instance của khách>`: chi phí phải **khác 0**. Bằng 0 thì **dừng lại**: budget sẽ đọc 0 đồng và không bao giờ báo, không có lỗi. Nguyên nhân thường gặp: tag chưa Active, resource chưa mang tag, chưa đủ thời gian.

#### B5. Khai báo khách trong `shr-monitoring`
```powershell
cd environment\shr-monitoring
Copy-Item terraform.tfvars.example cost.prd.tfvars
```
Sửa `cost.prd.tfvars`: `instance` đúng giá trị tag `Instance` ở B1, `monthly_budget_usd = 1` để thử. Điền ở **một** deployment mỗi môi trường, vì tên budget có môi trường và hai region của cùng một môi trường sẽ trùng tên.

#### B6. Apply
```powershell
terraform init
terraform validate                         # chưa từng chạy: đọc kỹ lỗi nếu có
terraform workspace select prd-us-east-1   # đúng workspace <môi trường>-<region>
terraform plan  -var environment=prd -var region=us-east-1 -var-file=cost.prd.tfvars
terraform apply -var environment=prd -var region=us-east-1 -var-file=cost.prd.tfvars
terraform output cost_budget_names
```
Plan phải thấy: **thêm** budget, anomaly monitor, subscription; **sửa** topic policy P2/P3 và key KMS. Không có resource nào bị xóa. Chọn sai workspace là ghi đè state của môi trường khác.

#### B7. Kiểm tra
```powershell
aws budgets describe-budgets --account-id <ID account> --query "Budgets[].BudgetName"
aws ce get-anomaly-monitors --query "AnomalyMonitors[].MonitorName"
aws ce get-anomaly-subscriptions --query "AnomalySubscriptions[].SubscriptionName"
# Thử đường Slack độc lập với Budgets
aws sns publish --region us-east-1 --topic-arn <ARN topic P3> --message "cost test"
```
Budget cập nhật số liệu vài lần mỗi ngày, nên cảnh báo thật có thể đến sau vài giờ. Anomaly cần vài ngày dữ liệu, chỉ xác nhận subscription tồn tại. Tin phải tới Slack kênh **Operations**.

Nếu tin không tới:

| Triệu chứng | Nơi xem |
| --- | --- |
| Apply báo budget không publish được vào topic | Topic policy ([formatter.tf:160](modules/alert-delivery/formatter.tf#L160)) và key policy ([kms.tf:54](modules/alert-delivery/kms.tf#L54)) |
| Tin anomaly không tới | Subscription ở [anomaly.tf:22](modules/cost-monitoring/anomaly.tf#L22), statement Cost Anomaly ở [formatter.tf:186](modules/alert-delivery/formatter.tf#L186) |
| Budget không bao giờ báo | Tag chưa Active, hoặc `instance` lệch tag `Instance` trên resource (B1, B4) |
| Tin có ở topic nhưng không tới Slack | Secret webhook rỗng hoặc sai; log của alert delivery Lambda |

#### B8. Ngân sách thật và mở rộng
Thay `monthly_budget_usd` bằng số thật, thêm khách vào `cost_customers`, apply lại. Số budget và monitor có hạn mức và có phí theo số lượng: kiểm tra trước khi thêm hàng trăm khách (chưa kiểm chứng con số).

#### B9. (Tùy chọn) Định dạng tin Cost Anomaly và Budgets
Sửa [slack_formatter.py](modules/alert-delivery/lambda_src/slack_formatter.py) để tin kèm tên khách. Hiện chúng đi vào Operations dạng văn bản tự do.

#### B10. (Tùy chọn) Dọn quyền thừa của role CI
Budget không còn do CI tạo, nên quyền ghi Budgets và Cost Anomaly trong policy CI ở [shr-iam/github_actions.tf](environment/shr-iam/github_actions.tf) (`monitoring_module`, `monitoring_module_env`) là thừa, cùng quyền đọc tương ứng nếu không còn dùng.

#### Rút lại khi cần
Đặt `cost_customers = {}` rồi apply: toàn bộ budget và monitor bị xóa. Topic và khóa KMS vẫn mở cho Budgets và Cost Anomaly của account này (không còn công tắc).

### 4.4 Thứ tự

```text
B0 → B1 (tag lên resource) → B3 (kích hoạt) → chờ ~1 ngày → B4 (kiểm tra) → B5, B6 (budget thử) → B7 (kiểm tra tin) → B8
```

### 4.5 Kiểm tra

| Kiểm tra | Kết quả mong đợi |
| --- | --- |
| Cost Explorer lọc theo tag `Instance` | Chi phí khác 0 cho từng khách |
| Budget thử ngưỡng thấp | Tin tới Slack kênh Operations, có tên budget `<môi trường>-<khách>-monthly-budget` |
| Đổi ngân sách trong `cost_customers` | Budget đổi theo ở lần apply sau, không sửa code |
| Anomaly | Có tin khi chi tiêu bất thường (cần vài ngày dữ liệu) |

### 4.6 Rủi ro riêng của cost

| Rủi ro | Hệ quả |
| --- | --- |
| Tag chưa kích hoạt hoặc chưa có trên resource tính tiền | Budget đọc 0 đồng, không bao giờ báo, **không có lỗi** |
| Tag chỉ có hiệu lực từ lúc kích hoạt | Chi phí trước đó không được tách |
| Resource không tag được hoặc tag không đi theo chi phí (một số dịch vụ, phí dùng chung) | Không thuộc khách nào, nằm ngoài mọi budget |
| `instance` trong `cost_customers` lệch với tag `Instance` trên resource | Budget lọc ra 0 đồng, không lỗi |
| `cost_customers` điền ở hai region của cùng một môi trường | Apply báo trùng tên budget: chỉ điền ở một deployment mỗi môi trường |
| Budgets là dịch vụ toàn cầu; topic ở một region cụ thể | Chưa biết gửi được không, thử ở B7 |
| Số budget và monitor tăng theo số khách | Có hạn mức và phí theo số lượng: kiểm tra trước (chưa kiểm chứng con số) |
| Topic P2/P3 luôn mở cho Budgets và Cost Anomaly của account | Rủi ro thấp (ràng buộc `aws:SourceAccount`), nhưng có ở mọi môi trường, kể cả chưa có khách |

### 4.7 Tài liệu tham khảo

Đã đối chiếu với code:

| Chủ đề | Tài liệu |
| --- | --- |
| Topic policy của Budgets (principal, `aws:SourceAccount`, `aws:SourceArn`); topic phải cùng account | [Creating an Amazon SNS topic for budget notifications](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-sns-policy.html) |
| Topic policy và key KMS của Cost Anomaly (`costalerts.amazonaws.com`, `aws:SourceAccount`) | [Creating an Amazon SNS topic for anomaly notifications](https://docs.aws.amazon.com/cost-management/latest/userguide/ad-SNS.html) |
| Kích hoạt tag chi phí: 24 giờ để hiện, 24 giờ để có hiệu lực, không áp dụng ngược, chỉ account payer hoặc account đứng riêng | [Activating user-defined cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/activating-tags.html) |
| Dùng tag trong báo cáo (tiền tố `user:`) | [Using user-defined cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/custom-tags.html) |
| `aws_budgets_budget`: `cost_filter` `TagKeyValue` dạng `TagKey$TagValue`, `notification`, `tags` | [Terraform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) |
| `aws_ce_anomaly_subscription`: `frequency`, `subscriber`, `threshold_expression` | [Terraform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_subscription), [AnomalySubscription (API)](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_AnomalySubscription.html) |
| Hạn mức Budgets và Cost Anomaly | [Quotas and restrictions](https://docs.aws.amazon.com/cost-management/latest/userguide/management-limits.html) (chưa đọc) |

Chưa xác nhận được:
- **Statement KMS cho Budgets:** trang tài liệu có bước "thêm đoạn sau vào key policy" nhưng JSON nằm trong tab không đọc được. Statement ở [kms.tf:54](modules/alert-delivery/kms.tf#L54) dùng cùng dạng với Cost Anomaly. Nếu budget không publish được vào topic mã hóa, chép đúng statement từ trang Budgets ở trên.
- **`match_options = GREATER_THAN_OR_EQUAL`** ở [anomaly.tf:38](modules/cost-monitoring/anomaly.tf#L38): trang Terraform không liệt kê giá trị này (API của AWS dùng nó). Chạy `terraform plan` để xem provider có chấp nhận không.
- Budgets gửi vào topic ở region của deployment, và nội dung tin Budgets và Cost Anomaly.

---

## 5. Thứ tự tổng thể của hai phần

```text
Pha 0   chốt D3, D6 (D1, D5, D9 đã chốt)
Pha 1   code cost, A8 đã xong; còn B9 và B10 (tùy chọn)
Pha 2   tay và admin: A1 (Azure), B3 (kích hoạt tag), A12 (biến cho CI)
Pha 3   apply: B1 (tag); A2 → A3 → A4 → A5 → A6, A7; B4 (sau ~1 ngày) → B5, B6 → B7, B8
Pha 4   dashboard: A9, A10 ở graham-infrastructure; kiểm tra cả hai phần; A11 sau cùng
```

Phần cost có độ trễ cố hữu (khoảng một ngày sau khi kích hoạt tag), và A9 (dashboard theo khách) cũng
cần tag, nên **B1 (apply tag) và B3 (kích hoạt) là việc đầu tiên**, làm song song với Grafana.

---

## 6. Giữ khớp giữa hai repo

Dashboard ở `graham-infrastructure` và Terraform ở repo này không tự đồng bộ. Cần giữ khớp:

| Giá trị | Ở dashboard | Ở repo này |
| --- | --- | --- |
| Ngưỡng alarm (CPU 70 và 90, memory 70 và 85, disk 80 và 90, ALB 0,3 s và 5%, certificate 7 và 30, quota 80 và 95) | Đường ngưỡng trên panel | Biến ngưỡng của `customer-monitoring` |
| Tên alert delivery Lambda | Biến Environment và Region ở Platform | `lighthouse-alerting-<môi trường>-<region>-formatter` |
| Namespace `AWS/Usage`, `Lighthouse/Backup`, `CWAgent` | Truy vấn panel | AWS tự publish (`AWS/Usage`), job snapshot (repo khác), cấu hình agent |
| Dimension `Environment`, `Instance` và `region` trên metric | Mọi panel của năm dashboard | CloudWatch không tự thêm tag vào metric: phải do metric tùy chỉnh, cấu hình agent, hoặc tính năng gắn tag của CloudWatch (chưa kiểm chứng) |
| Tag chi phí (`Instance`, `Environment`) | Không dùng | Tag có sẵn trên resource (B1) |
| uid data source | Viết cứng trong từng file JSON | Data source tạo tay ở A6 |

Quy ước dashboard mới: thêm vào `graham-infrastructure`.

---

## 7. Chưa kiểm chứng

Phần Grafana:

- Metric có dimension `Environment`, `Instance` và `region` hay không (nếu không, panel trống); truy vấn biến `ec2InstanceAttributes`; panel canary HTTPS và workflow đang hiện cả hai canary vì cùng tag.
- `terraform validate` của `grafana-alerting` chưa chạy (provider không tải được ở nơi viết code).
- Role federation và Azure Managed Identity chưa chạy thật (token, audience, `sub`).
- Contact point SNS trên Grafana; luật heartbeat dùng biểu thức hằng số.
- Truy vấn CloudWatch trong các luật; multi-select target group trên Remote Access.

Phần cost:

- Budgets gửi vào topic SNS ở region của deployment (Budgets là dịch vụ toàn cầu).
- Nội dung chính xác của tin Budgets và Cost Anomaly (cần một tin thật).
- Giới hạn tài nguyên (ARN) cho các hành động của Cost Anomaly Detection.
- Statement KMS cho Budgets ([kms.tf:54](modules/alert-delivery/kms.tf#L54)): JSON trong tài liệu AWS không đọc được, cần đối chiếu nếu budget không publish được vào topic mã hóa.
- `match_options = GREATER_THAN_OR_EQUAL` của anomaly ([anomaly.tf:38](modules/cost-monitoring/anomaly.tf#L38)): trang Terraform không liệt kê giá trị này, cần `terraform plan` xác nhận.
- Một bộ lọc budget theo hai tag cùng lúc (nên dùng một tag `Instance` duy nhất để tránh).
- Cú pháp `MAX`, `SUM` của metric math ở các alarm target group (không thuộc phần cost, nhưng chưa apply).

Còn mở: bốn alarm CloudWatch cũ của pipeline và topic `pipeline` vẫn còn trong code, dư thừa khi đã
có luật Grafana; chưa quyết định bỏ.
