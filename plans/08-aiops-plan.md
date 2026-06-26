# 08 AIOps Stack - 智能維運與自動化告警建置計畫

本計畫紀錄了 EKS 智能維運專題中「AIOps 智能維運與自動化告警系統（Stack 08）」的建置規劃、核心元件設計與自動修復工作流。我們將透過結合 AWS Lambda、API Gateway、Amazon Bedrock、DynamoDB 快取、SNS 告警與 CodeBuild，實現「異常偵測 -> AI 診斷 -> 工程師審批 -> 自動修復」的完整閉環。

---

## 💡 費曼學習法：大樓警報、大腦調度員與維修機器人

當我們的 EKS 叢集運作時，就像是一棟繁忙的**電商百貨大樓**。如果突然有店家失火或水管漏水（Pod 異常），我們要如何讓大樓管理處即時反應，又不會引發混亂？

### 1. 📡 Amazon SNS (大樓廣播與警報器)
* **比喻**：**大樓的緊急廣播喇叭。**
* **用途**：當系統發生問題時，它負責第一時間向指定的工程師信箱（`james810526@gmail.com`）發送通知，就像廣播大聲呼叫：「維運工程師請注意，二樓發生漏水！」

### 2. 🗄️ DynamoDB 告警快取表 (重複通知過濾器)
* **比喻**：**值班室的「重複便條紙過濾器」。**
* **用途**：如果水管在 1 分鐘內噴水 100 次，現場路過的人會拼命打電話報警。如果沒有過濾，值班室的電話會被打爆，工程師也會收到 100 封垃圾簡訊（告警風暴）。
* **機制**：DynamoDB 當作快取登記簿。當第一個警報進來時，我們登記「水管漏水，有效期 10 分鐘（TTL）」。在接下來的 10 分鐘內，所有重複的「水管漏水」警報都會被直接過濾丟棄，讓工程師能專注於修復，而不是被通知淹沒。

### 3. 🧠 AWS Lambda (值班室的智能大腦)
* **比喻**：**大樓值班室的主任（調度員）。**
* **用途**：它是整個系統的核心。當它收到警報通知後：
  1. 它會把凌亂的警報拿去給**高級顧問**（Amazon Bedrock AI）翻譯。
  2. 生成附帶「核准（Approve）」與「拒絕（Reject）」網址連結的電子郵件，透過廣播器（SNS）發給工程師。
  3. 收到工程師的核准指令後，對**維修機器人**（CodeBuild）下達修復命令。

### 4. 📖 Amazon Bedrock (資深顧問)
* **比喻**：**值班室外聘的「外籍資深工程顧問」。**
* **用途**：Kubernetes 報錯時常是密密麻麻的英文代碼（例如：`CrashLoopBackOff: back-off 5m0s restarting failed container`）。這位 AI 顧問會將這些生硬的錯誤轉換成**白話中文**：「報告工程師，這是因為資料庫連線超時，請檢查密碼與網路設定。」並提供具體的修復指南。

### 5. 🚪 Amazon API Gateway (值班室的對外櫃檯)
* **比喻**：**值班室的「感應大門與對外收發櫃檯」。**
* **用途**：EKS 叢集內部的診斷工具（K8sGPT）可以把警報送到這個櫃檯（`/webhook`），工程師也可以透過手機點選信中的核准按鈕（`/approve`）來回傳指令給 Lambda 大腦。

### 6. 🤖 AWS CodeBuild (維修機器人)
* **比喻**：**值班室的「自動維修機器人」。**
* **用途**：為了保障安全，我們的電商大樓內部通道（EKS API Server）完全是封閉的（Private Control Plane）。這台維修機器人因為被安置在**大樓內部網段**（VPC Private Subnet）中，所以能安全地使用 `kubectl` 工具進入叢集執行修復，例如重新啟動 Pod 或更新設定檔。

---

## 🏗️ AIOps 智能維運工作流 (Workflow)

