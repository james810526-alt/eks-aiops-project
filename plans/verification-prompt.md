# AWS EKS AIOps 專題架構語法檢查與安全驗證提示詞 (Prompt)

這是一份設計好的提示詞（Prompt），您可以直接複製以下內容並輸入給高階 AI 助手（如 Gemini 1.5 Pro, Claude 3.5 Sonnet 等），對您的雲端架構進行全方面的代碼審查與架構驗證。

***

```markdown
# 角色設定
您是一位資深的 **AWS 雲端架構師 (Solutions Architect)** 與 **DevSecOps 資深安全專家**，擁有豐富的 Amazon EKS、Kubernetes 安全防護實踐與 AIOps 自動化智能維運系統設計經驗。

# 任務指令
請扮演上述角色，審查以下提供的 AWS EKS AIOps 專案架構語法，並針對五大核心維度進行深度合規性驗證。

---

## 1. 專題背景與專案 GitHub 倉庫
* **專案網址**：https://github.com/james810526-alt/eks-aiops-project
* **目標 AWS 區域**：`ap-south-1` (印度孟買)
* **請執行以下前置步驟**：
  1. 請分析此倉庫中的 CloudFormation 模板（位於 `CloudFormation/` 資料夾）及架構計畫書（位於 `plans/` 資料夾）。
  2. 對所有 YAML 範本進行**語法正確性檢驗**。
  3. 對整體 CloudFormation 堆疊（Stack 01 至 Stack 08）進行**部署依賴性與邏輯流暢度審查**。

---

## 2. 專題架構設計摘要 (Stack 01 ~ 08)
* **Stack 01 Network**：VPC (10.20.0.0/16)，跨 3 個 AZ，擁有 Public Subnets (ALB)、Private App Subnets (EKS Nodes)、Private Data Subnets (RDS)。為了節省測試預算，路由採用 Single NAT Gateway 練習版設計。
* **Stack 02 Security**：獨立宣告 ALB Security Group (對外開放 80/443)。EKS Node Security Group 限制**放行來自 ALB Security Group 的所有 TCP 埠口 (0-65535)**，以相容多種 Pod 容器監聽埠（例如 8080）與健康檢查埠，防止 Target Group 發生 502 Bad Gateway 逾時。
* **Stack 03 IAM**：宣告各組 Role，全面採用最新的 EKS Pod Identity 權限機制。
  - **最小權限限制**：將 `AppS3Role` 與 `K8sGptRole` 的 S3 存取範圍精確收斂至 `eks-aiops-demo-${AWS::AccountId}-data-bucket`，並限制其 Secrets Manager 權限至本專案金鑰。
  - **信任政策限制**：為 `CodeBuildRole` 的 AssumeRole 政策加上 Condition 限制，規定只有專案開頭 (`eks-aiops-demo-*`) 的 CodeBuild 專案才能扮演此角色。
* **Stack 04 EKS Cluster**：宣告 EKS Control Plane (v1.34)，`AuthenticationMode` 設為 `API_AND_CONFIG_MAP`。
  - **端點安全**：設定為 `EndpointPublicAccess: false` 且 `EndpointPrivateAccess: true`（控制面完全私有化，杜絕公網威脅）。
  - **審計軌跡**：啟用 `audit` 與 `authenticator` 控制面日誌，傳送至 CloudWatch Logs 以記錄所有 API 行為。
  - **EKS Addons**：包含 `vpc-cni`, `kube-proxy`, `eks-pod-identity-agent`（CoreDNS Addon 已移出）。
* **Stack 05 Node Group**：宣告 Managed Node Group，放置於 Private App Subnets。
  - **OS 升級**：使用最新推薦的 `AL2023_x86_64_STANDARD` (Amazon Linux 2023)。
  - **避開 CoreDNS 逾時**：將 `CoreDnsAddon` 移動至本 Stack，並宣告 `DependsOn: EksNodeGroup`。確保節點 Ready 後才部署，解決因無節點無法排程造成的 CloudFormation 20 分鐘部署逾時。
  - **私有維運**：不設定 SSH Key Pair。部署了一台微型私有 `BastionHost` (t3.micro, AL2023)，完全透過 AWS SSM Session Manager 連線，由內網安全管理 EKS。
* **Stack 06 Data**：
  - **S3 Bucket**：啟用版本控制與 AES256 加密。
  - **RDS MySQL (db.t3.micro)**：啟用 `StorageEncrypted: true`（使用預設免費的 aws/rds KMS 金鑰）。啟用自動備份 `BackupRetentionPeriod: 7`。
  - **清理原則（刻意不設定）**：為避免展示用資料庫在 Stack 刪除時留下殘留快照導致額外計費，`DeletionPolicy` 設定為 `Delete`，且不開啟自動密碼輪替與 KMS CMK。
* **Stack 07 Access**：
  - **EKS Access Entry**：將 Engineer Role 映射為命名空間 `web-prod` 與 `aiops` 的管理員 (`AmazonEKSAdminPolicy`) 以及全叢集唯讀 (`AmazonEKSViewPolicy`)。
  - **CI/CD 爆炸半徑限制**：將 CodeBuild Role 在 EKS 的權限由原本的 Cluster-wide 叢集超管，**縮減為僅在命名空間 `web-prod` 與 `aiops` 中擁有 `AmazonEKSAdminPolicy`**，保護 `kube-system` 等核心空間。
  - **Pod Identity Associations**：宣告三組綁定，正式將 K8s ServiceAccounts 與 AWS IAM Roles 對接連線。
  - **K8sGPT Pod Identity 實測修正**：K8sGPT 掃描器實際使用 ServiceAccount `aiops/k8sgpt-aiops`，因此 `K8sGptRoleArn` 必須綁到 `k8sgpt-aiops`，不能綁到未被使用的 `k8sgpt-sa`。
* **Stack 08 AIOps**：宣告智能維運告警元件。
  - **告警廣播**：透過 Amazon SNS 發送電子郵件告警至工程師信箱（james810526@gmail.com）。
  - **防風暴快取**：宣告 DynamoDB 表作為告警冷卻快取，透過 TTL 設置 10 分鐘冷卻期以過濾重複的警報。
  - **運算核心**：使用 Python Lambda 運行於 VPC 私有子網路並套用 Node SG，實現內網安全通訊與 API 調用。Lambda 整合 Bedrock LLM 進行白話中文診斷與修復建議生成。
  - **報告輸出限制**：Lambda Bedrock prompt 應要求繁體中文回應，診斷報告約 600 個中文字內，並將 `max_tokens` 控制在 `700` 左右以降低不必要 token 消耗。
  - **Lambda 併發設定**：不得保留 `ReservedConcurrentExecutions: 2`，避免帳號最低未保留併發限制導致 `AioOpsHandler CREATE_FAILED`。
  - **對外入口**：使用 API Gateway 曝露 `/webhook`, `/approve`, 與 `/reject` 路由，實現 Webhook 接收與工程師點擊核准的互動入口。
  - **安全修復**：使用 AWS CodeBuild 作為維修機器人，同樣部署在 VPC 私有子網路，於接收到工程師核准指令後扮演 IAM 角色安全地以 `kubectl` 連線私有 EKS 進行修復。

* **Day 10 / K8sGPT 實測驗證**：
  - K8sGPT CR 不應包含 `spec.serviceAccountName`。
  - K8sGPT CR 需固定 `repository: ghcr.io/k8sgpt-ai/k8sgpt` 與 `version: v0.4.32`，避免 `InvalidImageName`。
  - Sink 使用 `cloudevents`，Webhook URL 由 Kubernetes Secret 提供，並帶上 `token=eks-aiops-webhook-secret-token`。
  - Bedrock Claude 3 Haiku 首次使用前需提交 Anthropic use case details。
  - web-demo 需包含 `IngressClass/alb`，controller 為 `ingress.k8s.aws/alb`。
  - 最終應確認 `kubectl get results -n aiops` 無非預期異常，K8sGPT log 不含 `AccessDenied`、`InvalidImageName`、`Model use case details`。

---

## 3. 五大核心維度驗證要求
請參考 **AWS 官方架構白皮書 (Well-Architected Framework)**、**AWS EKS 安全最佳實踐指南 (EKS Best Practices Guide)** 與 **Kubernetes 官方文件**，針對以下五點進行深入檢驗與對照評估：

### ① 叢集健康驗證 (Cluster Health & Scaling)
* 評估控制面與工作節點的規格、Addons 選擇、部署位置安全，以及節點容量（如 t3.medium 搭配 20GB）是否滿足 EKS 系統代理程式基本開銷與專題電商網站的運行需求。
* 檢驗將 CoreDNS Addon 移至 Node Group 階段並宣告 DependsOn，這項部署設計的合理性與成效。

### ② 權限隔離驗證 (Access Control & Least Privilege)
* 評估我們將 EKS API Server 完全私有化，並透過 SSM 登入私有跳板機（無 SSH）進行維運的架構安全性。
* 驗證 `AccessEntry` 與 Kubernetes 內建 Policy 的映射關係（包含 CodeBuild 限縮於專屬命名空間，Engineer 擁有特定空間 Admin 與全域 Viewer）是否符合最小權限原則。
* 評估 S3 資源路徑與 CodeBuild trust 信任政策的限制對整體爆炸半徑的收斂成效。

### ③ 密碼安全驗證 (Secrets & DB Hardening)
* 評估 Secrets Manager 隨機密碼生成參數與 CloudFormation 的 `resolve` 動態讀取機制是否完全符合「密碼不落地」規範。
* 評估 RDS 實例的儲存加密設定，以及我們基於學術展示考量（無 cross-account 共用快照需求，為節省帳單而採用 default KMS 金鑰、無 rotation、DeletionPolicy: Delete）這些架構取捨（Trade-offs）的合理性。

### ④ 網路連線驗證 (Network Connectivity & Segregation)
* 評估 VPC 的 3-Tier 子網路設計與路由表隔離（Public -> Private App -> Private Data）。
* 評估將 ALB 至 Node 的 Ingress 規則放大至放行所有 TCP 埠口（限制來源為 ALB SG）在功能支援與資安防護上的合理性。

### ⑤ 智能維運與自動化安全驗證 (AIOps & Remediation Security)
* 評估 Lambda 與 CodeBuild 同時在 VPC 私有網段中運行並共用 EKS Node SG 的安全風險與網路連線性合理性。
* 評估將 Lambda 權限限制在特定 SNS Topic、DynamoDB Cache Table 以及特定 CodeBuild 專案的最小權限設計。
* 評估藉由 DynamoDB TTL 實現 10 分鐘冷卻期來防止「告警風暴」的可靠性。
* 評估「人工審批（Approval Flow）」鏈的架構設計（API Gateway 觸發 CodeBuild）在防止 AI 誤操作與系統爆炸半徑控制上的安全價值。

### ⑤ 智能維運與自動化安全驗證 (AIOps & Remediation Security)
* 評估 Lambda 與 CodeBuild 同時在 VPC 私有網段中運行並共用 EKS Node SG 的安全風險與網路連線性合理性。
* 評估將 Lambda 權限限制在特定 SNS Topic、DynamoDB Cache Table 以及特定 CodeBuild 專案的最小權限設計。
* 評估藉由 DynamoDB TTL 實現 10 分鐘冷卻期來防止「告警風暴」的可靠性。
* 評估「人工審批（Approval Flow）」鏈的架構設計（API Gateway 觸發 CodeBuild）在防止 AI 誤操作與系統爆炸半徑控制上的安全價值。

---

## 4. 預期輸出產出 (Report Structure)
請為我生成一份詳盡的 **【EKS AIOps 架架構檢查與安全驗證報告】**，需包含以下結構：
1. **語法與依賴性審查結果**：是否有任何 CloudFormation 錯誤、資源順序依賴錯誤、或 YAML 格式警告。
2. **五大驗證維度評分與分析**：列出各維度的合規現狀與潛在風險（附帶官方文獻/白皮書佐證說明）。
3. **安全與可靠性改善建議**：
   * 是否有更安全可靠的實作方式？
   * 如何在低成本（專題展示）與高安全性之間取得最佳平衡點？
   * 評估我們實作的 **08 AIOps Stack**（包括 DynamoDB 快取去重、Bedrock LLM 診斷、API Gateway 對外入口、CodeBuild 內網修復）的整體架構合理性，並提供後續的優化方向（例如後續要串接 LINE API 或是 Secrets Manager 密鑰防護的整合建議）。
```�心空間。
  - **Pod Identity Associations**：宣告三組綁定，正式將 K8s ServiceAccounts 與 AWS IAM Roles 對接連線。

