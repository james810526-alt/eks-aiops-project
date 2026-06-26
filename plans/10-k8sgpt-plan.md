# 10 K8sGPT Stack - 智能診斷與監控資料來源建置計畫

本計畫紀錄了 EKS 智能維運專題中「K8sGPT 掃描器安裝與監控資料來源（Day 10）」的建置規劃、Helm 安裝步驟以及故障注入驗證流程，方便導入 Obsidian 閱讀與複習。

---

## 💡 費曼學習法：大樓巡邏警衛與被監控的電商商家

當我們在 AWS 上蓋好了 VPC 網路與 EKS 叢集大樓，且 Lambda 自動修復大腦也準備就緒後，我們要如何讓大樓內的異常事件自動申報上去？這需要「被監控的商家」與「巡邏警衛」。

### 1. 📦 被監控的商家 (web-demo 網頁 App)
* **比喻**：**大樓內新入駐的百貨店家（Nginx 網頁）。**
* **用途**：它是我們專題系統中運行的業務主體。在 Demo 時，我們需要故意讓這家店發生意外（注入錯誤，如將網頁鏡像改成不存在的版本），使其產生 `ImagePullBackOff` 故障。這個故障的狀態就是我們 AIOps 系統的**監控資料來源**。

### 2. 🩺 巡邏警衛與自動申報器 (K8sGPT Operator)
* **比喻**：**大樓管理處派駐的巡邏警衛。**
* **用途**：
  * **日常巡邏**：它會在 EKS 內不斷掃描所有 Pod、Service 與 Ingress，檢查是否有商家漏水或失火（出現異常狀態）。
  * **智慧診斷**：如果它發現 Pod 崩潰，它會使用它的證件（EKS Pod Identity 綁定的 `K8sGptRole`）打電話給高級顧問（AWS Bedrock）進行第一時間的日誌分析。
  * **緊急通報**：同時，它會將事件摘要整理好，打電話到大樓值班室（API Gateway 的 `/webhook` 端點），通報 Lambda 大腦啟動自動修復審批。

---

## 🏗️ 系統架構設計

```
    EKS Cluster (VPC Private Subnet)
┌──────────────────────────────────────────────┐
│  [aiops Namespace]                           │
│  ┌──────────────────┐     Access Bedrock     │
│  │ K8sGPT Pod       ├──────────────────────┼─────┐
│  │ (巡邏警衛)        │                      │     │
│  └────────┬─────────┘                      │     │
│           │                                │     │
│           │ Report Error                    │     │   AWS VPC Private Link
│           ▼                                │     │  ┌──────────────────────┐
│  [web-prod Namespace]                      │     ├──► Bedrock VPC Endpoint │
│  ┌──────────────────┐                      │     │  └──────────────────────┘
│  │ web-demo Pod     │                      │     │
│  │ (注入故障:1.999)  │                      │     │
│  └──────────────────┘                      │     │
└────────────────────────────────────────────┼─────┘
                                             │
                               Send Webhook  │          AWS Public Network
                                             ▼        ┌──────────────────────┐
                                             └───────►│ API Gateway (HTTPS)  │
                                                      │ (/webhook)           │
                                                      └──────────────────────┘
```

---

## 🛠️ 部署指南 (透過 SSM 跳板機連線部署)

由於我們的 EKS 控制面是完全私有化的，**請務必登入 SSM 跳板機進行以下 Helm 安裝與 YAML 套用**：

### 步驟 1：登入 SSM 跳板機
在您本地電腦的 PowerShell 中執行（請將 `<BastionInstanceId>` 替換為 Stack 05 輸出的 ID）：
```powershell
aws ssm start-session `
  --target <BastionInstanceId> `
  --region ap-south-1 `
  --profile nkc201-17-sso
```
進入跳板機後，執行以下指令以連線配對 EKS：
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ENGINEER_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/eks-aiops-demo-engineer-role"

aws eks update-kubeconfig \
  --region ap-south-1 \
  --name eks-aiops-mumbai \
  --assume-role-arn "$ENGINEER_ROLE_ARN" \
  --role-arn "$ENGINEER_ROLE_ARN"
```

### 步驟 2：使用 Helm 安裝 K8sGPT Operator
在跳板機終端機中執行：
```bash
# 若是新 SSM session，先確認 kubectl 路徑
export PATH=$HOME/bin:$PATH

# 1. 新增 K8sGPT Helm 倉庫
helm repo add k8sgpt https://charts.k8sgpt.ai/
helm repo update

# 2. 建立命名空間並安裝 Operator
helm install k8sgpt-operator k8sgpt/k8sgpt-operator   --namespace aiops   --create-namespace
```

### 步驟 3：部署 web-demo 監控目標
將 `Kubernetes/web-prod-app.yaml` 與 `Kubernetes/deploy-web-prod.sh` 上傳至跳板機同一目錄。從 Stack 02 Output 取得 `AlbSecurityGroupId`，由腳本驗證並注入 Ingress 後再套用：
```bash
chmod +x deploy-web-prod.sh
./deploy-web-prod.sh sg-xxxxxxxxxxxxxxxxx apply
```
* **驗證**：執行 `kubectl get pods -n web-prod`，確認有 3 個 `web-demo` Pod 處於 `Running` 狀態，且 ALB Ingress 已順利建立。

> [!NOTE]
> web-demo 使用 `ingressClassName: alb`。最新版 `Kubernetes/web-prod-app.yaml` 已包含 `IngressClass/alb`，controller 為 `ingress.k8s.aws/alb`。若缺少此物件，K8sGPT 會產生 `ingress class alb does not exist` 的診斷結果。

