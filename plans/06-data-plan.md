# 06 Data Stack - 資料層建置計畫

本計畫紀錄了 EKS 智能維運專題中資料儲存層（包含 S3、RDS MySQL、Secrets Manager）的建置規劃與安全認證設計，方便導入 Obsidian 閱讀與複習。

## 💡 費曼學習法：密碼貼在額頭上，還是放進保險箱？

### 1. 🗄️ AWS Secrets Manager (安全保險箱)
- **問題（傳統寫法）：** 我們在寫網頁程式碼或腳本時，常會直接寫入密碼：`password = "123456"`。這就像是把保險箱密碼寫在便利貼上，**直接貼在程式機器人的額頭上**。當您把程式碼 Git Push 到 GitHub 後，全世界的人都可以輕鬆看到便利貼上的密碼，造成嚴重安全危機。
- **解法（Secrets Manager 做法）：** 我們將敏感的資料庫密碼和金鑰，存放在 AWS 的專利「保險箱」（Secrets Manager）裡。
  - 當程式（EKS Pod）想要讀取資料庫時，它會走到保險箱前。
  - 保險箱會先核對程式的指紋（**IAM Role / Pod Identity 權限**）。
  - 確認無誤後，保險箱會吐出當下的密碼給程式使用。程式使用完畢後立即將密碼從暫存中抹除。
  - **好處：** 您的程式碼或 YAML 藍圖中，**永遠不會有明文密碼出現**。

### 2. 🔐 動態密碼解析 (Dynamic Resolve) 
- 我們的 RDS 資料庫在建立時，利用了 AWS CloudFormation 的內建動態讀取語法：
  `MasterUserPassword: !Sub "{{resolve:secretsmanager:${DatabaseSecret}:SecretString:password}}"`
- **意思：** 「請 CloudFormation 在建立資料庫時，自己去指定的 Secrets Manager 保險箱讀取自動隨機產生的 `password` 數值並填入。」
- 這真正實現了**密碼不落地**的安全合規標準。

---

## 🛠️ 完整的 CloudFormation 藍圖

已寫入：`CloudFromation/nkc201-17-06-data-stack.yaml`

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: AWS EKS AIOps Data Stack containing S3, Secrets Manager and RDS MySQL

Parameters:
  ProjectName:
    Type: String
    Default: eks-aiops-demo
    Description: Project name used for resource naming

  VpcId:
    Type: AWS::EC2::VPC::Id
    Description: VPC ID where resources will be deployed (from Stack 01)

  PrivateDataSubnets:
    Type: List<AWS::EC2::Subnet::Id>
    Description: The 3 Private Data Subnets for DB Subnet Group (from Stack 01)

  RdsSecurityGroupId:
    Type: AWS::EC2::SecurityGroup::Id
    Description: Security Group ID for RDS Database (from Stack 02)

  DatabaseEngine:
    Type: String
    Default: mysql
    AllowedValues: [mysql]
    Description: Database engine type

  DatabaseEngineVersion:
    Type: String
    Default: '8.0'
    Description: Database engine version

  DatabaseInstanceClass:
    Type: String
    Default: db.t3.micro
    Description: Database instance class for testing (cost-efficient)

  AllocatedStorage:
    Type: Number
    Default: 20
    Description: Allocated storage size in GB for database

Resources:
  # 1. S3 Bucket
  DataBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "${ProjectName}-${AWS::AccountId}-data-bucket"
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      VersioningConfiguration:
        Status: Enabled
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-data-bucket"
        - Key: Project
          Value: nkc201-17

  # 2. Secrets Manager
  DatabaseSecret:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub "${ProjectName}-rds-secret"
      Description: Database credentials for RDS MySQL
      GenerateSecretString:
        SecretStringTemplate: '{"username": "admin"}'
        GenerateStringKey: password
        PasswordLength: 16
        ExcludeCharacters: '"@/\' '

  # 3. RDS DB Subnet Group
  DbSubnetGroup:
    Type: AWS::RDS::DBSubnetGroup
    Properties:
      DBSubnetGroupDescription: Subnet group for RDS database
      SubnetIds: !Ref PrivateDataSubnets
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-db-subnet-group"
        - Key: Project
          Value: nkc201-17

  # 4. RDS DB Instance
  RdsDatabase:
    Type: AWS::RDS::DBInstance
    DeletionPolicy: Delete
    Properties:
      DBInstanceIdentifier: !Sub "${ProjectName}-rds-db"
      Engine: !Ref DatabaseEngine
      EngineVersion: !Ref DatabaseEngineVersion
      DBInstanceClass: !Ref DatabaseInstanceClass
      AllocatedStorage: !Ref AllocatedStorage
      DBSubnetGroupName: !Ref DbSubnetGroup
      VPCSecurityGroups:
        - !Ref RdsSecurityGroupId
      MasterUsername: !Sub "{{resolve:secretsmanager:${DatabaseSecret}:SecretString:username}}"
      MasterUserPassword: !Sub "{{resolve:secretsmanager:${DatabaseSecret}:SecretString:password}}"
      PubliclyAccessible: false
      MultiAZ: false
      StorageType: gp3
      StorageEncrypted: true
      BackupRetentionPeriod: 7
      Tags:
        - Key: Name
          Value: !Sub "${ProjectName}-rds-db"
        - Key: Project
          Value: nkc201-17

