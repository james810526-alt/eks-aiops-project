# 02 Security Stack - 安全群組架構計畫

本計畫紀錄了 EKS 專題中的安全群組 (Security Group) 架構設計，並使用費曼學習法（比喻法）進行詳細說明，便於初學者理解與複習。

## 💡 費曼學習法：安全群組是什麼？

安全群組（Security Group）就像是辦公大樓中**各個辦公室門口的「保安人員（防火牆）」**。他們會檢查訪客的身份，決定是否放行（Inbound 規則）與是否准許出境（Outbound 規則）。

本專題建立了四個主要的安全房間，各有保安把守：

### 1. 🏢 ALB 安全群組 (大門口保安)
- **比喻：** 公司的對外大門與接待大廳。
- **規則：** 任何人（`0.0.0.0/0`）都可以來，但只允許通過 **Port 80 (HTTP)** 和 **Port 443 (HTTPS)**。其他門口一律不通。

### 2. 💻 EKS Node 安全群組 (員工辦公區保安)
- **比喻：** 實際放置伺服器和容器的工作區域。
- **規則：**
  1. 訪客必須先通過大廳保安 (ALB SG) 的過濾引導。
  2. 允許經理室的保安 (EKS Cluster SG) 進來發布指令 (Port 443 與隨機埠口)。
  3. 辦公區內的同仁可以直接交談不用每次申報（這在 CloudFormation 中稱為 **Self-reference 自我關聯**）。

### 3. 🧠 EKS Cluster 安全群組 (經理辦公室保安)
- **比喻：** Kubernetes 的管理大腦 (Control Plane)。
- **規則：** 只允許在辦公區工作的員工 (EKS Node) 進來報告進度 (Port 443)。

### 4. 🗄️ RDS 安全群組 (保險金庫保安)
- **比喻：** 存放客戶與訂單機密資料的資料庫。
- **規則：** **全棟最嚴格。** 只允許識別證是「EKS Node 員工」的人進入，且只能透過 **Port 3306 (MySQL)** 存取，其他人一律拒之門外。

---

## 🔄 循環相依問題與解決方案

- **問題：** 經理室保安（EKS Cluster）需要知道員工辦公區的 ID 才能放行，而員工辦公區（EKS Node）也需要經理室的 ID。如果在建立安全群組時直接把對方的規則寫進去，AWS 會不知道要先建立哪一個，導致部署失敗。
- **解決方案：** 先建立空房間（空的 Security Group），待兩者都蓋好取得房號（ID）後，再使用 `AWS::EC2::SecurityGroupIngress` 資源像「便利貼」一樣動態貼到門口，建立連線規則。

---

## 🛠️ 完整的 CloudFormation 藍圖

已寫入：`CloudFromation/nkc201-17-02-security-stack.yaml`

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Security Groups Stack for EKS Cluster, ALB, Node Group and RDS Database

Parameters:
  ProjectName:
    Type: String
    Default: eks-aiops-demo
    Description: Project name used for resource naming

  VpcId:
    Type: AWS::EC2::VPC::Id
    Description: VPC ID where security groups will be created

  DatabasePort:
    Type: Number
    Default: 3306
    AllowedValues: [3306, 5432]
    Description: Port of the database (3306 for MySQL, 5432 for PostgreSQL)