---

## 3. 五大核心維度驗證要求
請參考 **AWS 官方架構白皮書 (Well-Architected Framework)**、**AWS EKS 安全最佳實踐指南 (EKS Best Practices Guide)** 與 **Kubernetes 官方文件**，針對以下五點進行深入檢驗與對照評估：

### ① 叢集健康驗證 (Cluster Health & Scaling)
* 評估控制面與工作節點的規格、Addons 選擇、部署位置安全，以及節點容量（如 t3.medium 搭配 20GB）是否滿足 EKS 系統代理程式基本開銷與專題電商網站的運行需求。
* 檢驗將 CoreDNS Addon 移至 Node Group 階段並宣告 DependsOn，這項部署設計的合理性與成效。

### ② 權限隔離驗證 (Access Control & Least Privilege)
* 評估我們將 EKS API Server 完全私有化，並透過 SSM 登入私有跳板機（無 SSH）進行維運的架構安全性。
* 驗證 `AccessEntry` 與 Kubernetes 內建 Policy 的映射關係（包含 CodeBuild 限縮於專屬命名空間，Engineer 擁有特定空間 Admin 與全域 Viewer）是否符合最小權限原則。
* 評估 S3 資源路徑與 CodeBuild trust 信任政策的限制對整體爆炸半徑的收斂成效。

