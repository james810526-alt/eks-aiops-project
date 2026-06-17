# AWS EKS AIOps 智能維運告警系統專題規格說明

> 本文件用途：作為後續詢問 AI 時的「專題背景提示詞」，讓 AI 能根據本專題目標，協助產出 CloudFormation YAML、Kubernetes YAML、Helm 安裝步驟、AWS CLI 指令、部署教學、除錯流程與簡報內容。

---

## 1. 專題名稱

**AWS EKS 智能維運告警系統實作**

完整名稱：**基於 AWS EKS 與 K8sGPT 的 AIOps 雲端智能維運與自動化告警系統實作**

---

## 2. 專題故事背景

某電商網站在晚間 20:00 舉辦限時促銷活動，大量消費者同時湧入網站搶購商品並進行結帳。活動開始後，網站突然變慢，部分使用者無法開啟商品頁面，甚至在結帳階段發生錯誤，造成訂單流失與客戶體驗下降。

此時負責值班的是剛入職、Kubernetes 經驗不足的工程師。他面對 Linux 終端機，只能不斷輸入：

```bash
kubectl get pods
kubectl logs
kubectl describe pod
```

但畫面上出現大量錯誤訊息，例如：

```text
CrashLoopBackOff
ImagePullBackOff
Pending
OOMKilled
Readiness probe failed
Service has no endpoints
Ingress failed to provision ALB
```

工程師無法第一時間判斷問題是來自應用程式錯誤、Pod 資源不足、節點容量不夠、資料庫連線問題，還是短時間流量暴增導致系統無法負荷。

因此，本專題希望建立一套部署於 AWS EKS 的 AIOps 智能維運與自動化告警系統，當活動期間發生流量高峰或 Kubernetes 服務異常時，能即時偵測問題、分析原因、提供修復建議並通知工程師。後續也可結合 AWS 水平擴展能力，讓系統在高流量期間自動擴充資源，降低故障風險。

---

## 3. 情境、痛點與解方

### 3.1 情境

企業將電商網站部署於 AWS EKS 上，網站平時穩定運作，但在晚間 20:00 限時促銷活動開跑時，大量使用者同時湧入網站，造成流量瞬間暴增。

系統由多個 Kubernetes Pod、Service、Ingress、ALB、RDS 與 S3 組成，必須支援活動期間的高流量、穩定結帳與即時故障處理。

### 3.2 痛點

在活動高峰期間，系統可能同時面臨流量暴增、Pod 資源不足、節點容量不足、應用程式異常或服務連線失敗等問題。傳統監控系統雖然能發出告警，但多半只告訴工程師「系統壞了」，卻沒有清楚說明「為什麼壞」以及「該怎麼修」。

新手工程師需要花大量時間查 Log、搜尋錯誤訊息或求助資深工程師，導致平均修復時間 MTTR 拉長，也增加企業營運風險。

### 3.3 解方

本專題導入 AWS EKS 作為高可用網站平台，並結合 K8sGPT 與 AWS Bedrock 建立 AIOps 智能維運流程。

當 Kubernetes 發生異常時，K8sGPT 會自動偵測問題，並透過 AWS Bedrock 將複雜錯誤轉換成白話原因、影響範圍與修復建議，再透過 Email 或 LINE 通知工程師。

工程師確認後，系統才會執行修正，避免 AI 直接修改正式環境。後續也可加入 HPA、Cluster Autoscaler 或 Karpenter，讓系統在電商活動高流量期間具備自動水平擴展能力。

---

## 4. 專題核心目標

1. 使用 CloudFormation 建立可重複部署的 AWS 基礎架構。
2. 在 AWS 孟買區 `ap-south-1` 建立跨 3 個 AZ 的高可用 VPC 架構。
3. 使用 Amazon EKS 部署對外網站服務。
4. 外部消費者可透過 Internet-facing ALB 瀏覽網站。
5. EKS Worker Node 放在 Private App Subnet。
6. RDS 放在 Private Data Subnet。
7. S3 用於保存檔案、Log、K8sGPT 診斷報告與 AI 分析結果。
8. 工程師維運通道改用 IAM、EKS Access Entry、kubectl、Helm 與 SSM，不直接開放 SSH。
9. 使用 K8sGPT 偵測 Kubernetes 異常。
10. 使用 AWS Bedrock 產生白話化錯誤原因與修復建議。
11. 使用 SNS Email 或 LINE 通知工程師。
12. 修復動作需經工程師 Approve 後才執行。
13. 後續加入 HPA、Cluster Autoscaler 或 Karpenter，應對高流量活動。

