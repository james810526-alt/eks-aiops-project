# 05 Node Group Stack - 工作節點建置計畫

本計畫紀錄了 EKS 智能維運專題中工作節點（Worker Nodes）的建置規劃與成本優化考量，方便導入 Obsidian 閱讀與複習。

## 💡 費曼學習法：辦公大樓裡的「辦公桌與隔間」

### 1. 👷 EKS Node Group (辦公大樓)
- **比喻：** 它是這間自動化大工廠中的 **「實體辦公大樓（EC2 主機）」**。
- **用途：** 實際提供運算資源（CPU、記憶體、硬碟）來安裝我們的網頁與智能維運軟體（Pods/Containers）。

### 2. ⚠️ 為什麼不能用 `t3.micro`？ (關鍵限制)
- **大樓公設佔比太高：** `t3.micro` 只有 1GB 記憶體，但 K8s 內建的管理基礎設施（如 CNI 網路、proxy 轉發）開機就會吃掉約 0.7GB ~ 0.8GB 的空間，只剩下不到 200MB 的空間給我們的網頁，會直接造成系統記憶體不足而崩潰 (OOMKilled)。
- **網卡 IP 分配上限：** `t3.micro` 的硬體限制了它最多只能運行 4 個 Pods（扣掉內建的，只能再放 2 個 Pod）。而 `t3.medium` 可以運行 17 個 Pods。
- **結論：** **`t3.medium` 是 EKS 正常運作的最低硬體門檻。**

### 3. 🔌 CoreDNS 部署優化 (延遲至節點準備就緒)
- **排程依賴**：CoreDNS 以 Deployment 形式運行（預設 2 副本），必須有實體節點才能進行排程。
- **避免逾時**：若在 Stack 04 (只有控制面，無節點) 建立 CoreDNS Addon，Addon 將因無法排程而長期待在 `DEGRADED` 狀態，導致 CloudFormation 出現 20 分鐘的建立逾時與失敗。
- **解決方案**：將 CoreDNS Addon 移動至本 Stack，並宣告 `DependsOn: EksNodeGroup`。當工作節點順利啟動並加入叢集後，才安裝 CoreDNS，使其能瞬間完成排程，快速變成 `ACTIVE`。

### 4. 💰 專題省錢優化設計
為了解決學術專題的預算考量，我們在模板中進行了以下優化：
- **硬碟調降：** 從預設的 30GB 降低至 **20GB**，省下 EBS 儲存空間月租費。
- **數量調降：** 初始與最少數量從 3 台調降至 **2 台**（能跨 2 個 AZ 通訊，省下 1/3 的 EC2 費用）。
- **最大自動擴展：** 設為 4 台，防止流量測試時開太多台導致帳單失控。

---

## 🛠️ 完整的 CloudFormation 藍圖

已寫入：`CloudFromation/nkc201-17-05-nodegroup-stack.yaml`

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: AWS EKS Managed Node Group Stack for cost-efficient student testing

Parameters:
  ProjectName:
    Type: String
    Default: eks-aiops-demo
    Description: Project name used for resource naming

  ClusterName:
    Type: String
    Default: eks-aiops-mumbai
    Description: Name of the existing EKS Cluster

  NodeRoleArn:
    Type: String
    Description: IAM Role ARN for EKS Node Group (from Stack 03)

  SubnetIds:
    Type: List<AWS::EC2::Subnet::Id>
    Description: Select the 3 Private App Subnets where nodes will be launched (from Stack 01)

  InstanceTypes:
    Type: CommaDelimitedList
    Default: t3.medium
    Description: EC2 instance type for the EKS nodes (t3.medium is minimum required for system memory)

  DesiredSize:
    Type: Number
    Default: 2
    Description: Desired number of worker nodes (set to 2 for budget saving)

  MinSize:
    Type: Number
    Default: 2
    Description: Minimum number of worker nodes

  MaxSize:
    Type: Number
    Default: 4
    Description: Maximum number of worker nodes

  DiskSize:
    Type: Number
    Default: 20
    Description: Disk size in GB for node root volume (reduced to 20GB for cost-efficiency)

  IamStackName:
    Type: String
    Default: nkc201-17-03-iam-stack
    Description: Name of the IAM Stack to import Instance Profile

  SecurityStackName:
    Type: String
    Default: nkc201-17-02-security-stack
    Description: Name of the Security Stack to import Node Security Group

