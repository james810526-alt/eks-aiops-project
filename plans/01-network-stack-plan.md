# 01 Network Stack - 網路架構計畫

本計畫紀錄了針對 `nkc201-17-01-network-stack.yaml` 的檢查、修正與優化歷程。

## 🔍 檢查發現的關鍵問題

### 1. 私有子網路自動指派公網 IP (安全性風險)
- **問題：** 私有 App 子網路與 Data 子網路的 `MapPublicIpOnLaunch` 設定為 `true`。
- **影響：** 會使 EKS 節點或 RDS 被配發公有 IP，容易遭到掃描攻擊。
- **修正：** 將 6 個私有子網路的 `MapPublicIpOnLaunch` 設為 `false`。

### 2. Kubernetes ELB 標籤設定錯誤
- **問題：** 私有子網路設定了 `kubernetes.io/role/elb: "1"` (公有標籤)。
- **影響：** AWS ALB Controller 會搞不清楚在哪裡建立 Ingress 負載平衡器。
- **修正：**
  - 私有 App 子網路改用內部負載平衡器標籤：`kubernetes.io/role/internal-elb: "1"`。
  - 私有 Data 子網路移除 ELB 相關標籤。

### 3. 缺少 EKS Cluster 識別標籤
- **問題：** 公有與私有 App 子網路均缺少 `kubernetes.io/cluster/eks-aiops-mumbai: shared`。
- **影響：** EKS 與 ALB Controller 無法自動識別子網路以建立網路資源。
- **修正：** 為公有與私有 App 子網路補上此標籤。

### 4. Multi-AZ NAT 路由邏輯失效
- **問題：** 所有的私有 App 子網路關聯到同一個路由表，只指向 `NatGatewayA`。在 `MultiAZ` 模式下，另外兩個 NAT GW 會形同虛設，且一旦 AZ-a 故障，全部私有節點都會斷網。
- **修正：** 拆分路由表為 `PrivateAppRouteTableA/B/C`。在 `MultiAZ` 模式下，利用 `!If` 函數分別指向自己 AZ 的 NAT 閘道器，確保高可用性。

---

## 🛠️ 調整後的完整 CloudFormation 藍圖

已寫入並更新至：`CloudFromation/nkc201-17-01-network-stack.yaml`

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: VPC Infrastructure for EKS practice in Mumbai region with proper subnets and conditional NAT Gateways

Parameters:
  ProjectName:
    Type: String
    Default: eks-aiops-demo
    Description: Project name used for resource naming

  VpcCidr:
    Type: String
    Default: 10.20.0.0/16
    Description: CIDR block for VPC

  NatGatewayMode:
    Type: String
    Default: Single
    AllowedValues:
      - None
      - Single
      - MultiAZ
    Description: Select NAT Gateway deployment mode

Conditions:
  CreateSingleNAT: !Equals [ !Ref NatGatewayMode, Single ]
  CreateMultiAzNAT: !Equals [ !Ref NatGatewayMode, MultiAZ ]
  CreateAnyNAT: !Not [ !Equals [ !Ref NatGatewayMode, None ] ]
  
