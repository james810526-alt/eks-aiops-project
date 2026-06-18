# AWS CloudFormation 主控台一鍵部署指南 (EKS AIOps 專題)

為了減少在 WSL 或 PowerShell 終端機執行 CLI 指令時可能遇到的語法、編碼與認證問題，建議您**直接使用 AWS Web 主控台 (AWS Console)** 進行 CloudFormation 部署。

本指南提供 8 個 Stack 的完整部署順序、需上傳的範本路徑，以及在主控台設定參數時的具體操作步驟。

---

## 🗺️ 部署前的準備工作
1. 登入 [AWS 管理主控台](https://aws.amazon.com/console/)。
2. 確認右上角的區域鎖定在 **孟買 (ap-south-1)**。
3. 進入 **CloudFormation** 服務頁面。

---

## 🥞 8 大 Stacks 順序部署指引

### 1️⃣ Stack 01: 網路基礎建設 (Network Stack)
* **範本檔案路徑**：`CloudFromation/nkc201-17-01-network-stack.yaml`
* **主控台操作步驟**：
  1. 點選 **Create stack** ➔ **With new resources (standard)**。
  2. 選擇 **Upload a template file**，上傳 [nkc201-17-01-network-stack.yaml](file:///c:/Users/USER/Desktop/專題資料/CloudFromation/nkc201-17-01-network-stack.yaml)。
  3. **Stack name** 輸入：`nkc201-17-01-network-stack`。
  4. **Parameters** 參數設定：
     - `ProjectName`: 保留預設 `eks-aiops-demo`
     - `NatGatewayMode`: 選擇 `Single`（單一 NAT，節省專題測試成本）
     - `VpcCidr`: 保留預設 `10.20.0.0/16`
  5. 連續點選 **Next**，最後點選 **Submit**。
  6. ⚠️ **等待狀態轉為 `CREATE_COMPLETE`** 後，點選該 Stack 的 **Outputs (輸出)** 標籤頁，後續步驟將頻繁複製裡面的值。

---

### 2️⃣ Stack 02: 安全群組建設 (Security Stack)
* **範本檔案路徑**：`CloudFromation/nkc201-17-02-security-stack.yaml`
* **主控台操作步驟**：
  1. 點選 **Create stack** ➔ **With new resources**。
  2. 上傳 [nkc201-17-02-security-stack.yaml](file:///c:/Users/USER/Desktop/專題資料/CloudFromation/nkc201-17-02-security-stack.yaml)。
  3. **Stack name** 輸入：`nkc201-17-02-security-stack`。
  4. **Parameters** 參數設定：
     - `VpcId`: 貼上 Stack 01 Outputs 中的 `VpcId`。
  5. 點選 **Next** ➔ **Submit**，等待 `CREATE_COMPLETE`。

---

### 3️⃣ Stack 03: IAM 角色權限建設 (IAM Stack)
* **範本檔案路徑**：`CloudFromation/nkc201-17-03-iam-stack.yaml`
* **主控台操作步驟**：
  1. 點選 **Create stack** ➔ **With new resources**。
  2. 上傳 [nkc201-17-03-iam-stack.yaml](file:///c:/Users/USER/Desktop/專題資料/CloudFromation/nkc201-17-03-iam-stack.yaml)。
  3. **Stack name** 輸入：`nkc201-17-03-iam-stack`。
  4. **Parameters**：保留預設值。
  5. 點選 **Next** 來到最後確認頁面。
  6. ⚠️ **關鍵步驟**：在頁面最下方，勾選 **"I acknowledge that AWS CloudFormation might create IAM resources with custom names."** (確認允許建立 IAM 角色)，否則部署會失敗。
  7. 點選 **Submit**，等待 `CREATE_COMPLETE`。

---

### 4️⃣ Stack 04: EKS 叢集控制面 (EKS Cluster Stack)
* **範本檔案路徑**：`CloudFromation/nkc201-17-04-eks-cluster-stack.yaml`
* **主控台操作步驟**：
  1. 點選 **Create stack** ➔ **With new resources**。
  2. 上傳 [nkc201-17-04-eks-cluster-stack.yaml](file:///c:/Users/USER/Desktop/專題資料/CloudFromation/nkc201-17-04-eks-cluster-stack.yaml)。
  3. **Stack name** 輸入：`nkc201-17-04-eks-cluster-stack`。
  4. **Parameters** 參數設定：
     - `EksClusterRoleArn`: 貼上 Stack 03 Outputs 中的 `EksClusterRoleArn`。
     - `SecurityGroupIds`: 貼上 Stack 02 Outputs 中的 `EksClusterSecurityGroupId` (即 Cluster 與控制面專用 SG)。
     - `SubnetIds`: 貼上 Stack 01 Outputs 中的三個 Private App Subnets，以逗號分隔，例如：`subnet-11111,subnet-22222,subnet-33333`（分別對應 AId, BId, CId）。
  5. 點選 **Next** ➔ **Submit**。
  6. ☕ **注意**：EKS 控制面建立約需 **10-15 分鐘**，請耐心等候至 `CREATE_COMPLETE`。

---

### 5️⃣ Stack 05: 託管節點群組與跳板機 (Node Group Stack)
* **範本檔案路徑**：`CloudFromation/nkc201-17-05-nodegroup-stack.yaml`
* **主控台操作步驟**：
  1. 點選 **Create stack** ➔ **With new resources**。
  2. 上傳 [nkc201-17-05-nodegroup-stack.yaml](file:///c:/Users/USER/Desktop/專題資料/CloudFromation/nkc201-17-05-nodegroup-stack.yaml)。
  3. **Stack name** 輸入：`nkc201-17-05-nodegroup-stack`。
  4. **Parameters** 參數設定：
     - `NodeRoleArn`: 貼上 Stack 03 Outputs 中的 `EksNodeRoleArn`。
     - `SubnetIds`: 貼上 Stack 01 Outputs 中的三個 Private App Subnets (同 Stack 04，以逗號分隔)。
     - `ClusterName`: 保留預設 `eks-aiops-mumbai`。
     - 其他設定如 `InstanceTypes` (`t3.medium`)、數量保留預設。
  5. 點選 **Next**，最後確認頁同樣勾選 **"I acknowledge that AWS CloudFormation might create IAM resources..."**（此 Stack 內含 BastionHost 角色）。
  6. 點選 **Submit**，等待 `CREATE_COMPLETE`。

---

### 6️⃣ Stack 06: 資料與儲存層 (Data Stack)
* **範本檔案路徑**：`CloudFromation/nkc201-17-06-data-stack.yaml`
* **主控台操作步驟**：
  1. 點選 **Create stack** ➔ **With new resources**。
  2. 上傳 [nkc201-17-06-data-stack.yaml](file:///c:/Users/USER/Desktop/專題資料/CloudFromation/nkc201-17-06-data-stack.yaml)。
  3. **Stack name** 輸入：`nkc201-17-06-data-stack`。
  4. **Parameters** 參數設定：
     - `PrivateDataSubnets`: 貼上 Stack 01 Outputs 中的三個 **Private Data Subnets**，以逗號分隔（分別對應 DataSubnetAId, BId, CId）。
     - `RdsSecurityGroupId`: 貼上 Stack 02 Outputs 中的 `RdsSecurityGroupId`。
     - 其他資料庫帳號密碼可保留預設（或自訂）。
  5. 點選 **Next** ➔ **Submit**，等待 `CREATE_COMPLETE`。

---

### 7️⃣ Stack 07: EKS 權限對接控制 (Access Stack)
* **範本檔案路徑**：`CloudFromation/nkc201-17-07-access-stack.yaml`
* **主控台操作步驟**：
  1. 點選 **Create stack** ➔ **With new resources**。
  2. 上傳 [nkc201-17-07-access-stack.yaml](file:///c:/Users/USER/Desktop/專題資料/CloudFromation/nkc201-17-07-access-stack.yaml)。
  3. **Stack name** 輸入：`nkc201-17-07-access-stack`。
  4. **Parameters** 參數設定：
     - `EngineerRoleArn`: 貼上 Stack 03 Outputs 中的 `EngineerRoleArn`。
     - `CodeBuildRoleArn`: 貼上 Stack 03 Outputs 中的 `CodeBuildRoleArn`。
     - `ClusterName`: 保留預設 `eks-aiops-mumbai`。
  5. 點選 **Next** ➔ **Submit**，等待 `CREATE_COMPLETE`。

---

### 8️⃣ Stack 08: AIOps 智能維護與告警 (AIOps Stack)
* **範本檔案路徑**：`CloudFromation/nkc201-17-08-aiops-stack.yaml`
* **主控台操作步驟**：
  1. 點選 **Create stack** ➔ **With new resources**。
  2. 上傳 [nkc201-17-08-aiops-stack.yaml](file:///c:/Users/USER/Desktop/專題資料/CloudFromation/nkc201-17-08-aiops-stack.yaml)。
  3. **Stack name** 輸入：`nkc201-17-08-aiops-stack`。
  4. **Parameters** 參數設定：
     - `VpcId`: 貼上 Stack 01 Outputs 中的 `VpcId`。
     - `PrivateSubnetIds`: 貼上 Stack 01 Outputs 中的三個 **Private App Subnets**，以逗號分隔（即 AId, BId, CId）。
     - `EngineerEmail`: 輸入您的電子郵件信箱，例如：`james810526@gmail.com`（用於接收 SNS 告警）。
  5. 點選 **Next**，最後確認頁勾選 **"I acknowledge that AWS CloudFormation might create IAM resources..."**（此 Stack 內含 Lambda 執行角色）。
  6. 點選 **Submit**，等待 `CREATE_COMPLETE`。
  7. ⚠️ **部署完成後的重要動作**：
     - 檢查您的工程師信箱，會收到一封 AWS SNS 的訂閱確認信，請點選 **"Confirm subscription"** 連結啟用告警。
     - 在 Stack 08 的 Outputs 中複製 `ApiEndpoint`，此即為 API Gateway 的路由網址（包含 `/webhook`、`/approve`、`/reject`）。