---

## 5. 目標 AWS 區域

```text
Region: ap-south-1
Location: Mumbai
```

---

## 6. 最終架構總覽

### 6.1 使用者流量路徑

```text
外部使用者 / 消費者
→ Internet Gateway
→ Internet-facing ALB
→ Kubernetes Ingress
→ Kubernetes Service
→ Web Pod
→ RDS / S3
→ 回傳網頁 / 結帳結果
```

### 6.2 維運與 AIOps 路徑

```text
K8sGPT Pod / CronJob
→ 掃描 EKS Cluster
→ 產生診斷報告
→ 儲存至 S3
→ 送至 AWS Bedrock
→ 產生錯誤原因與修復建議
→ SNS Email / LINE 通知工程師
→ 工程師 Approve / Reject
→ CodeBuild / kubectl 套用修正
→ 再次驗證
```

### 6.3 工程師維運通道

```text
工程師
→ AWS IAM / EKS Access Entry
→ kubectl / Helm
→ EKS API Server
→ 維運指定 namespace
```

若需進入私有節點，不開放 SSH，改用：

```text
工程師
→ AWS Systems Manager Session Manager
→ Private Subnet 內的節點或維運 EC2
```

---

## 7. AWS 網路架構設計

### 7.1 VPC 規劃

```text
VPC CIDR: 10.20.0.0/16
Region: ap-south-1
AZ 數量: 3
```

### 7.2 Subnet 規劃

| AZ | Public Subnet | Private App Subnet | Private Data Subnet |
|---|---|---|---|
| ap-south-1a | 10.20.0.0/24 | 10.20.10.0/24 | 10.20.20.0/24 |
| ap-south-1b | 10.20.1.0/24 | 10.20.11.0/24 | 10.20.21.0/24 |
| ap-south-1c | 10.20.2.0/24 | 10.20.12.0/24 | 10.20.22.0/24 |

### 7.3 Subnet 用途

| Subnet 類型 | 用途 |
|---|---|
| Public Subnet | ALB、NAT Gateway |
| Private App Subnet | EKS Managed Node Group、Pod |
| Private Data Subnet | RDS、ElastiCache optional |
| S3 | 區域型服務，不放在 subnet 內 |

### 7.4 Subnet Tag

Public Subnet：

```text
kubernetes.io/role/elb = 1
```

Private Subnet：

```text
kubernetes.io/role/internal-elb = 1
```

Cluster 相關 Subnet：

```text
kubernetes.io/cluster/eks-aiops-mumbai = shared
```

---

## 8. NAT Gateway 設計

NAT Gateway 使用 Parameter + Condition 控制。

### 8.1 NAT Gateway 模式

```yaml
NatGatewayMode:
  Type: String
  Default: Single
  AllowedValues:
    - None
    - Single
    - MultiAZ
```

| 模式 | 說明 |
|---|---|
| None | 不建立 NAT Gateway，最省錢，但 Private Node 可能無法連外 |
| Single | 建立 1 個 NAT Gateway，練習版 |
| MultiAZ | 建立 3 個 NAT Gateway，正式高可用版 |

### 8.2 練習版

```text
1 個 NAT Gateway
所有 Private App Subnet 先共用
```

### 8.3 正式版

```text
AZ-a → NAT Gateway A
AZ-b → NAT Gateway B
AZ-c → NAT Gateway C
```

正式版建議：

```text
3 個 NAT Gateway
3 份 Private Route Table
每個 AZ 的 Private Subnet 走同 AZ NAT Gateway
```

Private Data Subnet 原則上不需要對外連線，除非資料層服務有明確更新或外部 API 存取需求。

---

## 9. NACL 設計

NACL 可以在整個專題主要功能完成後再加入，不需要第一版就收斂。

第一版建議：

```text
使用預設 NACL 或較寬鬆 NACL
主要資安控管交給 Security Group
```

正式版後續可加入：

```text
Public NACL
Private App NACL
Private Data NACL
```