Resources:
  # 1. ALB Security Group
  AlbSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security Group for Application Load Balancer (ALB)
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0
          Description: Allow HTTP from internet
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 0.0.0.0/0
          Description: Allow HTTPS from internet
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-alb-sg"
        - Key: Project
          Value: nkc201-17

  # 2. EKS Cluster Security Group
  EksClusterSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security Group for EKS Cluster Control Plane
      VpcId: !Ref VpcId
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-eks-cluster-sg"
        - Key: Project
          Value: nkc201-17

  # 3. EKS Node Security Group
  EksNodeSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security Group for EKS Worker Nodes
      VpcId: !Ref VpcId
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-eks-node-sg"
        - Key: Project
          Value: nkc201-17

  # Self-reference Ingress for Node-to-Node communication
  EksNodeSelfIngress:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref EksNodeSecurityGroup
      SourceSecurityGroupId: !Ref EksNodeSecurityGroup
      IpProtocol: -1
      Description: Allow node-to-node and pod-to-pod communication

  # 4. RDS Security Group
  RdsSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security Group for RDS Database Instance
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: !Ref DatabasePort
          ToPort: !Ref DatabasePort
          SourceSecurityGroupId: !Ref EksNodeSecurityGroup
          Description: Allow database access only from EKS nodes
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-rds-sg"
        - Key: Project
          Value: nkc201-17

  # 5. Ingress Rules (Cross-References)
  AlbToNodeIngress80:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref EksNodeSecurityGroup
      SourceSecurityGroupId: !Ref AlbSecurityGroup
      IpProtocol: tcp
      FromPort: 80
      ToPort: 80
      Description: Allow ALB to talk to nodes on HTTP

  AlbToNodeIngress443:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref EksNodeSecurityGroup
      SourceSecurityGroupId: !Ref AlbSecurityGroup
      IpProtocol: tcp
      FromPort: 443
      ToPort: 443
      Description: Allow ALB to talk to nodes on HTTPS

  ClusterToNodeIngress443:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref EksNodeSecurityGroup
      SourceSecurityGroupId: !Ref EksClusterSecurityGroup
      IpProtocol: tcp
      FromPort: 443
      ToPort: 443
      Description: Allow EKS control plane to communicate with nodes on 443

  ClusterToNodeIngressEphemeral:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref EksNodeSecurityGroup
      SourceSecurityGroupId: !Ref EksClusterSecurityGroup
      IpProtocol: tcp
      FromPort: 1025
      ToPort: 65535
      Description: Allow EKS control plane to communicate with pods on ephemeral ports

  NodeToClusterIngress443:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref EksClusterSecurityGroup
      SourceSecurityGroupId: !Ref EksNodeSecurityGroup
      IpProtocol: tcp
      FromPort: 443
      ToPort: 443
      Description: Allow nodes to talk to EKS API server

# Outputs
Outputs:
  AlbSecurityGroupId:
    Description: Security Group ID for ALB
    Value: !Ref AlbSecurityGroup
    Export:
      Name: !Sub "${AWS::StackName}-AlbSecurityGroupId"

  EksClusterSecurityGroupId:
    Description: Security Group ID for EKS Cluster Control Plane
    Value: !Ref EksClusterSecurityGroup
    Export:
      Name: !Sub "${AWS::StackName}-EksClusterSecurityGroupId"

  EksNodeSecurityGroupId:
    Description: Security Group ID for EKS Worker Nodes
    Value: !Ref EksNodeSecurityGroup
    Export:
      Name: !Sub "${AWS::StackName}-EksNodeSecurityGroupId"

  RdsSecurityGroupId:
    Description: Security Group ID for RDS Database
    Value: !Ref RdsSecurityGroup
    Export:
      Name: !Sub "${AWS::StackName}-RdsSecurityGroupId"
```

---

## 💻 部署指令參考

在 Windows 中，您可以使用 AWS CLI 來建立本 Security Stack。

### 1. 查詢已建立的 VPC ID
```powershell
aws ec2 describe-vpcs --query "Vpcs[*].{ID:VpcId,Name:Tags[?Key=='Name'].Value | [0]}" --output table
```

### 2. 執行建立 Stack 指令
將查到的 VPC ID（例如 `vpc-xxxxxx`）填入下方：
```powershell
aws cloudformation create-stack `
  --stack-name eks-aiops-security `
  --template-body file://CloudFromation/nkc201-17-02-security-stack.yaml `
  --parameters ParameterKey=VpcId,ParameterValue=vpc-xxxxxx
```