Resources:
  # VPC
  ProjectVPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref VpcCidr
      EnableDnsSupport: true
      EnableDnsHostnames: true
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-vpc"
        - Key: Project
          Value: nkc201-17
 
  # Internet Gateway
  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-igw"
        - Key: Project
          Value: nkc201-17

  AttachInternetGateway:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref ProjectVPC
      InternetGatewayId: !Ref InternetGateway

  # =========================================================================
  # Subnets
  # =========================================================================

  # Availability Zone: ap-south-1a (Zone A)
  PublicSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref ProjectVPC
      CidrBlock: 10.20.0.0/24
      AvailabilityZone: ap-south-1a
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-public-subnet-a-1"
        - Key: kubernetes.io/role/elb
          Value: "1"
        - Key: kubernetes.io/cluster/eks-aiops-mumbai
          Value: shared
        - Key: Project
          Value: "nkc201-17"
            
  PrivateAppSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref ProjectVPC
      CidrBlock: 10.20.10.0/24
      AvailabilityZone: ap-south-1a
      MapPublicIpOnLaunch: false
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-private-app-subnet-a-4"
        - Key: kubernetes.io/role/internal-elb
          Value: "1"
        - Key: kubernetes.io/cluster/eks-aiops-mumbai
          Value: shared
        - Key: Project
          Value: "nkc201-17"            
            
  PrivateDataSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref ProjectVPC
      CidrBlock: 10.20.20.0/24
      AvailabilityZone: ap-south-1a
      MapPublicIpOnLaunch: false
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-private-data-subnet-a-7"
        - Key: Project
          Value: "nkc201-17"
            
  # Availability Zone: ap-south-1b (Zone B)
  PublicSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref ProjectVPC
      CidrBlock: 10.20.1.0/24
      AvailabilityZone: ap-south-1b
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-public-subnet-b-2"
        - Key: kubernetes.io/role/elb
          Value: "1"
        - Key: kubernetes.io/cluster/eks-aiops-mumbai
          Value: shared
        - Key: Project
          Value: "nkc201-17"
            
  PrivateAppSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref ProjectVPC
      CidrBlock: 10.20.11.0/24
      AvailabilityZone: ap-south-1b
      MapPublicIpOnLaunch: false
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-private-app-subnet-b-5"
        - Key: kubernetes.io/role/internal-elb
          Value: "1"
        - Key: kubernetes.io/cluster/eks-aiops-mumbai
          Value: shared
        - Key: Project
          Value: "nkc201-17"      
            
  PrivateDataSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref ProjectVPC
      CidrBlock: 10.20.21.0/24
      AvailabilityZone: ap-south-1b
      MapPublicIpOnLaunch: false
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-private-data-subnet-b-8"
        - Key: Project
          Value: "nkc201-17" 
            
  # Availability Zone: ap-south-1c (Zone C)
  PublicSubnetC:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref ProjectVPC
      CidrBlock: 10.20.2.0/24
      AvailabilityZone: ap-south-1c
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-public-subnet-c-3"
        - Key: kubernetes.io/role/elb
          Value: "1"
        - Key: kubernetes.io/cluster/eks-aiops-mumbai
          Value: shared
        - Key: Project
          Value: "nkc201-17"
            
  PrivateAppSubnetC:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref ProjectVPC
      CidrBlock: 10.20.12.0/24
      AvailabilityZone: ap-south-1c
      MapPublicIpOnLaunch: false
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-private-app-subnet-c-6"
        - Key: kubernetes.io/role/internal-elb
          Value: "1"
        - Key: kubernetes.io/cluster/eks-aiops-mumbai
          Value: shared
        - Key: Project
          Value: "nkc201-17"     
            
  PrivateDataSubnetC:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref ProjectVPC
      CidrBlock: 10.20.22.0/24
      AvailabilityZone: ap-south-1c
      MapPublicIpOnLaunch: false
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-private-data-subnet-c-9"
        - Key: Project
          Value: "nkc201-17"      

  # =========================================================================
  # NAT Gateways
  # =========================================================================
  NatGatewayEipA:
    Type: AWS::EC2::EIP
    Condition: CreateAnyNAT
    Properties:
      Domain: vpc
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-nat-eip-a"
        - Key: Project
          Value: "nkc201-17"

  NatGatewayA:
    Type: AWS::EC2::NatGateway
    Condition: CreateAnyNAT
    Properties:
      AllocationId: !GetAtt NatGatewayEipA.AllocationId
      SubnetId: !Ref PublicSubnetA
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-nat-a"
        - Key: Project
          Value: "nkc201-17"
          
  NatGatewayEipB:
    Type: AWS::EC2::EIP
    Condition: CreateMultiAzNAT
    Properties:
      Domain: vpc
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-nat-eip-b"
        - Key: Project
          Value: "nkc201-17"

  NatGatewayB:
    Type: AWS::EC2::NatGateway
    Condition: CreateMultiAzNAT
    Properties:
      AllocationId: !GetAtt NatGatewayEipB.AllocationId
      SubnetId: !Ref PublicSubnetB
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-nat-b"
        - Key: Project
          Value: "nkc201-17"
          
  NatGatewayEipC:
    Type: AWS::EC2::EIP
    Condition: CreateMultiAzNAT
    Properties:
      Domain: vpc
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-nat-eip-c"
        - Key: Project
          Value: "nkc201-17"

  NatGatewayC:
    Type: AWS::EC2::NatGateway
    Condition: CreateMultiAzNAT
    Properties:
      AllocationId: !GetAtt NatGatewayEipC.AllocationId
      SubnetId: !Ref PublicSubnetC
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-nat-c"
        - Key: Project
          Value: "nkc201-17"

  # =========================================================================
  # Route Tables
  # =========================================================================

  # Public Route Table
  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref ProjectVPC
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-public-rt"
        - Key: Project
          Value: "nkc201-17"

  PublicInternetRoute:
    Type: AWS::EC2::Route
    DependsOn: AttachInternetGateway
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  # Private Route Tables for App Subnets (Split to support Multi-AZ NAT Routing)
  PrivateAppRouteTableA:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref ProjectVPC
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-private-app-rt-a"
        - Key: Project
          Value: "nkc201-17"

  PrivateRouteA:
    Type: AWS::EC2::Route
    Condition: CreateAnyNAT
    Properties:
      RouteTableId: !Ref PrivateAppRouteTableA
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !Ref NatGatewayA

  PrivateAppRouteTableB:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref ProjectVPC
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-private-app-rt-b"
        - Key: Project
          Value: "nkc201-17"

  PrivateRouteB:
    Type: AWS::EC2::Route
    Condition: CreateAnyNAT
    Properties:
      RouteTableId: !Ref PrivateAppRouteTableB
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !If [ CreateMultiAzNAT, !Ref NatGatewayB, !Ref NatGatewayA ]

  PrivateAppRouteTableC:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref ProjectVPC
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-private-app-rt-c"
        - Key: Project
          Value: "nkc201-17"

  PrivateRouteC:
    Type: AWS::EC2::Route
    Condition: CreateAnyNAT
    Properties:
      RouteTableId: !Ref PrivateAppRouteTableC
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !If [ CreateMultiAzNAT, !Ref NatGatewayC, !Ref NatGatewayA ]

  # Isolated Route Table for Data Subnets
  PrivateDataRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref ProjectVPC
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-private-data-rt"
        - Key: Project
          Value: "nkc201-17"

  # =========================================================================
  # Route Table Associations
  # =========================================================================

  # Public Subnets Associations
  PublicSubnetARouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnetA
      RouteTableId: !Ref PublicRouteTable

  PublicSubnetBRouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnetB
      RouteTableId: !Ref PublicRouteTable

  PublicSubnetCRouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnetC
      RouteTableId: !Ref PublicRouteTable

  # Private App Subnets Associations
  PrivateAppSubnetARouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateAppSubnetA
      RouteTableId: !Ref PrivateAppRouteTableA

  PrivateAppSubnetBRouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateAppSubnetB
      RouteTableId: !Ref PrivateAppRouteTableB

  PrivateAppSubnetCRouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateAppSubnetC
      RouteTableId: !Ref PrivateAppRouteTableC

  # Private Data Subnets Associations (Isolated)
  PrivateDataSubnetARouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateDataSubnetA
      RouteTableId: !Ref PrivateDataRouteTable

  PrivateDataSubnetBRouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateDataSubnetB
      RouteTableId: !Ref PrivateDataRouteTable

  PrivateDataSubnetCRouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateDataSubnetC
      RouteTableId: !Ref PrivateDataRouteTable