原因：

```text
NACL 是 stateless
若一開始設太嚴，容易造成 EKS、ALB、RDS、NAT、SSM 連線 timeout
不利初期排錯
```

---

## 10. Security Group 設計

Security Stack 建議建立以下 Security Group。

### 10.1 ALB Security Group

用途：

```text
外部使用者透過 HTTP / HTTPS 進入網站
```

Inbound：

```text
80  from 0.0.0.0/0
443 from 0.0.0.0/0
```

Outbound：

```text
To VPC CIDR 或 EKS Node SG
```

### 10.2 EKS Cluster Security Group

用途：

```text
EKS Control Plane 使用
```

Outbound：

```text
Allow all
```

### 10.3 EKS Node Security Group

用途：

```text
EKS Worker Node 與 Pod 使用
```

Inbound：

```text
From ALB SG to 80 / 443
Node SG self-reference allow all
From EKS Cluster SG allow control plane communication
```

Outbound：

```text
Allow all
```

### 10.4 RDS Security Group

用途：

```text
資料庫只允許 EKS Node 存取
```

Inbound：

```text
From EKS Node SG to 3306 or 5432
```

Outbound：

```text
To VPC CIDR
```

### 10.5 Engineer Security Group

不建議第一版建立 Engineer SG，也不建議開 SSH 22。

工程師維運改用：

```text
IAM
EKS Access Entry
kubectl
Helm
SSM Session Manager
```

---

## 11. SSM 維運設計

本專題不直接開放 SSH 22 port。

### 11.1 維運方式

```text
工程師
→ AWS Console / AWS CLI
→ Systems Manager Session Manager
→ Private Subnet 內節點或維運 EC2
```

### 11.2 需要的 IAM 權限

EKS Node Role 後續需加入：

```text
AmazonSSMManagedInstanceCore
```

### 11.3 Private Subnet 連線需求

第一版：

```text
Private Subnet → NAT Gateway → SSM
```

正式版可加入 VPC Endpoints：

```text
com.amazonaws.ap-south-1.ssm
com.amazonaws.ap-south-1.ssmmessages
com.amazonaws.ap-south-1.ec2messages
```

---

## 12. IAM 設計

IAM Stack 建議建立下列 Role。

| IAM Role | 用途 |
|---|---|
| EKS Cluster Role | EKS Control Plane 使用 |
| EKS Node Role | Worker Node 加入 EKS、使用 CNI、拉取 image、SSM 管理 |
| ALB Controller Role | AWS Load Balancer Controller 建立 ALB |
| App S3 Role | Web Pod 存取 S3 |
| K8sGPT / AI Role | K8sGPT、Lambda、Bedrock、SNS、S3 使用 |
| Engineer Role | 工程師維運 EKS |
| CodeBuild Role | Approve 後執行 kubectl 修正 |

EKS Node Role 建議加入：

```text
AmazonEKSWorkerNodePolicy
AmazonEKS_CNI_Policy
AmazonEC2ContainerRegistryReadOnly
AmazonSSMManagedInstanceCore
```

---

## 13. EKS Cluster 設計

### 13.1 Cluster 設定

```text
Cluster Name: eks-aiops-mumbai
Region: ap-south-1
EndpointPublicAccess: true
EndpointPrivateAccess: true
```

第一版可使用 Public Endpoint，但建議限制來源 IP。若因學習位置不固定，可先開放，但文件要註明正式環境需限制為公司固定 IP、VPN 或私有存取。

### 13.2 Subnet

EKS Cluster 使用：

```text
Private App Subnet A
Private App Subnet B
Private App Subnet C
```

必要時也可同時指定 Public Subnet 供整體 ELB discovery，但 Worker Node 建議放 Private App Subnet。

---

## 14. Managed Node Group 設計

### 14.1 Node Group

```text
NodegroupName: app-nodegroup
Subnets: 3 個 Private App Subnet
InstanceType: t3.medium 或 t3.large
DesiredSize: 3
MinSize: 3
MaxSize: 6
DiskSize: 30 GB
```

### 14.2 原則

```text
不開 SSH
不使用 Key Pair
透過 SSM 或 kubectl 維運
Node 分散於 3 個 AZ
```

---

## 15. 資料層設計

### 15.1 S3

用途：

