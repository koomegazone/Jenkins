# Route53 Resolver를 이용한 Centralized Endpoint 구성

## 개요
Route53 Resolver Inbound/Outbound Endpoint와 Forwarding Rules를 사용하여 중앙 집중식 VPC Endpoint를 구성하는 방법입니다.

---

## 아키텍처

```
Hub Account (중앙)
├── VPC Endpoints (Interface Type)
├── Route53 Resolver Inbound Endpoint (DNS 쿼리 수신)
└── Forwarding Rules (선택적)

Spoke Account (사용)
├── Route53 Resolver Outbound Endpoint (DNS 쿼리 전송)
├── Forwarding Rules (Hub Resolver로 전달)
└── RAM 공유로 규칙 수신
```

---

## Route53 Profile vs Resolver 비교

| 항목 | Route53 Profile | Route53 Resolver |
|------|----------------|------------------|
| **출시 시기** | 2024년 (최신) | 2018년 |
| **복잡도** | 간단 | 복잡 |
| **비용** | 무료 | 유료 ($0.125/시간 per endpoint) |
| **설정** | Profile + Association | Inbound + Outbound + Rules |
| **DNS 쿼리 경로** | 자동 | 수동 설정 필요 |
| **권장 사용** | 신규 구성 | 기존 인프라 |

---

## 1단계: Hub VPC에 VPC Endpoints 생성

### 1.1 Interface Type Endpoints 생성

```bash
# 변수 설정
HUB_VPC_ID="vpc-hub-xxx"
HUB_SUBNET_IDS="subnet-hub-a subnet-hub-c"
HUB_SG_ID="sg-hub-endpoint-xxx"
REGION="ap-northeast-2"

# Interface Endpoints 생성
INTERFACE_ENDPOINTS=(
  "ec2"
  "eks"
  "eks-auth"
  "elasticfilesystem"
  "sts"
  "autoscaling"
  "guardduty-data"
  "elasticloadbalancing"
  "ecr.api"
  "ecr.dkr"
)

for endpoint in "${INTERFACE_ENDPOINTS[@]}"; do
  echo "Creating VPC Endpoint for $endpoint..."
  aws ec2 create-vpc-endpoint \
    --vpc-id $HUB_VPC_ID \
    --service-name com.amazonaws.$REGION.$endpoint \
    --vpc-endpoint-type Interface \
    --subnet-ids $HUB_SUBNET_IDS \
    --security-group-ids $HUB_SG_ID \
    --private-dns-enabled \
    --region $REGION
done
```

**중요**: `--private-dns-enabled` 옵션으로 Private DNS 활성화 필수!

---

## 2단계: Hub VPC에 Resolver Inbound Endpoint 생성

### 2.1 Inbound Endpoint 생성

Spoke VPC에서 Hub VPC로 DNS 쿼리를 보낼 수 있도록 Inbound Endpoint를 생성합니다.

```bash
# Inbound Endpoint 생성
aws route53resolver create-resolver-endpoint \
  --name "hub-inbound-endpoint" \
  --creator-request-id "hub-inbound-$(date +%s)" \
  --security-group-ids $HUB_SG_ID \
  --direction INBOUND \
  --ip-addresses \
    SubnetId=subnet-hub-a,Ip=10.1.1.100 \
    SubnetId=subnet-hub-c,Ip=10.1.3.100 \
  --region $REGION
```

**Console 경로:**
- Route 53 → Resolver → Inbound endpoints → Create inbound endpoint
- Name: `hub-inbound-endpoint`
- VPC: Hub VPC 선택
- Security group: Hub Endpoint SG 선택
- IP addresses:
  - Subnet A: 10.1.1.100 (자동 할당 또는 수동 지정)
  - Subnet C: 10.1.3.100

### 2.2 Inbound Endpoint IP 확인

```bash
# Inbound Endpoint IP 주소 확인
aws route53resolver list-resolver-endpoints \
  --filters Name=Name,Values=hub-inbound-endpoint \
  --query 'ResolverEndpoints[0].Id' \
  --output text

INBOUND_ENDPOINT_ID="rslvr-in-xxxxx"

aws route53resolver list-resolver-endpoint-ip-addresses \
  --resolver-endpoint-id $INBOUND_ENDPOINT_ID \
  --query 'IpAddresses[*].Ip' \
  --output table

# 출력 예시:
# 10.1.1.100
# 10.1.3.100
```

**이 IP 주소들을 기억하세요!** Spoke VPC에서 사용합니다.

---

## 3단계: Spoke VPC에 Resolver Outbound Endpoint 생성

### 3.1 Outbound Endpoint 생성

Spoke VPC에서 Hub VPC로 DNS 쿼리를 전달하기 위한 Outbound Endpoint를 생성합니다.

