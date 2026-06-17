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

##### 1. 初次設定時 (建立 Profile)
1. 在 PowerShell 執行以下指令：
   ```powershell
   aws configure sso
   ```
2. 依提示填入您的 SSO 資訊：
   - `SSO session name [sso-session]`: *(自訂一個連線名稱，直接按 Enter 即可)*
   - `SSO start URL [None]`: **輸入您的 SSO 入口網址** (例如 `https://d-xxxxxx.awsapps.com/start`)
   - `SSO region [None]`: **輸入您的 SSO 所在區域** (通常為 `us-east-1` 或 `ap-southeast-1`，視您的 SSO 服務建在哪裡而定)
3. 執行後會自動跳出瀏覽器，請在網頁上點擊 **Confirm and Allow** 授權登入。
4. 網頁授權成功後，回到 PowerShell 選擇您要使用的 AWS 帳號與角色，並在最後提示命名 CLI profile name 時輸入一個您好記的名稱（例如 `james-dev`），並將預設區域設為 `ap-south-1`。

##### 2. 日後登入時 (直接使用 Profile 登入)
如果您以前就已經完成上述設定，日後重新開機或登入過期時，**不需要重複設定**，直接執行此指令即可快速觸發瀏覽器進行登入：
```powershell
aws sso login --profile james-dev
```
*(請將 `james-dev` 替換為您當初命名的 Profile 名稱)*

* **日後執行指令方式：**
  當您使用此 Profile 登入後，後續所有 AWS 指令後面都要加上 `--profile` 參數以指定身分：
  ```powershell
  aws ec2 describe-vpcs --profile james-dev
  ```
* **懶人免打 Profile 小技巧：**
  如果覺得每次都要加上 `--profile` 太麻煩，可以在當前 PowerShell 視窗先執行一次這行環境變數設定：
  ```powershell
  $env:AWS_PROFILE="james-dev"
  ```
  執行後，該視窗內後續所有的 AWS 指令（包含 `aws eks update-kubeconfig` 等）都會預設直接以該 Profile 執行，不需再手動打 `--profile`。

---

### 3. 🔐 高安全架構：下載配對與連線說明 (透過 SSM 跳板機)

> [!IMPORTANT]
> **因為我們採取了「EKS 完全私有化」的高安全度架構：**
> 您的 EKS 叢集已經關閉了公網端點 (`EndpointPublicAccess: false`)。因此，**您無法直接從本地電腦執行 `kubectl` 連線到 EKS**，所有維運指令都必須透過我們在 Stack 05 部署的 **SSM Bastion Host (安全跳板機)** 進行轉發或登入操作。

#### 🟢 步驟 1：使用 SSM 登入私有跳板機 (無需 SSH 金鑰，免開 Port 22)
在本地電腦的 PowerShell 中，執行以下指令登入跳板機 (請將 `<BastionInstanceId>` 替換為 Stack 05 Outputs 輸出的 `BastionInstanceId`，例如 `i-xxxxxxxxxxxx`)：

```powershell
# 1. 確保已載入 AWS Profile 憑證
$env:AWS_PROFILE="nkc201-17-sso"

# 2. 啟動 SSM Session 登入跳板機
aws ssm start-session --target <BastionInstanceId>
```
*登入成功後，您會進入 Linux 的 shell 畫面（例如 `sh-5.2$` 或 `[ssm-user@ip-...]`）。*

---

#### 🟢 步驟 2：在跳板機內下載配對設定檔 (update-kubeconfig)
跳板機已自動附加了擁有 EKS 管理權限的 `EksNodeInstanceProfile` 證書。在跳板機的 Linux 終端機中，執行以下指令：

```bash
# 將跳板機與遠端私有 EKS 進行連線配對
aws eks update-kubeconfig --region ap-south-1 --name eks-aiops-mumbai
```
* **成功畫面：** 會顯示 `Added new context arn:aws:eks:... to /home/ssm-user/.kube/config`。

---

#### 🟢 步驟 3：開始在跳板機中操控您的 EKS 叢集！
現在您已身處安全內網中，可以直接在跳板機上下指令來操控 EKS：

