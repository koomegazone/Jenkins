#!/bin/bash

# Hub VPC 설정 스크립트
# Profile: koo (Hub Account)
#
# 사용법:
#   ./setup-hub.sh [HUB_VPC_ID] [HUB_SUBNET_A] [HUB_SUBNET_C] [HUB_VPC_CIDR] [SPOKE_VPC_CIDR] [SPOKE_ACCOUNT_ID] [HUB_ROUTE_TABLES]
#
# 예시:
#   ./setup-hub.sh vpc-xxx subnet-xxx subnet-yyy 192.168.0.0/16 10.0.0.0/24 876243134363 "rtb-xxx rtb-yyy"

set -e

echo "=========================================="
echo "Hub VPC Centralized Endpoint 설정 시작"
echo "Profile: koo (Hub Account)"
echo "=========================================="

# 변수 설정
export AWS_PROFILE=koo
REGION="ap-northeast-2"

# 명령줄 인자로 받기
if [ $# -eq 7 ]; then
    HUB_VPC_ID=$1
    HUB_SUBNET_A=$2
    HUB_SUBNET_C=$3
    HUB_VPC_CIDR=$4
    SPOKE_VPC_CIDR=$5
    SPOKE_ACCOUNT_ID=$6
    HUB_ROUTE_TABLES=$7
    echo ""
    echo "명령줄 인자 사용:"
elif [ $# -eq 6 ]; then
    HUB_VPC_ID=$1
    HUB_SUBNET_A=$2
    HUB_SUBNET_C=$3
    HUB_VPC_CIDR=$4
    SPOKE_VPC_CIDR=$5
    SPOKE_ACCOUNT_ID=$6
    HUB_ROUTE_TABLES=""
    echo ""
    echo "명령줄 인자 사용 (Route Table은 나중에 입력):"
else
    echo ""
    echo "대화형 모드 (명령줄 인자 미제공)"
    echo ""
    # Hub VPC 정보 입력
    read -p "Hub VPC ID를 입력하세요 (예: vpc-xxx): " HUB_VPC_ID
    read -p "Hub Private Subnet A ID를 입력하세요: " HUB_SUBNET_A
    read -p "Hub Private Subnet C ID를 입력하세요: " HUB_SUBNET_C
    read -p "Hub VPC CIDR를 입력하세요 (예: 10.1.0.0/16): " HUB_VPC_CIDR

    # Spoke VPC 정보 입력 (Security Group 설정용)
    read -p "Spoke VPC CIDR를 입력하세요 (예: 10.2.0.0/16): " SPOKE_VPC_CIDR
    read -p "Spoke Account ID를 입력하세요: " SPOKE_ACCOUNT_ID
    HUB_ROUTE_TABLES=""
fi

echo ""
echo "입력된 정보:"
echo "  Hub VPC ID: $HUB_VPC_ID"
echo "  Hub Subnet A: $HUB_SUBNET_A"
echo "  Hub Subnet C: $HUB_SUBNET_C"
echo "  Hub VPC CIDR: $HUB_VPC_CIDR"
echo "  Spoke VPC CIDR: $SPOKE_VPC_CIDR"
echo "  Spoke Account ID: $SPOKE_ACCOUNT_ID"
echo ""
read -p "계속하시겠습니까? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "취소되었습니다."
    exit 0
fi

# 1. VPC Endpoint용 Security Group 생성
echo ""
echo "[1/6] VPC Endpoint용 Security Group 확인 중..."

# 기존 Security Group 확인
HUB_ENDPOINT_SG_ID=$(aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values=$HUB_VPC_ID Name=group-name,Values=hub-vpc-endpoint-sg \
    --region $REGION \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$HUB_ENDPOINT_SG_ID" ] && [ "$HUB_ENDPOINT_SG_ID" != "None" ]; then
    echo "  ✓ 기존 Security Group 사용: $HUB_ENDPOINT_SG_ID"
else
    echo "  - 새 Security Group 생성 중..."
    HUB_ENDPOINT_SG_ID=$(aws ec2 create-security-group \
        --group-name "hub-vpc-endpoint-sg" \
        --description "Security group for Hub VPC Endpoints" \
        --vpc-id $HUB_VPC_ID \
        --region $REGION \
        --query 'GroupId' \
        --output text)
    
    echo "  ✓ Security Group 생성 완료: $HUB_ENDPOINT_SG_ID"
    
    # Security Group 규칙 추가
    echo "  - HTTPS (443) 허용 추가 중..."
    aws ec2 authorize-security-group-ingress \
        --group-id $HUB_ENDPOINT_SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr $HUB_VPC_CIDR \
        --region $REGION > /dev/null 2>&1 || echo "    (규칙이 이미 존재함)"

    aws ec2 authorize-security-group-ingress \
        --group-id $HUB_ENDPOINT_SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr $SPOKE_VPC_CIDR \
        --region $REGION > /dev/null 2>&1 || echo "    (규칙이 이미 존재함)"

    echo "  - NFS (2049) 허용 추가 중..."
    aws ec2 authorize-security-group-ingress \
        --group-id $HUB_ENDPOINT_SG_ID \
        --protocol tcp \
        --port 2049 \
        --cidr $HUB_VPC_CIDR \
        --region $REGION > /dev/null 2>&1 || echo "    (규칙이 이미 존재함)"

    aws ec2 authorize-security-group-ingress \
        --group-id $HUB_ENDPOINT_SG_ID \
        --protocol tcp \
        --port 2049 \
        --cidr $SPOKE_VPC_CIDR \
        --region $REGION > /dev/null 2>&1 || echo "    (규칙이 이미 존재함)"

    echo "  - DNS (53) 허용 추가 중..."
    aws ec2 authorize-security-group-ingress \
        --group-id $HUB_ENDPOINT_SG_ID \
        --protocol tcp \
        --port 53 \
        --cidr $SPOKE_VPC_CIDR \
        --region $REGION > /dev/null 2>&1 || echo "    (규칙이 이미 존재함)"

    aws ec2 authorize-security-group-ingress \
        --group-id $HUB_ENDPOINT_SG_ID \
        --protocol udp \
        --port 53 \
        --cidr $SPOKE_VPC_CIDR \
        --region $REGION > /dev/null 2>&1 || echo "    (규칙이 이미 존재함)"

    echo "  ✓ Security Group 규칙 추가 완료"
fi

# 2. VPC Interface Endpoints 생성
echo ""
echo "[2/6] VPC Interface Endpoints 확인 및 생성 중..."

INTERFACE_ENDPOINTS=(
    "ec2"
    "eks"
    "eks-auth"
    "elasticfilesystem"
    "sts"
    "autoscaling"
    "elasticloadbalancing"
    "ecr.api"
    "ecr.dkr"
)

for endpoint in "${INTERFACE_ENDPOINTS[@]}"; do
    SERVICE_NAME="com.amazonaws.$REGION.$endpoint"
    
    # 기존 Endpoint 확인
    EXISTING_ENDPOINT=$(aws ec2 describe-vpc-endpoints \
        --filters Name=vpc-id,Values=$HUB_VPC_ID Name=service-name,Values=$SERVICE_NAME \
        --region $REGION \
        --query 'VpcEndpoints[0].VpcEndpointId' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$EXISTING_ENDPOINT" ] && [ "$EXISTING_ENDPOINT" != "None" ]; then
        echo "  ✓ $endpoint Endpoint 이미 존재: $EXISTING_ENDPOINT"
    else
        echo "  - $endpoint Endpoint 생성 중..."
        aws ec2 create-vpc-endpoint \
            --vpc-id $HUB_VPC_ID \
            --service-name $SERVICE_NAME \
            --vpc-endpoint-type Interface \
            --subnet-ids $HUB_SUBNET_A $HUB_SUBNET_C \
            --security-group-ids $HUB_ENDPOINT_SG_ID \
            --private-dns-enabled \
            --region $REGION \
            --no-cli-pager > /dev/null
        echo "    ✓ 완료"
        sleep 2
    fi
done

echo "  ✓ 모든 Interface Endpoints 확인 완료"

# 3. S3 Gateway Endpoint 생성
echo ""
echo "[3/6] S3 Gateway Endpoint 확인 및 생성 중..."

if [ -z "$HUB_ROUTE_TABLES" ]; then
    read -p "Hub VPC의 Private Route Table ID를 입력하세요 (공백으로 구분): " HUB_ROUTE_TABLES
fi

# 기존 S3 Gateway Endpoint 확인
EXISTING_S3_ENDPOINT=$(aws ec2 describe-vpc-endpoints \
    --filters Name=vpc-id,Values=$HUB_VPC_ID Name=service-name,Values=com.amazonaws.$REGION.s3 Name=vpc-endpoint-type,Values=Gateway \
    --region $REGION \
    --query 'VpcEndpoints[0].VpcEndpointId' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$EXISTING_S3_ENDPOINT" ] && [ "$EXISTING_S3_ENDPOINT" != "None" ]; then
    echo "  ✓ S3 Gateway Endpoint 이미 존재: $EXISTING_S3_ENDPOINT"
else
    echo "  - S3 Gateway Endpoint 생성 중..."
    aws ec2 create-vpc-endpoint \
        --vpc-id $HUB_VPC_ID \
        --service-name com.amazonaws.$REGION.s3 \
        --vpc-endpoint-type Gateway \
        --route-table-ids $HUB_ROUTE_TABLES \
        --region $REGION \
        --no-cli-pager > /dev/null
    
    echo "  ✓ S3 Gateway Endpoint 생성 완료"
fi

# 4. Route53 Resolver Inbound Endpoint 생성
echo ""
echo "[4/6] Route53 Resolver Inbound Endpoint 확인 중..."

# 기존 Inbound Endpoint 확인
EXISTING_INBOUND=$(aws route53resolver list-resolver-endpoints \
    --filters Name=Direction,Values=INBOUND \
    --region $REGION \
    --query 'ResolverEndpoints[0].Id' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$EXISTING_INBOUND" ] && [ "$EXISTING_INBOUND" != "None" ]; then
    echo "  ✓ 기존 Inbound Endpoint 사용: $EXISTING_INBOUND"
    INBOUND_ENDPOINT_ID=$EXISTING_INBOUND
else
    echo "  - 새 Inbound Endpoint 생성 중..."
    read -p "Inbound Endpoint IP for Subnet A (예: 10.1.1.100, 비워두면 자동): " INBOUND_IP_A
    read -p "Inbound Endpoint IP for Subnet C (예: 10.1.3.100, 비워두면 자동): " INBOUND_IP_C

    if [ -z "$INBOUND_IP_A" ]; then
        IP_CONFIG_A="SubnetId=$HUB_SUBNET_A"
    else
        IP_CONFIG_A="SubnetId=$HUB_SUBNET_A,Ip=$INBOUND_IP_A"
    fi

    if [ -z "$INBOUND_IP_C" ]; then
        IP_CONFIG_C="SubnetId=$HUB_SUBNET_C"
    else
        IP_CONFIG_C="SubnetId=$HUB_SUBNET_C,Ip=$INBOUND_IP_C"
    fi

    INBOUND_ENDPOINT_ID=$(aws route53resolver create-resolver-endpoint \
        --name "hub-inbound-endpoint" \
        --creator-request-id "hub-inbound-$(date +%s)" \
        --security-group-ids $HUB_ENDPOINT_SG_ID \
        --direction INBOUND \
        --ip-addresses $IP_CONFIG_A $IP_CONFIG_C \
        --region $REGION \
        --query 'ResolverEndpoint.Id' \
        --output text 2>&1)
    
    if [[ $INBOUND_ENDPOINT_ID == *"LimitExceededException"* ]]; then
        echo ""
        echo "  ⚠️  오류: Resolver Endpoint 할당량 초과"
        echo "  계정당 리전별 최대 4개까지만 생성 가능합니다."
        echo ""
        echo "  해결 방법:"
        echo "  1. 기존 Resolver Endpoints 확인:"
        echo "     aws route53resolver list-resolver-endpoints --region $REGION --profile koo"
        echo ""
        echo "  2. 사용하지 않는 Endpoint 삭제:"
        echo "     aws route53resolver delete-resolver-endpoint --resolver-endpoint-id <ID> --region $REGION --profile koo"
        echo ""
        echo "  3. 또는 AWS Support에 할당량 증가 요청"
        echo ""
        exit 1
    fi

    echo "  ✓ Inbound Endpoint 생성 완료: $INBOUND_ENDPOINT_ID"
    echo "  - 상태가 OPERATIONAL이 될 때까지 대기 중..."

    while true; do
        STATUS=$(aws route53resolver get-resolver-endpoint \
            --resolver-endpoint-id $INBOUND_ENDPOINT_ID \
            --region $REGION \
            --query 'ResolverEndpoint.Status' \
            --output text)
        
        if [ "$STATUS" == "OPERATIONAL" ]; then
            echo "  ✓ Inbound Endpoint가 활성화되었습니다"
            break
        fi
        echo "    현재 상태: $STATUS (대기 중...)"
        sleep 10
    done
fi

# Inbound Endpoint IP 주소 확인
echo ""
echo "  Inbound Endpoint IP 주소:"
INBOUND_IPS=$(aws route53resolver list-resolver-endpoint-ip-addresses \
    --resolver-endpoint-id $INBOUND_ENDPOINT_ID \
    --region $REGION \
    --query 'IpAddresses[*].Ip' \
    --output text)

echo "  $INBOUND_IPS"
echo ""
echo "  ⚠️  이 IP 주소들을 기록해두세요! Spoke VPC 설정에 필요합니다."
echo ""

# 배열로 변환 (탭과 공백 모두 처리)
INBOUND_IPS=$(echo "$INBOUND_IPS" | tr '\t' ' ' | tr -s ' ')
IFS=' ' read -r -a INBOUND_IP_ARRAY <<< "$INBOUND_IPS"

# IP 배열 확인
echo "  디버그: IP 배열 개수 = ${#INBOUND_IP_ARRAY[@]}"
echo "  디버그: IP[0] = ${INBOUND_IP_ARRAY[0]}"
echo "  디버그: IP[1] = ${INBOUND_IP_ARRAY[1]}"

if [ ${#INBOUND_IP_ARRAY[@]} -lt 2 ]; then
    echo ""
    echo "  ⚠️  오류: Inbound Endpoint IP가 2개 미만입니다."
    echo "  현재 IP: $INBOUND_IPS"
    echo ""
    exit 1
fi

# 5. Route53 Resolver Outbound Endpoint 생성
echo ""
echo "[5/8] Route53 Resolver Outbound Endpoint 확인 중..."

# 기존 Outbound Endpoint 확인
EXISTING_OUTBOUND=$(aws route53resolver list-resolver-endpoints \
    --filters Name=Direction,Values=OUTBOUND \
    --region $REGION \
    --query 'ResolverEndpoints[0].Id' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$EXISTING_OUTBOUND" ] && [ "$EXISTING_OUTBOUND" != "None" ]; then
    echo "  ✓ 기존 Outbound Endpoint 사용: $EXISTING_OUTBOUND"
    OUTBOUND_ENDPOINT_ID=$EXISTING_OUTBOUND
else
    echo "  - 새 Outbound Endpoint 생성 중..."
    
    OUTBOUND_ENDPOINT_ID=$(aws route53resolver create-resolver-endpoint \
        --name "hub-outbound-endpoint" \
        --creator-request-id "hub-outbound-$(date +%s)" \
        --security-group-ids $HUB_ENDPOINT_SG_ID \
        --direction OUTBOUND \
        --ip-addresses SubnetId=$HUB_SUBNET_A SubnetId=$HUB_SUBNET_C \
        --region $REGION \
        --query 'ResolverEndpoint.Id' \
        --output text 2>&1)
    
    if [[ $OUTBOUND_ENDPOINT_ID == *"LimitExceededException"* ]]; then
        echo ""
        echo "  ⚠️  오류: Resolver Endpoint 할당량 초과"
        echo "  기존 Outbound Endpoint를 삭제하거나 할당량 증가를 요청하세요."
        exit 1
    fi

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
fi

# 6. Forwarding Rules 생성
echo ""
echo "[6/8] Forwarding Rules 생성 중..."

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
    echo "  - $domain 규칙 확인 중..."
    
    # 기존 Rule 확인
    EXISTING_RULE=$(aws route53resolver list-resolver-rules \
        --region $REGION \
        --query "ResolverRules[?DomainName=='$domain' && RuleType=='FORWARD'].Id" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$EXISTING_RULE" ] && [ "$EXISTING_RULE" != "None" ]; then
        echo "    ✓ 기존 Rule 사용: $EXISTING_RULE"
        RULE_IDS+=($EXISTING_RULE)
    else
        # Rule 이름 생성 (점을 하이픈으로 변경)
        RULE_NAME=$(echo "forward-${domain}" | sed 's/\./-/g')
        
        echo "    - 새 Rule 생성 중..."
        RULE_ID=$(aws route53resolver create-resolver-rule \
            --name "$RULE_NAME" \
            --creator-request-id "rule-${domain}-$(date +%s)" \
            --rule-type FORWARD \
            --domain-name "$domain" \
            --resolver-endpoint-id $OUTBOUND_ENDPOINT_ID \
            --target-ips "Ip=${INBOUND_IP_ARRAY[0]},Port=53" "Ip=${INBOUND_IP_ARRAY[1]},Port=53" \
            --region $REGION \
            --query 'ResolverRule.Id' \
            --output text)
        
        RULE_IDS+=($RULE_ID)
        echo "    ✓ 완료: $RULE_ID"
        sleep 1
    fi
done

echo "  ✓ 모든 Forwarding Rules 확인 완료"

# 7. Forwarding Rules는 Spoke VPC에서만 사용
echo ""
echo "[7/8] Forwarding Rules 안내"
echo "  ⚠️  Hub VPC는 VPC Endpoints를 직접 사용합니다."
echo "  Forwarding Rules는 Spoke VPC에서만 연결하세요."
echo ""

# 8. RAM Resource Share 생성
echo ""
echo "[8/8] RAM Resource Share 생성 중..."

# 기존 Resource Share 확인
EXISTING_SHARE=$(aws ram get-resource-shares \
    --resource-owner SELF \
    --name resolver-rules-share \
    --region $REGION \
    --query 'resourceShares[0].resourceShareArn' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$EXISTING_SHARE" ] && [ "$EXISTING_SHARE" != "None" ]; then
    echo "  ✓ 기존 RAM Share 사용: $EXISTING_SHARE"
else
    # Rule ARN 목록 생성
    RULE_ARNS=""
    for rule_id in "${RULE_IDS[@]}"; do
        RULE_ARN=$(aws route53resolver get-resolver-rule \
            --resolver-rule-id $rule_id \
            --region $REGION \
            --query 'ResolverRule.Arn' \
            --output text)
        RULE_ARNS="$RULE_ARNS $RULE_ARN"
    done

    aws ram create-resource-share \
        --name "resolver-rules-share" \
        --resource-arns $RULE_ARNS \
        --principals "arn:aws:iam::${SPOKE_ACCOUNT_ID}:root" \
        --region $REGION \
        --no-cli-pager > /dev/null

    echo "  ✓ RAM Resource Share 생성 완료"
fi

# 6. 설정 정보 저장
echo ""
echo "[6/6] 설정 정보 저장 중..."

# 완료 메시지
echo ""
echo "=========================================="
echo "Hub VPC 설정 완료!"
echo "=========================================="
echo ""
echo "생성된 리소스:"
echo "  - VPC Endpoint Security Group: $HUB_ENDPOINT_SG_ID"
echo "  - Interface Endpoints: ${#INTERFACE_ENDPOINTS[@]}개"
echo "  - S3 Gateway Endpoint: 1개"
echo "  - Resolver Inbound Endpoint: $INBOUND_ENDPOINT_ID"
echo "  - Resolver Outbound Endpoint: $OUTBOUND_ENDPOINT_ID"
echo "  - Inbound Endpoint IPs: $INBOUND_IPS"
echo "  - Forwarding Rules: ${#RULE_IDS[@]}개"
echo "  - RAM Resource Share: resolver-rules-share"
echo ""
echo "다음 단계:"
echo "  1. Spoke VPC 설정 스크립트 실행: ./setup-spoke.sh"
echo "  2. Spoke에서는 RAM 공유된 Rules를 수락하고 VPC에 연결합니다"
echo ""
echo "설정 정보를 hub-config.txt에 저장합니다..."

cat > hub-config.txt <<EOF
# Hub VPC 설정 정보
HUB_VPC_ID=$HUB_VPC_ID
HUB_SUBNET_A=$HUB_SUBNET_A
HUB_SUBNET_C=$HUB_SUBNET_C
HUB_VPC_CIDR=$HUB_VPC_CIDR
HUB_ENDPOINT_SG_ID=$HUB_ENDPOINT_SG_ID
INBOUND_ENDPOINT_ID=$INBOUND_ENDPOINT_ID
OUTBOUND_ENDPOINT_ID=$OUTBOUND_ENDPOINT_ID
INBOUND_IPS=$INBOUND_IPS
SPOKE_ACCOUNT_ID=$SPOKE_ACCOUNT_ID
REGION=$REGION
EOF

echo "  ✓ hub-config.txt 저장 완료"
echo ""