```bash
# Spoke Account로 전환
export AWS_PROFILE=spoke-account

# 변수 설정
SPOKE_VPC_ID="vpc-spoke-xxx"
SPOKE_SUBNET_IDS="subnet-spoke-a subnet-spoke-c"
SPOKE_SG_ID="sg-spoke-resolver-xxx"

# Outbound Endpoint 생성
aws route53resolver create-resolver-endpoint \
  --name "spoke-outbound-endpoint" \
  --creator-request-id "spoke-outbound-$(date +%s)" \
  --security-group-ids $SPOKE_SG_ID \
  --direction OUTBOUND \
  --ip-addresses \
    SubnetId=subnet-spoke-a \
    SubnetId=subnet-spoke-c \
  --region $REGION
```

**Console 경로:**
- Route 53 → Resolver → Outbound endpoints → Create outbound endpoint
- Name: `spoke-outbound-endpoint`
- VPC: Spoke VPC 선택
- Security group: Spoke Resolver SG 선택
- IP addresses: 각 서브넷에 자동 할당

### 3.2 Outbound Endpoint ID 확인

```bash
OUTBOUND_ENDPOINT_ID=$(aws route53resolver list-resolver-endpoints \
  --filters Name=Name,Values=spoke-outbound-endpoint \
  --query 'ResolverEndpoints[0].Id' \
  --output text)

echo "Outbound Endpoint ID: $OUTBOUND_ENDPOINT_ID"
```

---

## 4단계: Forwarding Rules 생성 (Hub Account)

### 4.1 AWS 서비스 도메인용 Forwarding Rules 생성

Hub VPC의 Private DNS를 Spoke VPC에서 조회할 수 있도록 Forwarding Rules를 생성합니다.

```bash
# Hub Account로 전환
export AWS_PROFILE=hub-account

# Inbound Endpoint IP 주소
INBOUND_IPS=("10.1.1.100" "10.1.3.100")

# Forwarding Rules 생성할 도메인 목록
DOMAINS=(
  "ec2.ap-northeast-2.amazonaws.com"
  "eks.ap-northeast-2.amazonaws.com"
  "elasticfilesystem.ap-northeast-2.amazonaws.com"
  "sts.ap-northeast-2.amazonaws.com"
  "autoscaling.ap-northeast-2.amazonaws.com"
  "guardduty-data.ap-northeast-2.amazonaws.com"
  "elasticloadbalancing.ap-northeast-2.amazonaws.com"
  "ecr.ap-northeast-2.amazonaws.com"
)

# 각 도메인에 대해 Forwarding Rule 생성
for domain in "${DOMAINS[@]}"; do
  echo "Creating forwarding rule for $domain..."
  
  aws route53resolver create-resolver-rule \
    --name "forward-${domain}" \
    --creator-request-id "rule-${domain}-$(date +%s)" \
    --rule-type FORWARD \
    --domain-name "$domain" \
    --target-ips \
      Ip=${INBOUND_IPS[0]},Port=53 \
      Ip=${INBOUND_IPS[1]},Port=53 \
    --region $REGION
done
```

**Console 경로:**
- Route 53 → Resolver → Rules → Create rule
- Name: `forward-ec2.ap-northeast-2.amazonaws.com`
- Rule type: Forward
- Domain name: `ec2.ap-northeast-2.amazonaws.com`
- Target IP addresses:
  - 10.1.1.100:53
  - 10.1.3.100:53

### 4.2 생성된 Rules 확인

```bash
# Forwarding Rules 목록 확인
aws route53resolver list-resolver-rules \
  --query 'ResolverRules[?RuleType==`FORWARD`].[Id,Name,DomainName]' \
  --output table
```

---

## 5단계: Forwarding Rules를 RAM으로 공유

### 5.1 Resource Share 생성

```bash
# Forwarding Rule ARN 목록 가져오기
RULE_ARNS=$(aws route53resolver list-resolver-rules \
  --query 'ResolverRules[?RuleType==`FORWARD`].Arn' \
  --output text | tr '\t' ' ')

# RAM Resource Share 생성
aws ram create-resource-share \
  --name "resolver-rules-share" \
  --resource-arns $RULE_ARNS \
  --principals "arn:aws:organizations::ORG_ID:account/SPOKE_ACCOUNT_ID" \
  --region $REGION
```

**Console 경로:**
- AWS RAM → Resource shares → Create resource share
- Name: `resolver-rules-share`
- Resources:
  - Resource type: `Route 53 Resolver Rules`
  - 생성한 모든 Forwarding Rules 선택
- Principals:
  - Spoke Account ID 입력

### 5.2 공유 확인

```bash
aws ram get-resource-shares \
  --resource-owner SELF \
  --name resolver-rules-share \
  --query 'resourceShares[0].[Name,Status]' \
  --output table
```