```text
網站檔案
Log
K8sGPT 診斷報告
AI 分析結果
備份資料
```

設定：

```text
Block Public Access: Enabled
Versioning: Enabled
Encryption: Enabled
Bucket Policy: 僅允許指定 IAM Role 存取
```

### 15.2 RDS

用途：

```text
訂單資料
使用者資料
活動資料
系統資料
```

設定：

```text
Subnet: Private Data Subnet A/B/C
DB Subnet Group: 包含三個 Private Data Subnet
Public Access: false
Security Group: RDS SG
Engine: MySQL 或 PostgreSQL
Secret: Secrets Manager 保存帳密
Multi-AZ: 正式版建議啟用，練習版可先不啟用
```

### 15.3 Secrets Manager

用途：

```text
RDS 帳號密碼
LINE Token
API Key
其他敏感資訊
```

---

## 16. Kubernetes 資源設計

### 16.1 Namespace

```text
web-prod
aiops
```

### 16.2 Web App

第一版用 nginx：

```text
Deployment: web-demo
Service: ClusterIP
Ingress: ALB Ingress
Replicas: 3
```

後續可改自製電商首頁。

### 16.3 Ingress

```text
ingressClassName: alb
alb.ingress.kubernetes.io/scheme: internet-facing
alb.ingress.kubernetes.io/target-type: ip
alb.ingress.kubernetes.io/listen-ports: HTTP 80 first, HTTPS 443 later
```

### 16.4 AWS Load Balancer Controller

使用方式：

```text
IAM Role by CloudFormation
ServiceAccount by YAML / Helm
Controller by Helm
```

---

## 17. AIOps 設計

### 17.1 K8sGPT

部署位置：

```text
EKS Cluster 內
Namespace: aiops
形式: Pod / CronJob / Operator
```

偵測項目：

```text
CrashLoopBackOff
ImagePullBackOff
Pending
OOMKilled
Readiness probe failed
Service has no endpoints
Ingress ALB 建立失敗
S3 AccessDenied
RDS Connection Timeout
```

### 17.2 AWS Bedrock

用途：

```text
將 K8sGPT 診斷結果轉成白話原因、影響範圍、修復建議與建議指令
```

輸出格式建議：

```text
問題摘要
影響範圍
可能原因
建議修復方式
建議指令
風險提醒
是否建議自動修復
```

---

## 18. 告警通知設計

### 18.1 Email

使用：

```text
Amazon SNS
SNS Topic
Email Subscription
```

### 18.2 LINE

使用：

```text
AWS Lambda
LINE Messaging API
Secrets Manager 保存 LINE Token
```

### 18.3 通知內容

```text
Cluster 名稱
Namespace
異常類型
影響資源
AI 分析原因
修復建議
建議指令
Approve / Reject 連結
```

### 18.4 告警去重與冷卻機制 (DynamoDB Cache)

為避免因 Pod 連續崩潰（例如 `CrashLoopBackOff`）導致維運通道在短時間內遭灌爆（告警風暴），我們在 Lambda 的告警發送流程中設計「去重與冷卻機制」：

1. **快照存儲**：使用一張輕量型的 DynamoDB 表（`eks-aiops-demo-alert-cache`），主鍵為 `AlertHash`（結合 Namespace/ResourceName/ErrorType 的雜湊值），內含 `LastSentTime` 屬性。
2. **冷卻邏輯**：當 Lambda 接收到新告警時，先計算其雜湊值並向 DynamoDB 查詢：
   - 若在設定的冷卻時間內（例：15 分鐘）已發送過相同告警，則丟棄此次發信（冷卻攔截）。
   - 若已超過冷卻時間，或為全新告警，則更新/存入 DynamoDB 記錄，並照常觸發 SNS / LINE 發送告警。

---

## 19. 人工核准與修復設計

### 19.1 第一版

```text
只通知工程師
提供修復建議
由工程師手動執行修正
```

### 19.2 第二版

```text
通知內含 Approve / Reject
工程師 Approve 後
Lambda 觸發 CodeBuild
CodeBuild 執行 kubectl patch / apply
修正後再次執行 K8sGPT 驗證
```

### 19.3 不建議

```text
AI 偵測到問題後直接修改正式環境
```

原因：

