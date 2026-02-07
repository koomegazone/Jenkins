#!/bin/bash

# Spoke VPC 설정 스크립트
# Profile: default (Spoke Account)
#
# 사용법:
#   ./setup-spoke.sh [SPOKE_VPC_ID] [HUB_ACCOUNT_ID]
#
# 예시:
#   ./setup-spoke.sh vpc-xxx 064711168361

set -e

echo "=========================================="
echo "Spoke VPC Centralized Endpoint 설정 시작"
echo "Profile: default (Spoke Account)"
echo "=========================================="

# 변수 설정
export AWS_PROFILE=default
REGION="ap-northeast-2"

# 명령줄 인자로 받기
if [ $# -eq 2 ]; then
    SPOKE_VPC_ID=$1
    HUB_ACCOUNT_ID=$2
    echo ""
    echo "명령줄 인자 사용:"
else
    echo ""
    echo "대화형 모드 (명령줄 인자 미제공)"
    echo ""
    # Spoke VPC 정보 입력
    read -p "Spoke VPC ID를 입력하세요 (예: vpc-xxx): " SPOKE_VPC_ID
    read -p "Hub Account ID를 입력하세요: " HUB_ACCOUNT_ID
fi

echo ""
echo "입력된 정보:"
echo "  Spoke VPC ID: $SPOKE_VPC_ID"
echo "  Spoke Subnet A: $SPOKE_SUBNET_A"
echo "  Spoke Subnet C: $SPOKE_SUBNET_C"
echo "  Spoke VPC CIDR: $SPOKE_VPC_CIDR"
echo "  Hub VPC CIDR: $HUB_VPC_CIDR"
echo "  Hub Inbound IPs: $INBOUND_IP_1, $INBOUND_IP_2"
echo "  Hub Account ID: $HUB_ACCOUNT_ID"
echo ""
read -p "계속하시겠습니까? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "취소되었습니다."
    exit 0
fi

# 1. Resolver용 Security Group 생성
echo ""
echo "[1/5] Resolver용 Security Group 생성 중..."
SPOKE_RESOLVER_SG_ID=$(aws ec2 create-security-group \
    --group-name "spoke-resolver-sg" \
    --description "Security group for Spoke Resolver Endpoints" \
    --vpc-id $SPOKE_VPC_ID \
    --region $REGION \
    --query 'GroupId' \
    --output text)

echo "  ✓ Security Group 생성 완료: $SPOKE_RESOLVER_SG_ID"

# Security Group 규칙 추가
echo "  - DNS (53) Outbound 허용 추가 중..."
aws ec2 authorize-security-group-egress \
    --group-id $SPOKE_RESOLVER_SG_ID \
    --protocol tcp \
    --port 53 \
    --cidr $HUB_VPC_CIDR \
    --region $REGION > /dev/null

aws ec2 authorize-security-group-egress \
    --group-id $SPOKE_RESOLVER_SG_ID \
    --protocol udp \
    --port 53 \
    --cidr $HUB_VPC_CIDR \
    --region $REGION > /dev/null

echo "  ✓ Security Group 규칙 추가 완료"

# 2. Route53 Resolver Outbound Endpoint 생성
echo ""
echo "[2/5] Route53 Resolver Outbound Endpoint 생성 중..."

OUTBOUND_ENDPOINT_ID=$(aws route53resolver create-resolver-endpoint \
    --name "spoke-outbound-endpoint" \
    --creator-request-id "spoke-outbound-$(date +%s)" \
    --security-group-ids $SPOKE_RESOLVER_SG_ID \
    --direction OUTBOUND \
    --ip-addresses SubnetId=$SPOKE_SUBNET_A SubnetId=$SPOKE_SUBNET_C \
    --region $REGION \
    --query 'ResolverEndpoint.Id' \
    --output text)

echo "  ✓ Outbound Endpoint 생성 완료: $OUTBOUND_ENDPOINT_ID"
echo "  - 상태가 OPERATIONAL이 될 때까지 대기 중..."

while true; do
    STATUS=$(aws route53resolver get-resolver-endpoint \
        --resolver-endpoint-id $OUTBOUND_ENDPOINT_ID \
        --region $REGION \
        --query 'ResolverEndpoint.Status' \
        --output text)
    
    if [ "$STATUS" == "OPERATIONAL" ]; then
        echo "  ✓ Outbound Endpoint가 활성화되었습니다"
        break
    fi
    echo "    현재 상태: $STATUS (대기 중...)"
    sleep 10
done

# 3. Forwarding Rules 생성 (Spoke Outbound Endpoint 사용)
echo ""
echo "[3/5] Forwarding Rules 생성 중..."

DOMAINS=(
    "ec2.ap-northeast-2.amazonaws.com"
    "eks.ap-northeast-2.amazonaws.com"
    "elasticfilesystem.ap-northeast-2.amazonaws.com"
    "sts.ap-northeast-2.amazonaws.com"
    "autoscaling.ap-northeast-2.amazonaws.com"
    "elasticloadbalancing.ap-northeast-2.amazonaws.com"
    "ecr.ap-northeast-2.amazonaws.com"
)

RULE_IDS=()

for domain in "${DOMAINS[@]}"; do
    echo "  - $domain 규칙 생성 중..."
    
    # Rule 이름 생성 (점을 하이픈으로 변경)
    RULE_NAME=$(echo "forward-${domain}" | sed 's/\./-/g')
    
    # 기존 Rule 확인
    EXISTING_RULE=$(aws route53resolver list-resolver-rules \
        --region $REGION \
        --query "ResolverRules[?DomainName=='$domain' && RuleType=='FORWARD'].Id" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$EXISTING_RULE" ] && [ "$EXISTING_RULE" != "None" ]; then
        echo "    ✓ 기존 Rule 사용: $EXISTING_RULE"
        RULE_IDS+=($EXISTING_RULE)
    else
        RULE_ID=$(aws route53resolver create-resolver-rule \
            --name "$RULE_NAME" \
            --creator-request-id "rule-${domain}-$(date +%s)" \
            --rule-type FORWARD \
            --domain-name "$domain" \
            --resolver-endpoint-id $OUTBOUND_ENDPOINT_ID \
            --target-ips "Ip=$INBOUND_IP_1,Port=53" "Ip=$INBOUND_IP_2,Port=53" \
            --region $REGION \
            --query 'ResolverRule.Id' \
            --output text)
        
        RULE_IDS+=($RULE_ID)
        echo "    ✓ 완료: $RULE_ID"
        sleep 1
    fi
done

echo "  ✓ 모든 Forwarding Rules 생성 완료"

# 4. Forwarding Rules를 Spoke VPC에 연결
echo ""
echo "[4/5] Forwarding Rules를 Spoke VPC에 연결 중..."

for rule_id in "${RULE_IDS[@]}"; do
    RULE_NAME=$(aws route53resolver get-resolver-rule \
        --resolver-rule-id $rule_id \
        --region $REGION \
        --query 'ResolverRule.Name' \
        --output text 2>/dev/null || echo "unknown")
    
    # 기존 Association 확인
    EXISTING_ASSOC=$(aws route53resolver list-resolver-rule-associations \
        --filters Name=ResolverRuleId,Values=$rule_id Name=VPCId,Values=$SPOKE_VPC_ID \
        --region $REGION \
        --query 'ResolverRuleAssociations[0].Id' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$EXISTING_ASSOC" ] && [ "$EXISTING_ASSOC" != "None" ]; then
        echo "  ✓ $RULE_NAME 이미 연결됨"
    else
        echo "  - $RULE_NAME 연결 중..."
        
        aws route53resolver associate-resolver-rule \
            --resolver-rule-id $rule_id \
            --vpc-id $SPOKE_VPC_ID \
            --region $REGION \
            --no-cli-pager > /dev/null
        
        echo "    ✓ 완료"
        sleep 2
    fi
done

echo "  ✓ 모든 Forwarding Rules 연결 완료"

# 5. 네트워크 연결 확인 및 안내
echo ""
echo "[5/5] 네트워크 연결 확인..."

echo ""
echo "⚠️  중요: VPC Peering 또는 Transit Gateway 설정이 필요합니다!"
echo ""
echo "Spoke VPC에서 Hub VPC로 DNS 쿼리를 보내려면 네트워크 연결이 필요합니다."
echo ""
echo "옵션 1: VPC Peering"
echo "  1. Hub Account에서 Peering 요청 생성"
echo "  2. Spoke Account에서 Peering 수락"
echo "  3. 양쪽 Route Table에 경로 추가"
echo ""
echo "옵션 2: Transit Gateway"
echo "  1. Transit Gateway 생성"
echo "  2. Hub VPC와 Spoke VPC Attachment 생성"
echo "  3. Route Table 설정"
echo ""

read -p "VPC Peering을 지금 설정하시겠습니까? (y/n): " SETUP_PEERING

if [ "$SETUP_PEERING" == "y" ]; then
    echo ""
    echo "VPC Peering 설정을 시작합니다..."
    
    # Peering 요청 (Hub에서 실행해야 함)
    echo ""
    echo "⚠️  다음 명령어를 Hub Account (profile: koo)에서 실행하세요:"
    echo ""
    echo "aws ec2 create-vpc-peering-connection \\"
    echo "  --vpc-id <HUB_VPC_ID> \\"
    echo "  --peer-vpc-id $SPOKE_VPC_ID \\"
    echo "  --peer-owner-id \$(aws sts get-caller-identity --query Account --output text) \\"
    echo "  --peer-region $REGION \\"
    echo "  --profile koo"
    echo ""
    
    read -p "Peering 요청이 생성되었으면 Peering Connection ID를 입력하세요: " PEERING_ID
    
    if [ ! -z "$PEERING_ID" ]; then
        echo ""
        echo "Peering 요청을 수락합니다..."
        aws ec2 accept-vpc-peering-connection \
            --vpc-peering-connection-id $PEERING_ID \
            --region $REGION \
            --no-cli-pager > /dev/null
        
        echo "  ✓ Peering 수락 완료"
        
        # Route Table 설정 안내
        echo ""
        echo "⚠️  Route Table 설정이 필요합니다:"
        echo ""
        echo "Spoke VPC Route Table에 다음 경로 추가:"
        echo "  Destination: $HUB_VPC_CIDR"
        echo "  Target: $PEERING_ID"
        echo ""
        echo "Hub VPC Route Table에 다음 경로 추가 (Hub Account에서 실행):"
        echo "  Destination: $SPOKE_VPC_CIDR"
        echo "  Target: $PEERING_ID"
        echo ""
        
        read -p "Spoke VPC Route Table ID를 입력하세요: " SPOKE_RT_ID
        
        if [ ! -z "$SPOKE_RT_ID" ]; then
            aws ec2 create-route \
                --route-table-id $SPOKE_RT_ID \
                --destination-cidr-block $HUB_VPC_CIDR \
                --vpc-peering-connection-id $PEERING_ID \
                --region $REGION > /dev/null
            
            echo "  ✓ Spoke VPC Route 추가 완료"
        fi
    fi
fi

# 완료 메시지
echo ""
echo "=========================================="
echo "Spoke VPC 설정 완료!"
echo "=========================================="
echo ""
echo "생성된 리소스:"
echo "  - Resolver Security Group: $SPOKE_RESOLVER_SG_ID"
echo "  - Resolver Outbound Endpoint: $OUTBOUND_ENDPOINT_ID"
echo "  - Forwarding Rules: ${#RULE_IDS[@]} 개"
echo "  - VPC에 연결된 Rules: ${#RULE_IDS[@]} 개"
echo ""
echo "다음 단계:"
echo "  1. 네트워크 연결 완료 (VPC Peering 또는 Transit Gateway)"
echo "  2. DNS Resolution 테스트: ./test-dns.sh"
echo ""
echo "설정 정보를 spoke-config.txt에 저장합니다..."

cat > spoke-config.txt <<EOF
# Spoke VPC 설정 정보
SPOKE_VPC_ID=$SPOKE_VPC_ID
SPOKE_SUBNET_A=$SPOKE_SUBNET_A
SPOKE_SUBNET_C=$SPOKE_SUBNET_C
SPOKE_VPC_CIDR=$SPOKE_VPC_CIDR
SPOKE_RESOLVER_SG_ID=$SPOKE_RESOLVER_SG_ID
OUTBOUND_ENDPOINT_ID=$OUTBOUND_ENDPOINT_ID
HUB_VPC_CIDR=$HUB_VPC_CIDR
HUB_INBOUND_IP_1=$INBOUND_IP_1
HUB_INBOUND_IP_2=$INBOUND_IP_2
HUB_ACCOUNT_ID=$HUB_ACCOUNT_ID
REGION=$REGION
EOF

echo "  ✓ spoke-config.txt 저장 완료"
echo ""
