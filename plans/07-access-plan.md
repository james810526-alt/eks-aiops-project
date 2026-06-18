# 07 Access Stack - 叢集存取控制建置計畫

本計畫紀錄了 EKS 智能維運專題中「EKS 叢集存取控制（Cluster Access Control）」的建置規劃與權限綁定設計。我們採用 AWS 最新推薦的 **EKS Access Entry API** 機制，取代傳統且危險的 `aws-auth` ConfigMap 機制，以安全地將 IAM 角色與 Kubernetes 內部的權限進行對接。

---

## 💡 費曼學習法：辦公大樓、識別證與電子門禁系統

當我們想要讓 AWS 的 IAM 角色（例如工程師或自動化程式）進入 Kubernetes 叢集操作時，兩者就像是兩個獨立的王國：
- **AWS 國王**（IAM）認得您的 IAM 角色。
- **Kubernetes 國王**（K8s RBAC）只認得 K8s 內部的 User 與 Group。

要如何讓兩者安全通訊？

### 傳統做法：`aws-auth` ConfigMap (門口紙本登記簿)
- 過去，EKS 依靠一個寫在 Kubernetes 內部的設定檔（ConfigMap）叫 `aws-auth`。
- 這就像大樓門口放了一本**紙本登記簿**。每當有新的 IAM 員工來，大樓管理員就要手動把名字寫進登記簿。
- **問題：** 
  1. 如果大樓管理員不小心寫錯一個字（YAML 縮排錯誤），整本登記簿就會損毀，導致**所有人（包含管理員自己）都被鎖在大門外**。
  2. AWS CloudFormation 或 Terraform 很難安全地修改這本紙本登記簿，容易發生衝突。

### 現代做法：EKS Access Entry API (電子晶片卡感應門禁)
- EKS 引入了 Access Entry API。現在，大樓門口裝了最新的**電子晶片卡感應器**。
- 這套系統直接連線到 AWS IAM 伺服器。我們可以直接在 AWS 控制台（或透過 CloudFormation 藍圖）替不同的人設定門禁權限，完全不需要去改 Kubernetes 內部的紙本登記簿。
- **好處：** 安全性極高，部署極其穩定，寫錯語法也只會導致該筆設定失敗，絕不會把其他人鎖在外面。

---

## 🔑 門禁權限角色規劃 (Who gets What?)

在本專題中，我們有兩位主要使用者，分別核發不同權限的「晶片卡」：

### 1. 👷 維運工程師 (`EngineerRole`)
* **晶片卡權限：** **特定房間通行證 + 大廳通行證**
* **K8s 內部權限對應：**
  * **在 `web-prod` 與 `aiops` 命名空間 (Namespace) 中：** 擁有 `AmazonEKSAdminPolicy`（系統管理員權限）。可以自由地建立、刪除、修改這兩個命名空間內的所有 Pod、Deployment 與 Service。這就像是工程師在自己的專案辦公室裡擁有最高使用權。
  * **在整個叢集級別 (Cluster-wide)：** 擁有 `AmazonEKSViewerPolicy`（唯讀權限）。不能隨意修改大樓結構，但可以走到大廳看一看（查看 Node 狀態、Storage 資訊等），便於排查整體環境問題，同時避免不小心刪除系統核心組件（如 `kube-system` 命名空間下的網路外掛）。

### 2. 🤖 自動化修復機器人 (`CodeBuildRole`)
* **晶片卡權限：** **特定房間通行證**
* **K8s 內部權限對應：**
  * **在 `web-prod` 與 `aiops` 命名空間中：** 擁有 `AmazonEKSAdminPolicy`。此設計將自動修復範圍限縮於專題應用與 AIOps 命名空間，避免 CodeBuild 誤改 `kube-system` 等核心命名空間。

---

## 🛠️ 完整的 CloudFormation 藍圖

已寫入：`CloudFromation/nkc201-17-07-access-stack.yaml`

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: EKS Cluster Access Entry Stack to map IAM Roles to Kubernetes Policies

Parameters:
  ProjectName:
    Type: String
    Default: eks-aiops-demo
    Description: Project name used for resource naming

  ClusterStackName:
    Type: String
    Default: nkc201-17-04-eks-cluster-stack
    Description: The name of the EKS Cluster CloudFormation Stack to import ClusterName

  IamStackName:
    Type: String
    Default: nkc201-17-03-iam-stack
    Description: The name of the IAM CloudFormation Stack to import Role ARNs

