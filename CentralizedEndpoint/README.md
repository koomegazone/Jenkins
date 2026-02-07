# Centralized Endpoint 자동 설정 스크립트

## 개요
이 스크립트들은 Route53 Resolver와 Forwarding Rules를 사용하여 Hub-Spoke 아키텍처의 Centralized VPC Endpoint를 자동으로 구성합니다.

## 사전 요구사항

### AWS Profile 설정
```bash
# Hub Account (profile: koo)
aws configure --profile koo

# Spoke Account (profile: default)
aws configure
```

### 필요한 정보
- Hub VPC ID, Subnet IDs, CIDR
- Spoke VPC ID, Subnet IDs, CIDR
- Hub Account ID, Spoke Account ID
- Route Table IDs

## 실행 순서

### 1단계: Hub VPC 설정

```bash
cd CentralizedEndpoint
chmod +x setup-hub.sh
./setup-hub.sh
```

**입력 정보:**
- Hub VPC ID
- Hub Private Subnet A ID
- Hub Private Subnet C ID
- Hub VPC CIDR (예: 10.1.0.0/16)
- Spoke VPC CIDR (예: 10.2.0.0/16)
- Spoke Account ID
- Hub Route Table IDs (S3 Gateway Endpoint용)
- Inbound Endpoint IP 주소 (선택, 비워두면 자동)

**생성되는 리소스:**
- VPC Endpoint Security Group
- Interface Endpoints (EC2, EKS, EFS, STS, Auto Scaling, ELB, ECR API, ECR DKR)
- S3 Gateway Endpoint
- Route53 Resolver Inbound Endpoint
- Forwarding Rules (7개)
- RAM Resource Share

**출력:**
- `hub-config.txt`: Hub VPC 설정 정보 저장
- Inbound Endpoint IP 주소 (Spoke 설정에 필요)

### 2단계: Spoke VPC 설정

```bash
chmod +x setup-spoke.sh
./setup-spoke.sh
```

**입력 정보:**
- Spoke VPC ID
- Spoke Private Subnet A ID
- Spoke Private Subnet C ID
- Spoke VPC CIDR (예: 10.2.0.0/16)
- Hub VPC CIDR (예: 10.1.0.0/16)
- Hub Inbound Endpoint IP 1 (setup-hub.sh 출력에서 확인)
- Hub Inbound Endpoint IP 2
- Hub Account ID

**생성되는 리소스:**
- Resolver Security Group
- Route53 Resolver Outbound Endpoint
- Forwarding Rules Association (VPC 연결)

**출력:**
- `spoke-config.txt`: Spoke VPC 설정 정보 저장

### 3단계: 네트워크 연결 (VPC Peering)

스크립트가 안내하는 대로 VPC Peering을 설정하거나, 수동으로 설정:

**Hub Account (profile: koo):**
```bash
aws ec2 create-vpc-peering-connection \
  --vpc-id <HUB_VPC_ID> \
  --peer-vpc-id <SPOKE_VPC_ID> \
  --peer-owner-id <SPOKE_ACCOUNT_ID> \
  --peer-region ap-northeast-2 \
  --profile koo
```

**Spoke Account (profile: default):**
```bash
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id <PEERING_ID>
```

**Route Table 설정:**
```bash
# Spoke VPC Route Table
aws ec2 create-route \
  --route-table-id <SPOKE_RT_ID> \
  --destination-cidr-block <HUB_VPC_CIDR> \
  --vpc-peering-connection-id <PEERING_ID>

# Hub VPC Route Table (profile: koo)
aws ec2 create-route \
  --route-table-id <HUB_RT_ID> \
  --destination-cidr-block <SPOKE_VPC_CIDR> \
  --vpc-peering-connection-id <PEERING_ID> \
  --profile koo
```

### 4단계: DNS Resolution 테스트

Spoke VPC의 EC2 인스턴스에서 실행:

```bash
# 스크립트 복사
scp -i key.pem test-dns.sh ec2-user@<SPOKE_EC2_IP>:~

# EC2 접속
ssh -i key.pem ec2-user@<SPOKE_EC2_IP>

# 테스트 실행
chmod +x test-dns.sh
./test-dns.sh
```

**예상 결과:**
```
테스트: ec2.ap-northeast-2.amazonaws.com
  ✓ 성공: 10.1.1.50 (Hub VPC Endpoint)

테스트: eks.ap-northeast-2.amazonaws.com
  ✓ 성공: 10.1.1.51 (Hub VPC Endpoint)

...

성공: 7 / 7
✓ 모든 DNS Resolution이 정상적으로 Hub VPC Endpoint를 사용합니다!
```

## 생성된 파일