```text
AI 可能誤判
正式環境修改需人工審核
需保留稽核紀錄
```

---

## 20. 水平擴展設計

### 20.1 HPA

用途：

```text
根據 CPU / Memory / Metrics 自動增加 Web Pod 副本數
```

第一版先做 HPA。

### 20.2 Cluster Autoscaler

用途：

```text
當 Pod 無法排程時，自動增加 Node
```

### 20.3 Karpenter

用途：

```text
更彈性地依 Pod 需求快速建立合適節點
```

建議順序：

```text
第一版: HPA
第二版: Cluster Autoscaler
第三版: Karpenter
```

---

## 21. CloudFormation Stack 拆分

建議拆成以下 Stack：

```text
01-network.yaml
02-security.yaml
03-iam.yaml
04-eks-cluster.yaml
05-nodegroup.yaml
06-data.yaml
07-access.yaml
08-aiops.yaml
```

### 21.1 Network Stack

建立：

```text
VPC
Public Subnet x3
Private App Subnet x3
Private Data Subnet x3
Internet Gateway
NAT Gateway with None / Single / MultiAZ condition
Route Table
Subnet Tags
```

### 21.2 Security Stack

建立：

```text
ALB SG
EKS Cluster SG
EKS Node SG
RDS SG
不建立 SSH Engineer SG
```

### 21.3 IAM Stack

建立：

```text
EKS Cluster Role
EKS Node Role
ALB Controller Role
App S3 Role
K8sGPT / AI Role
Engineer Role
CodeBuild Role
```

### 21.4 EKS Cluster Stack

建立：

```text
AWS::EKS::Cluster
EKS Addons (vpc-cni, kube-proxy, eks-pod-identity-agent)
EKS Control Plane Logging (audit, authenticator)
```

### 21.5 Node Group Stack

建立：

```text
AWS::EKS::Nodegroup
跨 3 AZ Private App Subnet
CoreDNS Addon (DependsOn: Nodegroup)
```

### 21.6 Data Stack

建立：

```text
S3
RDS
DB Subnet Group
Secrets Manager
```

### 21.7 Access Stack

建立：

```text
EKS Access Entry
Engineer namespace 權限
CI/CD 權限
```

### 21.8 AIOps Stack

建立：

```text
SNS
Lambda
EventBridge
API Gateway
CodeBuild
Bedrock 權限
S3 診斷報告區
DynamoDB (告警去重快取表)
```

---

## 22. Stack 建置順序

必須依順序建立：

```text
01 Network Stack
↓
02 Security Stack
↓
03 IAM Stack
↓
04 EKS Cluster Stack
↓
05 Node Group Stack
↓
06 Data Stack
↓
07 Access Stack
↓
08 AIOps Stack
↓
Kubernetes YAML / Helm 部署
```

原因：

```text
Security Stack 需要 VPC ID
EKS Stack 需要 Subnet IDs、Security Group IDs、IAM Role
Node Group 需要 EKS Cluster、Node Role、Private Subnet IDs
Data Stack 需要 Private Data Subnet IDs、RDS SG
Access Stack 需要 EKS Cluster
AIOps Stack 需要 IAM、S3、SNS、Lambda、EKS
```

---

## 23. Console 上傳 CloudFormation YAML 的操作方式

若使用 AWS Console 上傳 YAML：

1. 進入 AWS CloudFormation。
2. 點選 Create Stack。
3. 選擇 Upload a template file。
4. 上傳對應 YAML。
5. 輸入 Stack Name。
6. 在 Parameters 畫面選擇 VPC、Subnet、Security Group 或填入參數。
7. 確認 IAM Capability。
8. 建立 Stack。
9. 到 Events 查看建立狀態。
10. 建立完成後到 Outputs 複製輸出值，提供下一個 Stack 使用。

---

## 24. 專題 MVP

兩週內最小可行版本建議完成：

```text
1. CloudFormation 建 Network / Security / IAM / EKS / Node Group
2. EKS Node 跨 3 AZ Ready
3. AWS Load Balancer Controller 安裝成功
4. nginx Web App 部署成功
5. 外部使用者可透過 ALB DNS 瀏覽網站
6. K8sGPT 可偵測 ImagePullBackOff
7. Bedrock 可產生白話修復建議
8. SNS Email 可通知工程師
9. 文件、架構圖、使用者流程圖完成
```