# =========================================================================
# Outputs
# =========================================================================
Outputs:
  VpcId:
    Description: Created VPC ID
    Value: !Ref ProjectVPC
    
  VpcCidr:
    Description: CIDR block for VPC
    Value: !Ref VpcCidr
    
  PublicSubnetAId:
    Description: Public Subnet A ID
    Value: !Ref PublicSubnetA

  PublicSubnetBId:
    Description: Public Subnet B ID
    Value: !Ref PublicSubnetB

  PublicSubnetCId:
    Description: Public Subnet C ID
    Value: !Ref PublicSubnetC

  PrivateAppSubnetAId:
    Description: Private App Subnet A ID
    Value: !Ref PrivateAppSubnetA

  PrivateAppSubnetBId:
    Description: Private App Subnet B ID
    Value: !Ref PrivateAppSubnetB

  PrivateAppSubnetCId:
    Description: Private App Subnet C ID
    Value: !Ref PrivateAppSubnetC

  PrivateDataSubnetAId:
    Description: Private Data Subnet A ID
    Value: !Ref PrivateDataSubnetA

  PrivateDataSubnetBId:
    Description: Private Data Subnet B ID
    Value: !Ref PrivateDataSubnetB

  PrivateDataSubnetCId:
    Description: Private Data Subnet C ID
    Value: !Ref PrivateDataSubnetC
```