Resources:
  # =========================================================================
  # 1. 授權工程師權限 (限縮在特定命名空間 web-prod 與 aiops)
  # =========================================================================
  EngineerAccessEntry:
    Type: AWS::EKS::AccessEntry
    Properties:
      ClusterName:
        Fn::ImportValue: !Sub "${ClusterStackName}-ClusterName"
      PrincipalArn:
        Fn::ImportValue: !Sub "${IamStackName}-EngineerRoleArn"
      Type: STANDARD
      # 綁定 Kubernetes 權限策略
      AccessPolicies:
        # 1.1 在 web-prod 和 aiops 命名空間下擁有管理員 (Admin) 權限
        - PolicyArn: arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy
          AccessScope:
            Type: namespace
            Namespaces:
              - web-prod
              - aiops
        # 1.2 在整個叢集級別擁有唯讀 (Viewer) 權限，便於查看 Node 狀態
        - PolicyArn: arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewerPolicy
          AccessScope:
            Type: cluster
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-engineer-access"
        - Key: Project
          Value: nkc201-17

  # =========================================================================
  # 2. 授權 CI/CD 自動化修復權限 (EKS 叢集全域管理員)
  # =========================================================================
  CodeBuildAccessEntry:
    Type: AWS::EKS::AccessEntry
    Properties:
      ClusterName:
        Fn::ImportValue: !Sub "${ClusterStackName}-ClusterName"
      PrincipalArn:
        Fn::ImportValue: !Sub "${IamStackName}-CodeBuildRoleArn"
      Type: STANDARD
      AccessPolicies:
        # 2.1 限制在 web-prod 與 aiops 命名空間下擁有管理員 (Admin) 權限，避免對系統核心空間造成衝擊
        - PolicyArn: arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy
          AccessScope:
            Type: namespace
            Namespaces:
              - web-prod
              - aiops
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-codebuild-access"
        - Key: Project
          Value: nkc201-17

# =========================================================================
# Outputs
# =========================================================================
Outputs:
  EngineerAccessEntryArn:
    Description: ARN of the Engineer Access Entry
    Value: !GetAtt EngineerAccessEntry.AccessEntryArn
    Export:
      Name: !Sub "${AWS::StackName}-EngineerAccessEntryArn"

  CodeBuildAccessEntryArn:
    Description: ARN of the CodeBuild Access Entry
    Value: !GetAtt CodeBuildAccessEntry.AccessEntryArn
    Export:
      Name: !Sub "${AWS::StackName}-CodeBuildAccessEntryArn"
```

---

## 💻 部署指令參考

請在 **WSL (Bash)** 中執行以下指令：

```bash
# 1. 鎖定登入 Profile
export AWS_PROFILE="nkc201-17-sso"

# 2. 執行部署指令
aws cloudformation create-stack \
  --stack-name nkc201-17-07-access-stack \
  --template-body file://CloudFromation/nkc201-17-07-access-stack.yaml \
  --parameters \
    ParameterKey=ClusterStackName,ParameterValue=nkc201-17-04-eks-cluster-stack \
    ParameterKey=IamStackName,ParameterValue=nkc201-17-03-iam-stack
```

> [!TIP]
> **Windows PowerShell 備用指令**
> ```powershell
> # 1. 鎖定登入 Profile
> $env:AWS_PROFILE="nkc201-17-sso"
> 
> # 2. 執行部署指令
> aws cloudformation create-stack `
>   --stack-name nkc201-17-07-access-stack `
>   --template-body (Get-Content CloudFromation/nkc201-17-07-access-stack.yaml -Raw -Encoding UTF8) `
>   --parameters `
>     ParameterKey=ClusterStackName,ParameterValue=nkc201-17-04-eks-cluster-stack `
>     ParameterKey=IamStackName,ParameterValue=nkc201-17-03-iam-stack `
>   --profile nkc201-17-sso
> ```

---

## 🔍 如何驗證存取控制是否成功？

部署完成後，您可以透過 AWS CLI 查詢 EKS 叢集目前登錄的晶片卡名單（Access Entries）來進行驗證：

### 1. 查詢叢集上已註冊的 Access Entries 列表：
```bash
aws eks list-access-entries --cluster-name eks-aiops-mumbai --profile nkc201-17-sso
```

### 2. 詳細檢視 `EngineerRole` 綁定的 Kubernetes 策略：
```bash
# 請將 <EngineerRoleArn> 替換為實際的 EngineerRole ARN (例如 arn:aws:iam::xxxxxxxxxxxx:role/eks-aiops-demo-engineer-role)
aws eks list-associated-access-policies \
  --cluster-name eks-aiops-mumbai \
  --principal-arn <EngineerRoleArn> \
  --profile nkc201-17-sso
```

> [!TIP]
> **Windows PowerShell 備用指令**
> ```powershell
> # 1. 查詢列表
> aws eks list-access-entries --cluster-name eks-aiops-mumbai --profile nkc201-17-sso
> 
> # 2. 詳細檢視策略 (以反引號換行)
> aws eks list-associated-access-policies `
>   --cluster-name eks-aiops-mumbai `
>   --principal-arn <EngineerRoleArn> `
>   --profile nkc201-17-sso
> ```

* **預期結果：** 會列出 `AmazonEKSAdminPolicy` (限 namespace `web-prod`, `aiops`) 以及 `AmazonEKSViewerPolicy` (全叢集)。
