# AWS EKS AIOps 專題架構語法檢查與安全驗證提示詞 (Prompt)

這是一份設計好的提示詞（Prompt），您可以直接複製以下內容並輸入給高階 AI 助手（如 Gemini 1.5 Pro, Claude 3.5 Sonnet 等），對您的雲端架構進行全方面的代碼審查與架構驗證。

***

```markdown
# 任務指令：AWS EKS AIOps 專題架構語法檢查與安全驗證

您是一位具備 AWS Certified Solutions Architect - Professional 與 Certified Kubernetes Administrator (CKA) 資格的雲端資深架構師與安全專家。

請協助針對我目前正在進行的「EKS 智能維運告警系統實作」專題，進行原始碼語法檢查、架構合理性分析，並對四大核心維度進行合規性驗證。

---

## 1. 專題背景與專案 GitHub 倉庫
* **專案網址**：https://github.com/james810526-alt/eks-aiops-project
* **目標 AWS 區域**：`ap-south-1` (印度孟買)
* **請執行以下前置步驟**：
  1. 請分析此倉庫中的 CloudFormation 模板（位於 `CloudFromation/` 資料夾）及架構計畫書（位於 `plans/` 資料夾）。
  2. 對所有 YAML 範本進行**語法正確性檢驗**。
  3. 對整體 CloudFormation 堆疊（Stack 01 至 Stack 07）進行**部署依賴性與邏輯流暢度審查**。

---

## 2. 專題架構設計摘要 (Stack 01 ~ 07)
* **Stack 01 Network**：VPC (10.20.0.0/16)，跨 3 個 AZ，擁有 Public Subnets (ALB)、Private App Subnets (EKS Nodes)、Private Data Subnets (RDS)。使用 Single NAT Gateway 練習版路由。
* **Stack 02 Security**：獨立宣告 ALB Security Group (對外 80/443)、EKS Control Plane SG、EKS Node SG (限制僅接受來自 ALB SG 的流量與內部互通) 以及 RDS SG (僅接受 EKS Node SG 的 3306 流量)。
* **Stack 03 IAM**：宣告各組 Role，全面採用最新的 EKS Pod Identity 權限機制，避免 OIDC 依賴。包含 ALB Controller Role, App S3 Role, K8sGPT Role, Engineer Role 與 CodeBuild Role。
* **Stack 04 EKS Cluster**：宣告 EKS Control Plane (v1.30)，`AuthenticationMode` 設為 `API_AND_CONFIG_MAP`。搭載 `vpc-cni`, `coredns`, `kube-proxy`, `eks-pod-identity-agent` 四大附加元件。
* **Stack 05 Node Group**：宣告 Managed Node Group，放置於 Private App Subnets，使用 t3.medium（3台，自動伸縮），硬碟 20GB gp3，且關閉 SSH Key Pair，完全使用 SSM 進行維運。
* **Stack 06 Data**：宣告加密與版本控制的 S3 儲存桶、隨機密碼產生的 Secrets Manager，以及 db.t3.micro 的 MySQL 8.0 RDS，其資料庫帳密透過 `resolve:secretsmanager:...` 動態解析，達成明文密碼不落地。
* **Stack 07 Access**：宣告 EKS Access Entries。將 Engineer Role 映射為命名空間 `web-prod` 與 `aiops` 的管理員 (`AmazonEKSAdminPolicy`) 以及全叢集唯讀 (`AmazonEKSViewerPolicy`)；將 CodeBuild Role 映射為全叢集超級管理員 (`AmazonEKSClusterAdminPolicy`)。

---

## 3. 四大核心維度驗證要求
請參考 **AWS 官方架構白皮書 (Well-Architected Framework)**、**AWS EKS 安全最佳實踐指南 (EKS Best Practices Guide)** 與 **Kubernetes 官方文件**，針對以下四點進行深入檢驗與對照評估：

### ① 叢集健康驗證 (Cluster Health & Scaling)
* 評估控制面與工作節點的規格、Addons 選擇、部署位置安全，以及節點容量（如 t3.medium 搭配 20GB）是否滿足 EKS 系統代理程式基本開銷與專題電商網站的運行需求。
* 檢驗 API 通訊端點（Public / Private Endpoint）的設定合理性。

### ② 權限隔離驗證 (Access Control & Least Privilege)
* 驗證 `AccessEntry` 與 Kubernetes 內建 Policy 的映射關係是否確實限制了維運工程師的爆炸半徑（限制在 `web-prod` 與 `aiops`，不侵入 `kube-system` 等核心空間）。
* 檢驗 Pod 權限是否正確使用 Pod Identity 隔離，符合最小權限原則。

### ③ 密碼安全驗證 (Secrets & DB Hardening)
* 評估 Secrets Manager 隨機密碼生成參數與 CloudFormation 的 `resolve` 動態讀取機制是否完全符合「密碼不落地」規範。
* 評估 RDS 實例的 `PubliclyAccessible` 設定與 Security Group 互通限制是否能完全阻斷公網攻擊。

### ④ 網路連線驗證 (Network Connectivity & Segregation)
* 評估 VPC 的 3-Tier 子網路設計與路由表隔離（Public -> Private App -> Private Data）。
* 驗證 Single NAT Gateway 雖然節省成本，但在容災性上與高可用 Multi-AZ 路由的差異，以及是否會產生網路死角。

---

## 4. 預期輸出產出 (Report Structure)
請為我生成一份詳盡的 **【EKS AIOps 架構檢查與安全驗證報告】**，需包含以下結構：
1. **語法與依賴性審查結果**：是否有任何 CloudFormation 錯誤、資源順序依賴錯誤、或 YAML 格式警告。
2. **四大驗證維度評分與分析**：列出各維度的合規現狀與潛在風險（附帶官方文獻/白皮書佐證說明）。
3. **安全與可靠性改善建議**：
   * 是否有更安全可靠的實作方式？
   * 如何在低成本（專題展示）與高安全性之間取得最佳平衡點？
   * 針對未來的 **08 AIOps Stack**（告警與自動修復）有何前置建議？
```