```
CentralizedEndpoint/
├── README.md                          # 이 파일
├── setup-hub.sh                       # Hub VPC 설정 스크립트
├── setup-spoke.sh                     # Spoke VPC 설정 스크립트
├── test-dns.sh                        # DNS 테스트 스크립트
├── hub-config.txt                     # Hub 설정 정보 (자동 생성)
├── spoke-config.txt                   # Spoke 설정 정보 (자동 생성)
├── centralized-endpoint-guide.md      # Route53 Profile 가이드
└── resolver-forwarding-guide.md       # Resolver 상세 가이드
```

## 트러블슈팅

### DNS Resolution 실패

```bash
# 1. Forwarding Rules 연결 확인
aws route53resolver list-resolver-rule-associations \
  --filters Name=VPCId,Values=<SPOKE_VPC_ID>

# 2. Outbound Endpoint 상태 확인
aws route53resolver list-resolver-endpoints \
  --filters Name=Direction,Values=OUTBOUND

# 3. Inbound Endpoint 상태 확인 (profile: koo)
aws route53resolver list-resolver-endpoints \
  --filters Name=Direction,Values=INBOUND \
  --profile koo

# 4. VPC Peering 상태 확인
aws ec2 describe-vpc-peering-connections \
  --filters Name=status-code,Values=active
```

### Security Group 확인

```bash
# Hub Endpoint SG
aws ec2 describe-security-groups \
  --group-ids <HUB_ENDPOINT_SG_ID> \
  --profile koo

# Spoke Resolver SG
aws ec2 describe-security-groups \
  --group-ids <SPOKE_RESOLVER_SG_ID>
```

### 네트워크 연결 테스트

```bash
# Spoke EC2에서 Hub Inbound Endpoint로 ping
ping <HUB_INBOUND_IP>

# DNS 쿼리 테스트
nslookup elasticfilesystem.ap-northeast-2.amazonaws.com
dig elasticfilesystem.ap-northeast-2.amazonaws.com
```

## 정리 (Clean Up)

### Spoke VPC 리소스 삭제

```bash
# Forwarding Rules 연결 해제
aws route53resolver list-resolver-rule-associations \
  --filters Name=VPCId,Values=<SPOKE_VPC_ID> \
  --query 'ResolverRuleAssociations[*].Id' \
  --output text | xargs -I {} aws route53resolver disassociate-resolver-rule --resolver-rule-association-id {}

# Outbound Endpoint 삭제
aws route53resolver delete-resolver-endpoint \
  --resolver-endpoint-id <OUTBOUND_ENDPOINT_ID>

# Security Group 삭제
aws ec2 delete-security-group \
  --group-id <SPOKE_RESOLVER_SG_ID>
```

### Hub VPC 리소스 삭제 (profile: koo)

```bash
# RAM Resource Share 삭제
aws ram delete-resource-share \
  --resource-share-arn <RESOURCE_SHARE_ARN> \
  --profile koo

# Forwarding Rules 삭제
aws route53resolver list-resolver-rules \
  --query 'ResolverRules[?RuleType==`FORWARD`].Id' \
  --output text \
  --profile koo | xargs -I {} aws route53resolver delete-resolver-rule --resolver-rule-id {} --profile koo

# Inbound Endpoint 삭제
aws route53resolver delete-resolver-endpoint \
  --resolver-endpoint-id <INBOUND_ENDPOINT_ID> \
  --profile koo

# VPC Endpoints 삭제
aws ec2 describe-vpc-endpoints \
  --filters Name=vpc-id,Values=<HUB_VPC_ID> \
  --query 'VpcEndpoints[*].VpcEndpointId' \
  --output text \
  --profile koo | xargs -I {} aws ec2 delete-vpc-endpoints --vpc-endpoint-ids {} --profile koo

# Security Group 삭제
aws ec2 delete-security-group \
  --group-id <HUB_ENDPOINT_SG_ID> \
  --profile koo
```

## 비용 예상

### Resolver Endpoints
- Inbound Endpoint (Hub): $180/월
- Outbound Endpoint (Spoke): $180/월
- **총 $360/월** (Spoke VPC 1개 기준)

### DNS 쿼리
- $0.40 per million queries
- 예: 1억 쿼리/월 = $40/월

### VPC Endpoints
- Interface Endpoints: 무료 (데이터 전송 비용만)
- Gateway Endpoints (S3): 무료

## 참고 자료

- [resolver-forwarding-guide.md](./resolver-forwarding-guide.md) - 상세 가이드
- [centralized-endpoint-guide.md](./centralized-endpoint-guide.md) - Route53 Profile 방식
- [AWS Route 53 Resolver Documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html)