---

## 6단계: Spoke Account에서 Rules 수락 및 연결

### 6.1 RAM 초대 수락

```bash
# Spoke Account로 전환
export AWS_PROFILE=spoke-account

# 초대 확인
aws ram get-resource-share-invitations \
  --region $REGION

# 초대 수락
aws ram accept-resource-share-invitation \
  --resource-share-invitation-arn "arn:aws:ram:ap-northeast-2:HUB_ACCOUNT:resource-share-invitation/xxxxx" \
  --region $REGION
```

### 6.2 Forwarding Rules를 Spoke VPC에 연결

```bash
# 공유된 Resolver Rules 확인
aws route53resolver list-resolver-rules \
  --query 'ResolverRules[?ShareStatus==`SHARED_WITH_ME`].[Id,Name,DomainName]' \
  --output table

# 각 Rule을 Spoke VPC에 연결
RULE_IDS=$(aws route53resolver list-resolver-rules \
  --query 'ResolverRules[?ShareStatus==`SHARED_WITH_ME`].Id' \
  --output text)

for rule_id in $RULE_IDS; do
  echo "Associating rule $rule_id to Spoke VPC..."
  
  aws route53resolver associate-resolver-rule \
    --resolver-rule-id $rule_id \
    --vpc-id $SPOKE_VPC_ID \
    --region $REGION
done
```

**Console 경로:**
- Route 53 → Resolver → Rules → [공유된 Rule 선택]
- VPCs → Associate VPC
- Spoke VPC 선택 후 Associate

### 6.3 연결 확인

```bash
# VPC에 연결된 Rules 확인
aws route53resolver list-resolver-rule-associations \
  --filters Name=VPCId,Values=$SPOKE_VPC_ID \
  --query 'ResolverRuleAssociations[*].[ResolverRuleId,VPCId,Status]' \
  --output table
```

---

## 7단계: 네트워크 연결 설정

### 7.1 VPC Peering 또는 Transit Gateway

Spoke VPC에서 Hub VPC의 Resolver Inbound Endpoint로 DNS 쿼리를 보내려면 네트워크 연결이 필요합니다.

**옵션 1: VPC Peering**

```bash
# Hub Account에서 Peering 요청
aws ec2 create-vpc-peering-connection \
  --vpc-id $HUB_VPC_ID \
  --peer-vpc-id $SPOKE_VPC_ID \
  --peer-owner-id SPOKE_ACCOUNT_ID \
  --peer-region $REGION

# Spoke Account에서 수락
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id pcx-xxxxx
```

**옵션 2: Transit Gateway**

```bash
# Transit Gateway 생성 및 VPC Attachment
# (상세 내용은 별도 가이드 참조)
```

### 7.2 Route Table 설정

**Hub VPC Route Table:**
```bash
# Spoke VPC CIDR로 가는 경로 추가
aws ec2 create-route \
  --route-table-id rtb-hub-xxx \
  --destination-cidr-block 10.2.0.0/16 \
  --vpc-peering-connection-id pcx-xxxxx
```

**Spoke VPC Route Table:**
```bash
# Hub VPC CIDR로 가는 경로 추가
aws ec2 create-route \
  --route-table-id rtb-spoke-xxx \
  --destination-cidr-block 10.1.0.0/16 \
  --vpc-peering-connection-id pcx-xxxxx
```

### 7.3 Security Group 설정

**Hub Inbound Endpoint SG:**
```bash
# Spoke VPC CIDR에서 DNS (UDP/TCP 53) 허용
aws ec2 authorize-security-group-ingress \
  --group-id $HUB_SG_ID \
  --protocol tcp \
  --port 53 \
  --cidr 10.2.0.0/16

aws ec2 authorize-security-group-ingress \
  --group-id $HUB_SG_ID \
  --protocol udp \
  --port 53 \
  --cidr 10.2.0.0/16
```

**Spoke Outbound Endpoint SG:**
```bash
# Hub VPC CIDR로 DNS (UDP/TCP 53) 허용
aws ec2 authorize-security-group-egress \
  --group-id $SPOKE_SG_ID \
  --protocol tcp \
  --port 53 \
  --cidr 10.1.0.0/16

aws ec2 authorize-security-group-egress \
  --group-id $SPOKE_SG_ID \
  --protocol udp \
  --port 53 \
  --cidr 10.1.0.0/16
```

---

## 8단계: Spoke VPC EC2에서 테스트

### 8.1 DNS Resolution 테스트

