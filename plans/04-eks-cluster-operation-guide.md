# 04 EKS Cluster - 本地連線操作指南

本指南將指導您如何在 Windows 本地電腦上安裝必備工具（`kubectl`、`AWS CLI`），並配置它們以連線並遙控遠端在 AWS 孟買的 EKS 叢集。

## 💡 費曼學習法：遙控器與電視的配對

- **遠端 EKS 叢集** 就像是一台放置在 AWS 孟買機房的 **「電視 (TV)」**。
- **本地電腦上的 `kubectl`** 就像是您手上的 **「遙控器」**。
- **配置與登入動作** 就像是 **「把遙控器與電視進行藍牙配對」** 的過程。
  配對成功後，您就能在本地按下按鈕（輸入指令），直接切換或控制遠端電視的畫面。

---

## 🛠️ 本地電腦設定步驟 (PowerShell)

請在您本地的 Windows 電腦上開啟 **PowerShell** 視窗，並依序執行以下步驟：

### 1. 安裝本地遙控器 (kubectl)
Windows 已經內建了軟體套件管理器 `winget`，我們可以直接呼叫它來安裝：
```powershell
# 安裝 Kubernetes 控制工具 kubectl
winget install Kubernetes.kubectl
```
> [!NOTE]
> 安裝完畢後，請**關閉並重新打開**您的 PowerShell 視窗，讓環境變數生效。
> 重新開啟後，可以輸入以下指令檢查是否安裝成功：
> ```powershell
> kubectl version --client
> ```
> 如果畫面有出現 Client Version 資訊（如 v1.30.x），代表安裝完成！

---

### 2. 安裝與設定 AWS CLI (身分驗證)
如果您的電腦還沒有安裝 AWS CLI，可以先透過以下指令安裝：
```powershell
# 安裝 AWS CLI 工具
winget install Amazon.AWSCLI
```
安裝完成重開視窗後，您需要進行身分驗證。這取決於您使用的是 **傳統 IAM 使用者金鑰** 還是 **AWS SSO (IAM Identity Center)**：

#### 🟢 做法 A：使用傳統 IAM User Access Keys (最常見)
這種做法是使用 IAM 服務中建立的永久性 Access Key。
1. 前往 AWS Console -> **IAM** -> **Users** -> 點擊您的使用者名稱。
2. 切換到 **Security credentials** 頁籤，找到 **Access keys** 並點選 **Create access key**。
3. 取得您的 `Access Key ID` 與 `Secret Access Key`。
4. 在 PowerShell 執行以下指令進行登入：
   ```powershell
   aws configure
   ```
5. 依提示填入資訊（輸入後按 Enter）：
   - `AWS Access Key ID [None]`: **輸入您的 AWS 金鑰 ID**
   - `AWS Secret Access Key [None]`: **輸入您的 AWS 密鑰**
   - `Default region name [None]`: `ap-south-1` *(我們專題的孟買區域)*
   - `Default output format [None]`: `json`

#### 🟢 做法 B：使用 AWS SSO (IAM Identity Center)
如果您的帳號是由學校、公司或 AWS Control Tower 派發的 SSO 帳號，請使用此方式：
1. 在 PowerShell 執行以下指令：
   ```powershell
   aws configure sso
   ```
2. 依提示填入您的 SSO 資訊：
   - `SSO session name [sso-session]`: *(自訂一個連線名稱，直接按 Enter 即可)*
   - `SSO start URL [None]`: **輸入您的 SSO 入口網址** (例如 `https://d-xxxxxx.awsapps.com/start`)
   - `SSO region [None]`: **輸入您的 SSO 所在區域** (通常為 `us-east-1` 或 `ap-southeast-1`，視您的 SSO 服務建在哪裡而定)
3. 執行後會自動跳出瀏覽器，請在網頁上點擊 **Confirm and Allow** 授權登入。
4. 網頁授權成功後，回到 PowerShell 選擇您要使用的 AWS 帳號與角色，並將預設區域設為 `ap-south-1`。

---

### 3. 下載配對設定檔 (update-kubeconfig)
當您的 EKS 叢集 CloudFormation 部署成功後，執行這行指令，將遠端 EKS 叢集的憑證與連線網址下載至本地電腦：
```powershell
# 配對本地遙控器與遠端 EKS
aws eks update-kubeconfig --region ap-south-1 --name eks-aiops-mumbai
```
- **指令白話解釋：** 「請 AWS 工具幫我把位於孟買區 (`ap-south-1`)、名字叫 `eks-aiops-mumbai` 的 EKS 控制大腦連線資料，同步到我這台電腦的遙控器設定檔 (`.kube/config`) 中。」
- **成功畫面：** 畫面會顯示類似 `Added new context arn:aws:eks:... to C:\Users\您的帳號\.kube\config`。

---

### 4. 開始操控您的 EKS 叢集！
配對成功後，您可以直接從您的本地電腦下指令來遙控遠端的 K8s 了：

#### 🟢 測試：查詢目前有哪些伺服器節點 (Nodes)
```powershell
kubectl get nodes
```
*(在您還沒有部署 Stack 05 Node Group 之前，此指令會返回 `No resources found`，這是正常的！當部署完節點後，就會顯示 3 台 EC2 執行個體狀態為 Ready)*

#### 🟢 測試：查詢目前運行中的基本應用程式 (Pods)
```powershell
# 查詢所有 Namespaces 下運行的 Pods 狀態
kubectl get pods -A
```
*(這會列出 coredns 與 aws-node 等 K8s 內建的底層管理系統 Pod 狀態)*

#### 🟢 測試：查詢目前叢集的網路埠口服務 (Services)
```powershell
kubectl get svc -A
```
*(這會顯示 `kubernetes` API server 本身的內網 IP 服務)*
