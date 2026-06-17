# 04 EKS Cluster Stack - EKS 叢集大腦建置計畫

本計畫紀錄了 EKS 智能維運專題中 K8s 控制面大腦（Control Plane）的建置規劃與四大核心外掛套件安裝，方便導入 Obsidian 閱讀與複習。

## 💡 費曼學習法：叢集大腦與大樓水電系統

### 1. 🧠 EKS Cluster (大樓總指揮部)
- **比喻：** 它是這間自動化大工廠的 **「總指揮大腦」**。
- **用途：** 負責派發工作、看守各節點狀態、監控容器 Pod 是否正常運作。它自己不出力（體力活由 Stack 05 Node Group 幹），只做決策與排程。

### 2. 🔌 四大外掛 Addons (大樓基本維運水電系統)
為了讓指揮部正常運作，大樓需要配備核心系統：
- **VPC CNI (配電系統)：** 讓 Pod 可以直接獲得 VPC 的實體 IP，就像大樓裡的每個機器直接插上獨立插座一樣，傳輸速度最快。
- **CoreDNS (內部通訊簿)：** Pod 之間打電話找對方時，不需要去記複雜的 IP 地址，只要查 CoreDNS 的「分機名稱」即可。
- **Kube-Proxy (走廊指引員)：** 指引網絡流量，如果有外部流量進入，它負責平均分配給工作的 Pod 們。
- **EKS Pod Identity Agent (臨時證派發機)：** 負責為 Pod 檢查 IAM 識別證，並派發有時效性的臨時金鑰，讓 ALB Controller 和 K8sGPT 能夠呼叫 AWS 服務。

---

## 🛠️ 完整的 CloudFormation 藍圖

已寫入：`CloudFromation/nkc201-17-04-eks-cluster-stack.yaml`

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: AWS EKS Cluster Control Plane Stack with standard addons

Parameters:
  ProjectName:
    Type: String
    Default: eks-aiops-demo
    Description: Project name used for resource naming

  ClusterName:
    Type: String
    Default: eks-aiops-mumbai
    Description: The name of the EKS cluster

  KubernetesVersion:
    Type: String
    Default: '1.30'
    Description: Kubernetes Version of the EKS cluster

  EksClusterRoleArn:
    Type: String
    Description: ARN of the IAM role for EKS cluster control plane (from Stack 03)

  SecurityGroupIds:
    Type: List<AWS::EC2::SecurityGroup::Id>
    Description: Security Group to associate with the cluster control plane (from Stack 02)

  SubnetIds:
    Type: List<AWS::EC2::Subnet::Id>
    Description: The 3 Private App Subnet IDs for EKS control plane (from Stack 01)

Resources:
  EksCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      Version: !Ref KubernetesVersion
      RoleArn: !Ref EksClusterRoleArn
      ResourcesVpcConfig:
        SecurityGroupIds: !Ref SecurityGroupIds
        SubnetIds: !Ref SubnetIds
        EndpointPublicAccess: true
        EndpointPrivateAccess: true
      Tags:
        - Key: Name
          Value: !Ref ClusterName
        - Key: Project
          Value: nkc201-17

  VpcCniAddon:
    Type: AWS::EKS::Addon
    Properties:
      AddonName: vpc-cni
      ClusterName: !Ref EksCluster
      ResolveConflicts: OVERWRITE

  CoreDnsAddon:
    Type: AWS::EKS::Addon
    Properties:
      AddonName: coredns
      ClusterName: !Ref EksCluster
      ResolveConflicts: OVERWRITE

  KubeProxyAddon:
    Type: AWS::EKS::Addon
    Properties:
      AddonName: kube-proxy
      ClusterName: !Ref EksCluster
      ResolveConflicts: OVERWRITE

  PodIdentityAddon:
    Type: AWS::EKS::Addon
    Properties:
      AddonName: eks-pod-identity-agent
      ClusterName: !Ref EksCluster
      ResolveConflicts: OVERWRITE

Outputs:
  ClusterName:
    Description: The name of the EKS Cluster
    Value: !Ref EksCluster
    Export:
      Name: !Sub "${AWS::StackName}-ClusterName"

  ClusterArn:
    Description: The ARN of the EKS Cluster
    Value: !GetAtt EksCluster.Arn
    Export:
      Name: !Sub "${AWS::StackName}-ClusterArn"

  ClusterEndpoint:
    Description: EKS Cluster API Server Endpoint
    Value: !GetAtt EksCluster.Endpoint
    Export:
      Name: !Sub "${AWS::StackName}-ClusterEndpoint"

  ClusterSecurityGroupId:
    Description: EKS security group created by AWS EKS service itself
    Value: !GetAtt EksCluster.ClusterSecurityGroupId
    Export:
      Name: !Sub "${AWS::StackName}-ClusterSecurityGroupId"
```

---

## 💻 部署指令參考

在 Windows 中部署此 Cluster Stack：
```powershell
aws cloudformation create-stack `
  --stack-name eks-aiops-cluster `
  --template-body file://CloudFromation/nkc201-17-04-eks-cluster-stack.yaml `
  --parameters `
    ParameterKey=EksClusterRoleArn,ParameterValue=arn:aws:iam::您的帳號:role/eks-aiops-demo-eks-cluster-role `
    ParameterKey=SecurityGroupIds,ParameterValue=sg-您的安全群組ID `
    ParameterKey=SubnetIds,ParameterValue=subnet-A區ID`,subnet-B區ID`,subnet-C區ID`
```
*(注意：多個子網路 ID 請使用半形逗號 `,` 分隔)*