### 步驟 4：設定 K8sGPT 與 Webhook 對接
1. 查詢您的 API Gateway 網址（可由 Stack 08 輸出取得，如 `https://a1b2c3d4.execute-api.ap-south-1.amazonaws.com`）。
2. 在跳板機中編輯 `Kubernetes/k8sgpt-operator-config.yaml`，將 `Secret` 內的 `url` 替換為您的 API Gateway 網址後方加上 `/webhook?token=eks-aiops-webhook-secret-token`（必須帶上安全權限 Token 以防範非法惡意調用與費用刷爆）。
3. 部署 K8sGPT 配置：
```bash
kubectl apply -f k8sgpt-operator-config.yaml
```
* **驗證**：執行 `kubectl get pods -n aiops`，確認 K8sGPT Operator 運行正常。

> [!IMPORTANT]
> 最新版 `k8sgpt-operator-config.yaml` 需保留以下設計：
> - 不使用 `spec.serviceAccountName`，因 K8sGPT CRD `v1alpha1` 不支援該欄位。
> - 明確指定 `repository: ghcr.io/k8sgpt-ai/k8sgpt` 與 `version: v0.4.32`，避免新 Pod 出現 `InvalidImageName`。
> - Sink 使用 `type: cloudevents`。
> - Pod Identity 綁定的是 Operator 實際產生的 ServiceAccount `aiops/k8sgpt-aiops`，不是舊版規劃中的 `k8sgpt-sa`。
> - Anthropic Claude 3 Haiku 首次使用前需在 Bedrock Console 提交 use case details。

---

## 🧪 故障注入與資料來源驗證 (Live Demo)

當上述安裝完成後，我們可以透過以下方式模擬故障，驗證 Webhook 資料來源是否成功對接並觸發 AI 診斷：

### 1. 注入 ImagePullBackOff 故障
在跳板機中執行：
```bash
kubectl set image deployment/web-demo web-demo=nginx:1.999 -n web-prod
```
* **預期結果**：
  * 執行 `kubectl get pods -n web-prod` 會看到 Pod 變為 `ImagePullBackOff`。
  * K8sGPT 會在 10 秒內偵測到此異常，並向 API Gateway `/webhook` 發送 JSON 警報。
  * 檢查 AWS Lambda 日誌，會看到成功接收警報，並由 Bedrock 產出中文報告，最後發送 Approve/Reject 郵件至工程師信箱。

### 2. 注入 Service Selector 不匹配故障
在跳板機中執行：
```bash
kubectl patch svc web-demo-service -n web-prod -p '{"spec":{"selector":{"app":"web-wrong"}}}'
```
* **預期結果**：
  * 前台網頁連線顯示 503 服務無法使用，但 Pod 依然是 Running。
  * K8sGPT 會檢測到 `Service has no endpoints` 的異常，並將警報發送給 Lambda / Bedrock。
  * 您會收到郵件警告 Service Selector 標籤不匹配，並附帶 `kubectl patch` 的自動修復連結。

---

## 🔒 資安設計防護亮點

1. **Pod Identity 凭證不落地**：K8sGPT Operator 的 Pod 不需要設定 AWS IAM 永久金鑰（如 AccessKey），而是直接借用 ServiceAccount `k8sgpt-aiops` 被 AWS 授權的臨時憑證，安全防護力達到 AWS 生產級標準。
2. **過濾器精確收斂**：在 `k8sgpt-operator-config.yaml` 中，我們限制了掃描器只關注 `Pod`、`Service` , `Ingress` 與 `ReplicaSet`。這能有效過濾掉無關的 K8s 系統內部事件，避免產生不必要的 AWS Bedrock API 呼叫額度浪費。
3. **Webhook 加密保護**：Webhook 的目標 API 網址儲存在 Kubernetes `Secret` 內，在 Pod 中運行時動態載入，防止內部設定檔外流時暴露對外接口端點。
4. **Webhook 安全權限 Token 驗證**：在對外的 `/webhook` 端點引進密鑰查驗機制（查詢參數須包含 `token=eks-aiops-webhook-secret-token`），Lambda 才會受理並調用 Bedrock，藉此杜絕未授權的虛假告警請求，防範 API 遭騷擾與費用濫用。

---

## ✅ 2026-06-26 實測除錯重點

| 問題 | 現象 | 修正 |
|---|---|---|
| SSM 連線區域錯誤 | `TargetNotConnected` | `aws ssm start-session` 明確加上 `--region ap-south-1` |
| Bastion 缺 kubectl | `kubectl: command not found` | 下載 v1.34.0 到 `$HOME/bin` 並 `export PATH=$HOME/bin:$PATH` |
| K8sGPT CRD 欄位錯誤 | `unknown field "spec.serviceAccountName"` | 移除該欄位，改由 EKS Pod Identity association 綁實際 ServiceAccount |
| Bedrock 權限錯誤 | log 顯示 `eks-node-role` 無 `bedrock:InvokeModel` | Stack07 將 `K8sGptRoleArn` 綁到 `aiops/k8sgpt-aiops` |
| K8sGPT Pod 起不來 | `InvalidImageName` | 在 K8sGPT CR 加上 `repository` 與 `version: v0.4.32` |
| Bedrock 模型未啟用 | `Model use case details have not been submitted` | 到 Bedrock Claude 3 Haiku 頁面送出 use case details |
| K8sGPT 報 IngressClass | `ingress class alb does not exist` | 建立 `IngressClass/alb`，controller 為 `ingress.k8s.aws/alb` |