```mermaid
sequenceDiagram
    autonumber
    participant K as EKS Cluster (K8sGPT)
    participant APIGW as API Gateway
    participant L as Lambda (AIOps Handler)
    participant D as DynamoDB (Alert Cache)
    participant B as Amazon Bedrock (LLM)
    participant SNS as Amazon SNS
    participant Eng as Engineer (Email)
    participant CB as AWS CodeBuild (Remediation)

    K->>APIGW: 1. POST /webhook (送出異常警報)
    APIGW->>L: 2. 觸發 Lambda
    L->>D: 3. 原子寫入快取鎖 (Condition check: 若 AlertHash 存在且未過期則阻擋)
    alt 寫入失敗 (冷卻中/分析中)
        L-->>APIGW: 4a. 回傳 200 (直接丟棄重複告警)
    else 首次發生 / 已過冷卻期 (寫入成功，鎖定為 ANALYZING)
        L->>B: 5. 請求 Bedrock 分析錯誤原因並輸出結構化 Action JSON
        B-->>L: 6. 回傳白話文報告與 Action JSON
        L->>L: 7. 驗證 Action JSON (檢查白名單與防注入字元)
        L->>D: 8. 更新快取狀態為 PENDING，並存入一次性 Token 與安全修復指令
        L->>SNS: 9. 發送告警郵件 (附帶隨機 Token 認證的 Approve / Reject 連結)
        SNS-->>Eng: 10. 電子郵件通知
    end

    Note over Eng, L: 工程師閱讀報告並點擊郵件中的 Approve 連結 (驗證 Token 與 PENDING 狀態)

    Eng->>APIGW: 11. GET /approve?hash=...&token=...
    APIGW->>L: 12. 觸發 Lambda 驗證 Token 且狀態為 PENDING
    alt 驗證失敗 (過期 / Token 不符 / 已執行)
        L-->>Eng: 13a. 回傳錯誤頁面 (拒絕執行)
    else 驗證成功
        L->>D: 13b. 更新狀態為 APPROVED (防重複點擊)
        L->>CB: 14. 啟動 CodeBuild 專案 (傳入安全指令)
        CB->>CB: 15. 下載指定 v1.34.0 kubectl 並進行 SHA256 驗證
        CB->>K: 16. 於 VPC 內網安全執行 kubectl 指令
        CB-->>L: 17. 回報修復結果
        L->>SNS: 18. 發送修復成功通知
        SNS-->>Eng: 19. 工程師收到修復完成信件
    end
```

---

## 🛠️ 完整的 CloudFormation 藍圖

已寫入：`CloudFormation/nkc201-17-08-aiops-stack.yaml`

> [!IMPORTANT]
> **2026-06-26 實作更新**
> - 最新範本已移除 Lambda `ReservedConcurrentExecutions`。實測帳號若保留 `ReservedConcurrentExecutions: 2`，會因帳號最低未保留併發限制 `[10]` 而導致 `AioOpsHandler CREATE_FAILED`。
> - Lambda 呼叫 Bedrock 的 prompt 已要求以繁體中文輸出，並限制診斷報告約 600 個中文字內，避免報告過長與 token 浪費。
> - Bedrock `max_tokens` 已調整為 `700`。
> - Anthropic Claude 3 Haiku 在首次使用前需要到 Bedrock Console 提交 **Submit use case details**；若未提交，K8sGPT 或 Lambda 呼叫會出現 `Model use case details have not been submitted for this account`。

---

## 💻 部署與驗證步驟

### 1. 執行 CloudFormation 部署

請在您的專題資料夾下開啟 **WSL (Bash)** 執行以下指令進行部署：

```bash
# 1. 鎖定登入 Profile
export AWS_PROFILE="nkc201-17-sso"

# 2. 獲取 VPC ID (從 Stack 01 輸出查詢)
VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name nkc201-17-01-network-stack \
  --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue" \
  --output text \
  --region ap-south-1)

# 3. 獲取 3 個 Private App Subnet ID 並以逗號連接 (正確查詢 PrivateAppSubnetAId/BId/CId)
SUBNET_A=$(aws cloudformation describe-stacks --stack-name nkc201-17-01-network-stack --query "Stacks[0].Outputs[?OutputKey=='PrivateAppSubnetAId'].OutputValue" --output text --region ap-south-1)
SUBNET_B=$(aws cloudformation describe-stacks --stack-name nkc201-17-01-network-stack --query "Stacks[0].Outputs[?OutputKey=='PrivateAppSubnetBId'].OutputValue" --output text --region ap-south-1)
SUBNET_C=$(aws cloudformation describe-stacks --stack-name nkc201-17-01-network-stack --query "Stacks[0].Outputs[?OutputKey=='PrivateAppSubnetCId'].OutputValue" --output text --region ap-south-1)
PRIVATE_SUBNETS="${SUBNET_A},${SUBNET_B},${SUBNET_C}"

# 4. 部署 AIOps Stack (Stack 08)
aws cloudformation deploy \
  --template-file CloudFormation/nkc201-17-08-aiops-stack.yaml \
  --stack-name nkc201-17-08-aiops-stack \
  --parameter-overrides \
      VpcId="$VPC_ID" \
      PrivateSubnetIds="$PRIVATE_SUBNETS" \
      EngineerEmail="james810526@gmail.com" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-south-1
```