```bash
# 1. 查詢工作節點狀態
kubectl get nodes

# 2. 查詢所有命名空間下的 Pods 狀態
kubectl get pods -A
```

---

### 5. 💡 補充：什麼是 `--capabilities CAPABILITY_NAMED_IAM`？
在部署 `03 IAM Stack` 時，您會在部署指令最後看到 `--capabilities CAPABILITY_NAMED_IAM`：
- **為什麼需要它：** 在 AWS 中，建立 IAM 角色（Role）或權限（Policy）是非常敏感的安全操作（代表發放可以進出系統的鑰匙）。為了防止開發人員無意間執行不明範本，建立出權限過大或有安全疑慮的角色，AWS 規定部署時必須有明確的「安全切結授權」。
- **比喻（大額提款切結書）：** 就像去銀行辦理大額提款或授權，櫃檯行員一定會遞上單子要求您「簽字蓋章確認」一樣。
  - **在網頁主控台 (Console)：** 部署最後一步時，您必須手動勾選網頁最底下的黃色方框「*我確認 AWS CloudFormation 可能會建立具有自訂名稱的 IAM 資源*」。
  - **在 CLI 命令列：** 由於沒有瀏覽器網頁可按，您必須主動在指令尾端加上 `--capabilities CAPABILITY_NAMED_IAM`。如果漏掉這個參數，AWS 會直接中斷部署並回傳 `Requires capabilities : [CAPABILITY_NAMED_IAM]` 的錯誤。

---

### 6. 💡 補充：Windows PowerShell 部署遇到文字編碼錯誤怎麼辦？
在 Windows 上使用 AWS CLI 部署 CloudFormation 時，如果您的 YAML 檔案內包含中文註解，可能會遇到以下錯誤：
`An error occurred (ParamValidation): Error parsing parameter '--template-body': Unable to load paramfile..., text contents could not be decoded. If this is a binary file, please use the fileb:// prefix instead of the fileb://...`

- **為什麼會這樣：** Windows 系統底層預設使用舊式 ANSI (CP950) 編碼，而我們的 YAML 檔案是用 UTF-8 儲存中文。當 AWS CLI 內部試圖解析 `file://` 時，會因為編碼衝突而失敗；若改用 `fileb://` 則會因為 AWS 限制 `--template-body` 只能接受「純文字字串」而報錯類型不符。
- **黃金解決方案：** 
  利用 PowerShell 的原生指令 `(Get-Content -Raw -Encoding UTF8)` 預先讀取檔案成 UTF-8 文字，再直接塞給 AWS CLI。
  
  **範例 A：部署 02 Security Stack**
  ```powershell
  aws cloudformation create-stack `
    --stack-name nkc201-17-security `
    --template-body (Get-Content CloudFromation/nkc201-17-02-security-stack.yaml -Raw -Encoding UTF8) `
    --parameters ParameterKey=VpcId,ParameterValue=vpc-00f9f872d1cede59e
  ```

  **範例 B：部署 03 IAM Stack**
  ```powershell
  aws cloudformation create-stack `
    --stack-name nkc201-17-iam `
    --template-body (Get-Content CloudFromation/nkc201-17-03-iam-stack.yaml -Raw -Encoding UTF8) `
    --capabilities CAPABILITY_NAMED_IAM
  ```

  **範例 C：部署 04 EKS Cluster Stack**
  ```powershell
  aws cloudformation create-stack `
    --stack-name nkc201-17-cluster `
    --template-body (Get-Content CloudFromation/nkc201-17-04-eks-cluster-stack.yaml -Raw -Encoding UTF8) `
    --parameters `
      ParameterKey=EksClusterRoleArn,ParameterValue=<您的EksClusterRoleArn> `
      ParameterKey=SecurityGroupIds,ParameterValue=<您的EksClusterSecurityGroupId> `
      ParameterKey=SubnetIds,ParameterValue=<PrivateAppSubnetA的ID>,<PrivateAppSubnetB的ID>,<PrivateAppSubnetC的ID>
  ```