```bash
# Spoke VPC EC2에 접속
ssh -i key.pem ec2-user@<SPOKE_EC2_IP>

# EFS Endpoint DNS 조회
nslookup elasticfilesystem.ap-northeast-2.amazonaws.com

# 결과 예시:
# Server:         10.2.0.2 (VPC DNS)
# Address:        10.2.0.2#53
#
# Non-authoritative answer:
# Name:   elasticfilesystem.ap-northeast-2.amazonaws.com
# Address: 10.1.1.50  # Hub VPC의 EFS Endpoint Private IP

# ECR API Endpoint 조회
nslookup api.ecr.ap-northeast-2.amazonaws.com

# S3 Interface Endpoint 조회 (있는 경우)
nslookup s3.ap-northeast-2.amazonaws.com
```

### 8.2 DNS 쿼리 경로 확인

```bash
# DNS 쿼리가 어디로 가는지 확인
dig +trace elasticfilesystem.ap-northeast-2.amazonaws.com

# Resolver 로그 확인 (CloudWatch Logs 설정 필요)
aws route53resolver list-resolver-query-log-configs
```

---

## 9단계: Spoke VPC EKS에서 테스트

### 9.1 EKS 클러스터에서 DNS 확인

```bash
# EKS 클러스터 접속
kubectl run -it --rm debug --image=busybox --restart=Never -- sh

# DNS 조회
nslookup elasticfilesystem.ap-northeast-2.amazonaws.com
nslookup api.ecr.ap-northeast-2.amazonaws.com

# 결과: Hub VPC Endpoint의 Private IP 반환되어야 함
```

### 9.2 EFS CSI Driver 테스트

```bash
# EFS CSI Driver 설치 및 테스트
# (6단계 가이드와 동일)
```

---

## DNS 쿼리 흐름도

```
Spoke VPC EC2/Pod
    ↓ (DNS Query: elasticfilesystem.ap-northeast-2.amazonaws.com)
Spoke VPC DNS (10.2.0.2)
    ↓ (Forwarding Rule 매칭)
Spoke Outbound Endpoint
    ↓ (VPC Peering/TGW)
Hub Inbound Endpoint (10.1.1.100, 10.1.3.100)
    ↓ (Private DNS Resolution)
Hub VPC Endpoint (10.1.1.50)
    ↓ (Response)
Spoke VPC EC2/Pod
```

---

## 비용 계산

### Resolver Endpoints 비용

```bash
# Inbound Endpoint (Hub): 2 ENI
$0.125/시간 × 2 = $0.25/시간
$0.25 × 24시간 × 30일 = $180/월

# Outbound Endpoint (Spoke): 2 ENI
$0.125/시간 × 2 = $0.25/시간
$0.25 × 24시간 × 30일 = $180/월

# 총 비용: $360/월 (Spoke VPC 1개 기준)
```

### DNS 쿼리 비용

```bash
# Outbound Endpoint DNS 쿼리
$0.40 per million queries

# 예시: 1억 쿼리/월
$0.40 × 100 = $40/월
```

### Route53 Profile 비용 (비교)

```bash
# Profile 사용: 무료!
$0/월
```

---

## Route53 Profile vs Resolver 선택 가이드

### Route53 Profile 사용 (권장)
- ✅ 신규 구성
- ✅ 비용 절감 필요
- ✅ 간단한 설정 선호
- ✅ AWS 서비스 Endpoint만 사용

### Route53 Resolver 사용
- ✅ 기존 Resolver 인프라 존재
- ✅ On-Premise DNS 통합 필요
- ✅ 복잡한 DNS 라우팅 필요
- ✅ 커스텀 도메인 Forwarding 필요

---

## 트러블슈팅

### DNS Resolution 실패

```bash
# 1. Forwarding Rule 연결 확인
aws route53resolver list-resolver-rule-associations \
  --filters Name=VPCId,Values=$SPOKE_VPC_ID

# 2. Outbound Endpoint 상태 확인
aws route53resolver list-resolver-endpoints \
  --filters Name=Direction,Values=OUTBOUND

# 3. 네트워크 연결 확인
# Spoke VPC에서 Hub Inbound Endpoint IP로 ping
ping 10.1.1.100

# 4. Security Group 확인
# DNS 포트 53 (TCP/UDP) 허용 확인
```

### DNS 쿼리가 Hub로 안 가는 경우

```bash
# Forwarding Rule 우선순위 확인
aws route53resolver list-resolver-rules \
  --query 'ResolverRules[*].[Name,DomainName,Status]' \
  --output table

# VPC DNS 설정 확인
aws ec2 describe-vpc-attribute \
  --vpc-id $SPOKE_VPC_ID \
  --attribute enableDnsHostnames

aws ec2 describe-vpc-attribute \
  --vpc-id $SPOKE_VPC_ID \
  --attribute enableDnsSupport
```

---

## 참고 자료

- [Route 53 Resolver Documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html)
- [Resolver Endpoints](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver-endpoints.html)
- [Forwarding Rules](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver-rules-managing.html)