### 2. 驗證步驟與測試流程

> [!IMPORTANT]
> **步驟一：確認 SNS 訂閱**
> 部署完成後，AWS 會向 `james810526@gmail.com` 發送一封主旨為 `AWS Notification - Subscription Confirmation` 的郵件。請務必打開並點擊 **"Confirm subscription"** 連結。

> [!IMPORTANT]
> **步驟二：確認 Amazon Bedrock 模型存取權**
> 本專題之 Lambda 與 K8sGPT 會在 `ap-south-1` 區域調用 `anthropic.claude-3-haiku-20240307-v1:0`。首次使用 Anthropic 模型前，需在 Amazon Bedrock 的 Claude 3 Haiku 頁面提交 **use case details**。送出後通常需等待數分鐘同步，實測錯誤訊息可能提示最多等待約 15 分鐘。請同時確認 AWS 帳戶無組織層級的 Service Control Policies (SCP) 阻擋 Bedrock 服務。

#### 🧪 測試 Webhook 與 AI 診斷
您可以透過跳板機或本機使用 `curl` 模擬 K8sGPT 發送錯誤：
```bash
# 1. 獲取 API Gateway 網址
API_URL=$(aws cloudformation describe-stacks \
  --stack-name nkc201-17-08-aiops-stack \
  --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
  --output text \
  --region ap-south-1)

# 2. 發送模擬 Pod 異常 (ImagePullBackOff) 到 Webhook
curl -X POST "${API_URL}/webhook" \
  -H "Content-Type: application/json" \
  -d '{"name": "nginx-web", "namespace": "web-prod", "error": "ImagePullBackOff: Failed to pull image nginx:1.999"}'
```

---

## 🔒 安全設計與爆炸半徑收斂 (Security Design & Radius Mitigation)

1. **網路完全隔離 (VPC Private Subnet & VPC Endpoints)**：自動修復 CodeBuild、執行診斷的 Lambda 部署於 VPC Private Subnet 中，無公網 Public IP。此外，部署了 AWS PrivateLink VPC Endpoints (Bedrock Runtime、STS、CloudWatch Logs)，使 Lambda 與 Bedrock 及 STS 的通訊完全維持在 AWS 內網，不經公網與 NAT Gateway。
2. **Lambda 最小 IAM 權限**：Lambda 權限嚴格限縮，僅限於向指定的 SNS Topic 發送訊息、讀寫與更新特定的 DynamoDB 快取表、以及呼叫特定的 CodeBuild 項目。
3. **防止告警風暴與並發重複呼叫 (原子鎖)**：使用 DynamoDB Atomic Conditional Put，當 webhook 進來時先搶鎖，避免在 Bedrock 運算期間 (2-3 秒) 有相同警報並發進來而重複呼叫 Bedrock 與發送告警信。
4. **安全一次性 Token 審查**：審批連結不再使用可預測的 AlertHash 作為唯一的驗證標識，而是結合隨機生成的 UUID 一次性 Token。Lambda 在審批時會嚴格驗證 Token 並實施狀態檢驗，僅允許 `PENDING` -> `APPROVED`/`REJECTED` 狀態轉移，點擊一次後狀態立即變更，徹底杜絕重複點擊或越權執行的安全隱患。
5. **嚴格白名單命令解析器**：Bedrock 被限制僅能輸出 structured JSON，由 Lambda 對其進行防注入檢查 (防 `;`、`&`、`|`、`` `、`$` 等字元與高危命令關鍵字) 與 Namespace 白名單校驗 (`web-prod` 與 `aiops` 命名空間)，再由 Lambda 依據安全模板組裝成固定格式的指令，徹底消除 `eval` 任意命令執行的漏洞。
6. **CodeBuild 安全加固**：CodeBuild 的 kubectl 被鎖定為與 EKS 叢集一致的 `v1.34.0` 版本，並在安裝時自動下載官方的 `.sha256` 校驗碼進行 SHA256 強制驗證，避免供應鏈劫持風險，同時移除了 eval，改為直接字串執行。
