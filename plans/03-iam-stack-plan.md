# 03 IAM Stack - 權限角色架構計畫

本計畫紀錄了 EKS 智能維運專題中所有 IAM 角色（Role）與權限策略（Policy）的架構設計，並使用費曼學習法（比喻法）進行詳細說明，方便導入 Obsidian 閱讀與複習。

## 💡 費曼學習法：IAM 與 7 張識別證

AWS 的 **IAM（身分與存取管理）** 就像是這家自動化大工廠的 **「人事行政部 (HR)」**。
為了讓機器（伺服器）與軟體程式（K8s 裡的 Pod 等）能夠合規工作且不越權，HR 幫我們印製了 **7 張專屬角色識別證**：

### 1. 👑 EKS Cluster Role (總經理特助的識別證)
- **誰戴它：** EKS 控制面大腦（Control Plane）。
- **用途：** 授予大腦權限去協調 VPC 內的網路、硬體與基本資源。

### 2. 👷 EKS Node Role (現場班長的識別證)
- **誰戴它：** Worker Nodes 工作伺服器（EC2 實例）。
- **用途：** 讓伺服器能向叢集註冊為可用員工、去中央倉庫（ECR）搬運容器映像檔，並允許 SSM 通道以便維運人員免密碼登入查修。

### 3. 🚦 ALB Controller Role (交通警察的識別證)
- **誰戴它：** AWS Load Balancer Controller 控制元件的 Pod。
- **用途：** 允許它動態監聽 Ingress，並在門口「蓋紅綠燈、架設天線」（建立 AWS ALB、Listeners、Security Group 規則）。

### 4. 📦 App S3 Role (倉庫搬運工的識別證)
- **誰戴它：** 運行網頁服務的 Pod。
- **用途：** 允許網頁伺服器讀寫/存取中央大倉庫（S3 Buckets），例如放置上傳的商品圖片與備份。

### 5. 🩺 K8sGPT / AI Role (AI 智能醫生的識別證)
- **誰戴它：** 智能診斷分析 Pod。
- **用途：** 
  - 允許將 K8s 異常日誌送給 **AWS Bedrock 智囊團 (LLM)** 診斷。
  - 允許將診斷病歷存入 **S3 報告區**。
  - 允許使用 **SNS 發信系統**發布 Email 通知，或讀取 Secrets Manager 的 LINE API 憑證。

### 6. 🧑‍💻 Engineer Role (外部資深顧問的識別證)
- **誰戴它：** 人類工程師（您自己）。
- **用途：** 讓您能在控制台切換身分，對 EKS 叢集進行最高管理限度操作（如 kubectl 執行、描述節點等）。

### 7. 🤖 CodeBuild Role (自動維修工人的識別證)
- **誰戴它：** AWS CodeBuild。
- **用途：** 取得授權，在收到工程師的修復同意（Approve）後，自動執行 kubectl 指令去修改或升級部署。

---

## 💡 關鍵架構優化：EKS Pod Identity 

- **傳統作法 (IRSA)：** 
  - 必須將 IAM 角色與 EKS 的 OIDC 身份提供者（這需要叢集建立後才有其網址）進行綁定。
  - **缺點：** 造成「先有 EKS，還是先有 IAM 角色」的循環依賴。我們將無法在 Stack 03 提前部署 IAM。
- **新式作法 (EKS Pod Identity)：** 
  - 我們直接將角色的「信任關係 (Trust Relationship)」設定為 **`pods.eks.amazonaws.com`**。
  - **優點：** 
    - 識別證可以直接在 Stack 03 提前蓋好。
    - 當 EKS 叢集蓋好後，K8s 的 Pod 就可以直接使用 Pod Identity Association 來快速借用這張識別證，無需處理複雜的 OIDC 對接，非常優雅！

---

## 🛠️ 完整的 CloudFormation 藍圖

已寫入：`CloudFromation/nkc201-17-03-iam-stack.yaml`

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: IAM Roles Stack for EKS Cluster, Nodes, ALB Controller, S3, K8sGPT, Engineers, and CodeBuild.

Parameters:
  ProjectName:
    Type: String
    Default: eks-aiops-demo
    Description: Project name used for resource naming