Resources:
  EksNodeGroup:
    Type: AWS::EKS::Nodegroup
    Properties:
      ClusterName: !Ref ClusterName
      NodegroupName: app-nodegroup
      NodeRole: !Ref NodeRoleArn
      Subnets: !Ref SubnetIds
      InstanceTypes: !Ref InstanceTypes
      ScalingConfig:
        DesiredSize: !Ref DesiredSize
        MinSize: !Ref MinSize
        MaxSize: !Ref MaxSize
      DiskSize: !Ref DiskSize
      AmiType: AL2023_x86_64_STANDARD # 使用 Amazon Linux 2023 (最新推薦的最佳實踐)
      Labels:
        role: worker
        project: nkc201-17
      Tags:
        Name: !Sub "${ProjectName}-node"
        Project: nkc201-17

  # =========================================================================
  # 2. CoreDNS Addon (負責 K8s 內部 DNS 解析，依賴工作節點存在以進行排程)
  # =========================================================================
  CoreDnsAddon:
    Type: AWS::EKS::Addon
    DependsOn: EksNodeGroup
    Properties:
      AddonName: coredns
      ClusterName: !Ref ClusterName
      ResolveConflicts: OVERWRITE

  # =========================================================================
  # 3. SSM Bastion Host IAM Role & Instance Profile (跳板機專用 IAM 角色與設定檔)
  # =========================================================================
  BastionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ProjectName}-bastion-role"
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      Policies:
        - PolicyName: AllowAssumeEngineerRole
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: sts:AssumeRole
                Resource:
                  Fn::ImportValue: !Sub "${IamStackName}-EngineerRoleArn"
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-bastion-role"
        - Key: Project
          Value: nkc201-17

  BastionInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      InstanceProfileName: !Sub "${ProjectName}-bastion-instance-profile"
      Roles:
        - !Ref BastionRole

  # =========================================================================
  # 4. SSM Bastion Host (安全跳板機：無公網 IP、無開放 SSH、採用 SSM 登入，負責私有管理 EKS)
  # =========================================================================
  BastionHost:
    Type: AWS::EC2::Instance
    Properties:
      InstanceType: t3.micro
      SubnetId: !Select [0, !Ref SubnetIds] # 部署於第一個 App 私有子網路中
      SecurityGroupIds:
        - Fn::ImportValue: !Sub "${SecurityStackName}-EksNodeSecurityGroupId" # 使用與 Node 相同的安全群組以直接連線 API Server
      IamInstanceProfile: !Ref BastionInstanceProfile
      ImageId: "{{resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64}}" # 使用最新 AL2023 系統
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-bastion"
        - Key: Project
          Value: nkc201-17

# =========================================================================
# Outputs
# =========================================================================
Outputs:
  NodegroupName:
    Description: The name of the EKS Node Group
    Value: !Ref EksNodeGroup
    Export:
      Name: !Sub "${AWS::StackName}-NodegroupName"

  NodegroupArn:
    Description: The ARN of the EKS Node Group
    Value: !GetAtt EksNodeGroup.Arn
    Export:
      Name: !Sub "${AWS::StackName}-NodegroupArn"

  BastionInstanceId:
    Description: The Instance ID of the SSM Bastion Host
    Value: !Ref BastionHost
    Export:
      Name: !Sub "${AWS::StackName}-BastionInstanceId"
```

---

## 💻 部署指令參考

請在 **WSL (Bash)** 中執行以下指令：

```bash
# 1. 先鎖定登入 Profile
export AWS_PROFILE="nkc201-17-sso"

# 2. 執行部署指令
aws cloudformation create-stack \
  --stack-name nkc201-17-nodegroup \
  --template-body file://CloudFromation/nkc201-17-05-nodegroup-stack.yaml \
  --parameters \
    ParameterKey=ClusterName,ParameterValue=eks-aiops-mumbai \
    ParameterKey=NodeRoleArn,ParameterValue=<您的EksNodeRoleArn> \
    ParameterKey=SubnetIds,ParameterValue=<您的3個PrivateAppSubnetID，以逗號分隔>
```

> [!TIP]
> **Windows PowerShell 備用指令**
> 若要在 Windows PowerShell 中執行，可使用以下格式：
> ```powershell
> # 1. 先鎖定登入 Profile
> $env:AWS_PROFILE="nkc201-17-sso"
> 
> # 2. 執行部署指令
> aws cloudformation create-stack `
>   --stack-name nkc201-17-nodegroup `
>   --template-body (Get-Content CloudFromation/nkc201-17-05-nodegroup-stack.yaml -Raw -Encoding UTF8) `
>   --parameters `
>     ParameterKey=ClusterName,ParameterValue=eks-aiops-mumbai `
>     ParameterKey=NodeRoleArn,ParameterValue=<您的EksNodeRoleArn> `
>     ParameterKey=SubnetIds,ParameterValue=<您的3個PrivateAppSubnetID，以逗號分隔>
> ```