### ③ 密碼安全驗證 (Secrets & DB Hardening)
* 評估 Secrets Manager 隨機密碼生成參數與 CloudFormation 的 `resolve` 動態讀取機制是否完全符合「密碼不落地」規範。
* 評估 RDS 實例的儲存加密設定，以及我們基於學術展示考量（無 cross-account 共用快照需求，為節省帳單而採用 default KMS 金鑰、無 rotation、DeletionPolicy: Delete）這些架構取捨（Trade-offs）的合理性。

### ④ 網路連線驗證 (Network Connectivity & Segregation)
* 評估 VPC 的 3-Tier 子網路設計與路由表隔離（Public -> Private App -> Private Data）。
* 評估將 ALB 至 Node 的 Ingress 規則放大至放行所有 TCP 埠口（限制來源為 ALB SG）在功能支援與資安防護上的合理性。

### ⑤ 智能維運與自動化安全驗證 (AIOps & Remediation Security)
* 評估 Lambda 與 CodeBuild 同時在 VPC 私有網段中運行並共用 EKS Node SG 的安全風險與網路連線性合理性。
* 評估將 Lambda 權限限制在特定 SNS Topic、DynamoDB Cache Table 以及特定 CodeBuild 專案的最小權限設計。
* 評估藉由 DynamoDB TTL 實現 10 分鐘冷卻期來防止「告警風暴」的可靠性。
* 評估「人工審批（Approval Flow）」鏈的架構設計（API Gateway 觸發 CodeBuild）在防止 AI 誤操作與系統爆炸半徑控制上的安全價值。

---

## 4. 預期輸出產出 (Report Structure)
請為我生成一份詳盡的 **【EKS AIOps 架構檢查與安全驗證報告】**，需包含以下結構：
1. **語法與依賴性審查結果**：是否有任何 CloudFormation 錯誤、資源順序依賴錯誤、或 YAML 格式警告。
2. **四大驗證維度評分與分析**：列出各維度的合規現狀與潛在風險（附帶官方文獻/白皮書佐證說明）。
3. **安全與可靠性改善建議**：
   * 是否有更安全可靠的實作方式？
   * 如何在低成本（專題展示）與高安全性之間取得最佳平衡點？
   * 評估我們實作的 **08 AIOps Stack**（包括 DynamoDB 快取去重、Bedrock LLM 診斷、API Gateway 對外入口、CodeBuild 內網修復）的整體架構合理性，並提供後續的優化方向（例如後續要串接 LINE API 或是 Secrets Manager 密鑰防護的整合建議）。
```