Resources:
  # 1. EKS Cluster Role
  EksClusterRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ProjectName}-eks-cluster-role"
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: eks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-eks-cluster-role"
        - Key: Project
          Value: nkc201-17

  # 2. EKS Node Role
  EksNodeRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ProjectName}-eks-node-role"
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-eks-node-role"
        - Key: Project
          Value: nkc201-17

  EksNodeInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      InstanceProfileName: !Sub "${ProjectName}-eks-node-instance-profile"
      Roles:
        - !Ref EksNodeRole

  # 3. ALB Controller Role
  AlbControllerRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ProjectName}-alb-controller-role"
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: pods.eks.amazonaws.com
            Action: 
              - sts:AssumeRole
              - sts:TagSession
      Policies:
        - PolicyName: EKSALBControllerPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - iam:CreateServiceLinkedRole
                Resource: '*'
                Condition:
                  StringEquals:
                    iam:AWSServiceName: elasticloadbalancing.amazonaws.com
              - Effect: Allow
                Action:
                  - ec2:DescribeAccountAttributes
                  - ec2:DescribeAddresses
                  - ec2:DescribeAvailabilityZones
                  - ec2:DescribeInternetGateways
                  - ec2:DescribeVpcs
                  - ec2:DescribeSubnets
                  - ec2:DescribeSecurityGroups
                  - ec2:DescribeInstances
                  - ec2:DescribeNetworkInterfaces
                  - ec2:DescribeTags
                  - ec2:GetCoipPoolUsage
                  - ec2:DescribeCoipPools
                  - elasticloadbalancing:DescribeLoadBalancers
                  - elasticloadbalancing:DescribeLoadBalancerAttributes
                  - elasticloadbalancing:DescribeListeners
                  - elasticloadbalancing:DescribeListenerAttributes
                  - elasticloadbalancing:DescribeRules
                  - elasticloadbalancing:DescribeTargetGroups
                  - elasticloadbalancing:DescribeTargetGroupAttributes
                  - elasticloadbalancing:DescribeTargetHealth
                  - elasticloadbalancing:DescribeTags
                  - cognito-idp:DescribeUserPoolClient
                  - acm:ListCertificates
                  - acm:DescribeCertificate
                  - iam:ListServerCertificates
                  - iam:GetServerCertificate
                  - waf-regional:GetWebACL
                  - waf-regional:GetWebACLForResource
                  - waf-regional:AssociateWebACL
                  - waf-regional:DisassociateWebACL
                  - wafv2:GetWebACL
                  - wafv2:GetWebACLForResource
                  - wafv2:AssociateWebACL
                  - wafv2:DisassociateWebACL
                  - shield:GetSubscriptionState
                  - shield:DescribeProtection
                  - shield:CreateProtection
                  - shield:DeleteProtection
                Resource: '*'
              - Effect: Allow
                Action:
                  - ec2:AuthorizeSecurityGroupIngress
                  - ec2:RevokeSecurityGroupIngress
                  - ec2:CreateSecurityGroup
                  - ec2:DeleteSecurityGroup
                Resource: '*'
              - Effect: Allow
                Action:
                  - elasticloadbalancing:CreateLoadBalancer
                  - elasticloadbalancing:CreateTargetGroup
                  - elasticloadbalancing:CreateListener
                  - elasticloadbalancing:DeleteLoadBalancer
                  - elasticloadbalancing:DeleteTargetGroup
                  - elasticloadbalancing:DeleteListener
                  - elasticloadbalancing:ModifyLoadBalancerAttributes
                  - elasticloadbalancing:ModifyTargetGroup
                  - elasticloadbalancing:ModifyTargetGroupAttributes
                  - elasticloadbalancing:SetIpAddressType
                  - elasticloadbalancing:SetSecurityGroups
                  - elasticloadbalancing:SetSubnets
                  - elasticloadbalancing:RegisterTargets
                  - elasticloadbalancing:DeregisterTargets
                  - elasticloadbalancing:CreateRule
                  - elasticloadbalancing:DeleteRule
                  - elasticloadbalancing:ModifyListener
                  - elasticloadbalancing:ModifyRule
                Resource: '*'
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-alb-controller-role"
        - Key: Project
          Value: nkc201-17

  # 4. App S3 Role
  AppS3Role:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ProjectName}-app-s3-role"
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: pods.eks.amazonaws.com
            Action: 
              - sts:AssumeRole
              - sts:TagSession
      Policies:
        - PolicyName: PodS3AccessPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - s3:ListBucket
                  - s3:GetBucketLocation
                Resource: 'arn:aws:s3:::*'
              - Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:PutObject
                  - s3:DeleteObject
                Resource: 'arn:aws:s3:::*/*'
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-app-s3-role"
        - Key: Project
          Value: nkc201-17

  # 5. K8sGPT AI Role
  K8sGptRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ProjectName}-k8sgpt-ai-role"
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: pods.eks.amazonaws.com
            Action: 
              - sts:AssumeRole
              - sts:TagSession
      Policies:
        - PolicyName: K8sGptAIAccessPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - bedrock:InvokeModel
                  - bedrock:InvokeModelWithResponseStream
                Resource: 'arn:aws:bedrock:*::foundation-model/*'
              - Effect: Allow
                Action:
                  - sns:Publish
                Resource: 'arn:aws:sns:*:*:*'
              - Effect: Allow
                Action:
                  - s3:ListBucket
                  - s3:GetObject
                  - s3:PutObject
                Resource: 'arn:aws:s3:::*'
              - Effect: Allow
                Action:
                  - secretsmanager:GetSecretValue
                Resource: 'arn:aws:secretsmanager:*:*:secret:*'
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-k8sgpt-ai-role"
        - Key: Project
          Value: nkc201-17

  # 6. Engineer Role
  EngineerRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ProjectName}-engineer-role"
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: !Sub "arn:aws:iam::${AWS::AccountId}:root"
            Action: sts:AssumeRole
      Policies:
        - PolicyName: EKSReadWriteAccess
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - eks:DescribeCluster
                  - eks:ListClusters
                  - eks:ListNodegroups
                  - eks:DescribeNodegroup
                  - eks:ListUpdates
                  - eks:DescribeUpdate
                  - eks:AccessKubernetesApi
                Resource: '*'
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-engineer-role"
        - Key: Project
          Value: nkc201-17

  # 7. CodeBuild Role
  CodeBuildRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ProjectName}-codebuild-role"
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codebuild.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: CodeBuildBasePolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - logs:CreateLogGroup
                  - logs:CreateLogStream
                  - logs:PutLogEvents
                Resource: 'arn:aws:logs:*:*:*'
              - Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:GetObjectVersion
                  - s3:PutObject
                Resource: 'arn:aws:s3:::*'
              - Effect: Allow
                Action:
                  - eks:DescribeCluster
                Resource: '*'
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-codebuild-role"
        - Key: Project
          Value: nkc201-17