---

## 25. 後續加分項目

```text
RDS 實際連線
S3 Pod Identity / IRSA
LINE 通知
Approve / Reject
CodeBuild 自動修復
HPA 壓測展示
Cluster Autoscaler
Karpenter
GitHub
ECR
CodeBuild
CodePipeline
Jenkins
自製電商頁面
ACM HTTPS
WAF
CloudWatch Dashboard
VPC Endpoint
NACL 收斂
```

---

## 26. AI 協作提示詞使用方式

後續若要請 AI 產生 YAML 或教學，請先提供本文件，並使用以下提示詞格式。

### 26.1 產生 CloudFormation YAML

```text
請根據本專題規格，幫我產生 [Stack 名稱] 的 CloudFormation YAML。

條件：
- Region: ap-south-1
- ProjectName: eks-aiops-demo
- 架構需符合本文件設計
- 使用 YAML 格式
- 每個資源要有清楚註解
- 必須包含 Parameters、Resources、Outputs
- 若需要引用其他 Stack 的值，請使用 Parameters 方式讓我在 Console 建 Stack 時手動選擇
- 不要使用 Nested Stack
- 不要一次產出全部 Stack，請只產出目前指定的 Stack
```

### 26.2 產生 Kubernetes YAML

```text
請根據本專題規格，幫我產生 Kubernetes YAML。

需求：
- Namespace: web-prod 或 aiops
- 適用 AWS EKS
- 包含 Deployment、Service、Ingress 或指定資源
- Ingress 使用 AWS Load Balancer Controller
- 需要註解說明每個欄位用途
- 不要使用過度複雜設定
```

### 26.3 產生部署教學

```text
請根據本專題規格，幫我產生下一階段部署教學。

需求：
- 以初學者可操作方式說明
- 每個步驟要有目的
- 每個指令要附上 # 註解
- 說明預期結果
- 說明常見錯誤與排查方式
```

### 26.4 產生除錯流程

```text
請根據本專題規格，幫我針對 [錯誤訊息] 產生排查流程。

需求：
- 說明可能原因
- 提供 kubectl / aws cli 檢查指令
- 每個指令要有 # 註解
- 說明每種結果代表什麼
- 提供修正方式
```

---

## 27. 目前已決定的重要設計原則

1. AWS Region 使用 `ap-south-1`。
2. 使用 3 個 AZ。
3. Public Subnet x3。
4. Private App Subnet x3。
5. Private Data Subnet x3。
6. EKS Node 放 Private App Subnet。
7. ALB 放 Public Subnet。
8. RDS 放 Private Data Subnet。
9. S3 放 VPC 外，作為區域型物件儲存。
10. NAT Gateway 使用 Parameter + Condition 控制 None / Single / MultiAZ。
11. NACL 可等專題主要功能完成後再收斂。
12. Security Group 為第一階段主要資安控管。
13. 不開 SSH 22。
14. 工程師維運使用 IAM、EKS Access Entry、kubectl、Helm、SSM。
15. Node Role 加入 SSM 權限。
16. AIOps 使用 K8sGPT + AWS Bedrock。
17. 告警先做 Email，後續可加 LINE。
18. 修復流程需人工核准。
19. 水平擴展先做 HPA，後續 Cluster Autoscaler / Karpenter。
20. AWS 基礎設施用 CloudFormation，Kubernetes 內部資源用 YAML / Helm。

---

## 28. 面試介紹用摘要

本專題以電商促銷活動高峰為情境，使用 AWS EKS 建立高可用網站平台，並透過 CloudFormation 管理 AWS 基礎架構。外部使用者透過 Internet-facing ALB 存取 EKS 上的網站服務，資料層使用 S3 與 RDS。

維運面導入 K8sGPT 與 AWS Bedrock，當 Kubernetes 發生異常時，系統會自動產生白話原因與修復建議，並透過 Email 或 LINE 通知工程師。為避免 AI 誤改正式環境，修復動作需由工程師核准後才會執行。

後續再結合 HPA、Cluster Autoscaler 或 Karpenter，使系統能因應電商活動期間的短時間流量高峰，形成一套具備高可用、可觀測、可告警、可輔助修復的 AIOps 雲端智能維運平台。