Outputs:
  S3BucketName:
    Description: Name of the created S3 Data Bucket
    Value: !Ref DataBucket

  SecretsManagerArn:
    Description: ARN of the Secrets Manager Secret
    Value: !Ref DatabaseSecret

  RdsEndpoint:
    Description: Endpoint address of the RDS DB Instance
    Value: !GetAtt RdsDatabase.Endpoint.Address

  RdsPort:
    Description: Port of the RDS DB Instance
    Value: !GetAtt RdsDatabase.Endpoint.Port
```

---

## 💻 部署指令參考

請在您的專題資料夾下開啟 **PowerShell** 執行以下指令進行部署（採用 UTF-8 原生文字讀取以避開 Windows 系統編碼錯誤）：

```powershell
# 1. 先鎖定登入 Profile
$env:AWS_PROFILE="nkc201-17-sso"

# 2. 執行部署指令 (請將 <...> 替換成實際資料)
aws cloudformation create-stack `
  --stack-name nkc201-17-data `
  --template-body (Get-Content CloudFromation/nkc201-17-06-data-stack.yaml -Raw -Encoding UTF8) `
  --parameters `
    ParameterKey=VpcId,ParameterValue=<您的VpcId，如 vpc-00f9f872d1cede59e> `
    ParameterKey=RdsSecurityGroupId,ParameterValue=<您的RdsSecurityGroupId，如 sg-xxxxxx> `
    ParameterKey=PrivateDataSubnets,ParameterValue=<您的3個PrivateDataSubnetID，以逗號分隔>
```
*(💡 提示：多個子網路 ID 請使用半形逗號 `,` 分開，中間不要有任何空格)*

---

## 🔑 常用維運指令與資料庫連線指南

### 1. 如何查看 Secrets Manager 自動產生的隨機資料庫密碼？
因為我們讓 Secrets Manager 自動亂數生成高強度密碼，您在網頁上是看不到的。但您可以執行此 AWS CLI 指令，直接向保險箱調閱帳密：

```powershell
# 請確保已執行 $env:AWS_PROFILE="nkc201-17-sso"
aws secretsmanager get-secret-value --secret-id eks-aiops-demo-rds-secret --query "SecretString" --output text
```
* **執行後會輸出 JSON 格式的帳密：**
  ```json
  {"username": "admin", "password": "gH8#kL2!mP9$xY7q"}
  ```

---

### 2. 本地電腦該如何連線到這個 RDS 資料庫？
> [!CAUTION]
> **您無法直接從家裡的電腦連線！**
> 因為安全考量，資料庫符合以下嚴格條件：
> 1. `PubliclyAccessible` 設為 `false`（不對公網發行 IP）。
> 2. `VPCSecurityGroups` 限制了只有 **EKS 節點** 才能存取。
> 3. 資料庫位於 **Private Data Subnet** (私有子網路) 中。

#### 正常專題運作時，連線是由「程式」處理：
部署在 EKS 工作節點上的網站 Pod（Nginx/PHP/Python 等），因為與 RDS 處於同一個 VPC 內網，且擁有 EKS Node 識別證，所以程式可以直接透過 RDS Endpoint 連線到資料庫：
- **Host / Endpoint：** 可從 Stack 06 部署完的 Outputs 取得 `RdsEndpoint`（例如：`eks-aiops-demo-db.xxxxxx.ap-south-1.rds.amazonaws.com`）
- **Port：** `3306`
- **Username / Password：** 程式會自動向 Secrets Manager 讀取（免手動輸入）。

#### 如果工程師想要手動進去下 SQL 指令測試：
實務上，我們會透過以下兩種安全方式：
1. **SSM Port Forwarding (埠口轉發隧道)：**
   利用 SSM Agent，在您的本地電腦與私有子網路的節點間建立一條臨時的加密隧道，將本地的 `3306` 埠口對接到遠端 RDS 的 `3306` 埠口。這樣您就能在本地用 DBeaver 或 MySQL Workbench 連線 `localhost:3306` 來操作遠端資料庫！
2. **跳板機 (Bastion Host)：**
   在公有子網路建一台微型的 EC2 跳板機，工程師先登入跳板機，再從跳板機連線進 RDS。