# Outputs
Outputs:
  EksClusterRoleArn:
    Description: ARN for EKS Cluster Role
    Value: !GetAtt EksClusterRole.Arn

  EksNodeRoleArn:
    Description: ARN for EKS Node Role
    Value: !GetAtt EksNodeRole.Arn

  EksNodeInstanceProfileName:
    Description: Name for EKS Node Instance Profile
    Value: !Ref EksNodeInstanceProfile

  AlbControllerRoleArn:
    Description: ARN for ALB Controller Role
    Value: !GetAtt AlbControllerRole.Arn

  AppS3RoleArn:
    Description: ARN for App S3 Role
    Value: !GetAtt AppS3Role.Arn

  K8sGptRoleArn:
    Description: ARN for K8sGPT AI Role
    Value: !GetAtt K8sGptRole.Arn

  EngineerRoleArn:
    Description: ARN for Engineer Role
    Value: !GetAtt EngineerRole.Arn

  CodeBuildRoleArn:
    Description: ARN for CodeBuild Role
    Value: !GetAtt CodeBuildRole.Arn
```

---

## 💻 部署指令參考

在 Windows 中，您可以使用 AWS CLI 來部署此 IAM Stack：

```powershell
aws cloudformation create-stack `
  --stack-name eks-aiops-iam `
  --template-body file://CloudFromation/nkc201-17-03-iam-stack.yaml `
  --capabilities CAPABILITY_NAMED_IAM
```
* **注意：** 由於此範本會建立自訂名稱的 IAM 角色，您必須加入 `--capabilities CAPABILITY_NAMED_IAM` 參數授權 AWS 建立這類特殊權限資源，否則會發生 `RequiresCapabilities` 報錯。
