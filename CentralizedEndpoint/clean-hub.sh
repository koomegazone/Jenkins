#!/bin/bash

# Hub VPC 리소스 삭제 스크립트
# Profile: koo (Hub Account)

set -e

echo "=========================================="
echo "Hub VPC Centralized Endpoint 리소스 삭제"
echo "Profile: koo (Hub Account)"
echo "=========================================="

# 변수 설정
PROFILE="koo"
export AWS_PROFILE=$PROFILE
REGION="ap-northeast-2"

# hub-config.txt 파일이 있으면 자동으로 로드
if [ -f "hub-config.txt" ]; then
    echo ""
    echo "hub-config.txt 파일을 찾았습니다."
    read -p "저장된 설정을 사용하시겠습니까? (y/n): " USE_CONFIG
    
    if [ "$USE_CONFIG" == "y" ]; then
        source hub-config.txt
        echo "  ✓ 설정 로드 완료"
    fi
fi

# 설정이 없으면 수동 입력
if [ -z "$HUB_VPC_ID" ]; then
    echo ""
    read -p "Hub VPC ID를 입력하세요: " HUB_VPC_ID
fi

if [ -z "$HUB_ENDPOINT_SG_ID" ]; then
    read -p "Hub Endpoint Security Group ID를 입력하세요 (선택, 비워두면 자동 검색): " HUB_ENDPOINT_SG_ID
fi

if [ -z "$INBOUND_ENDPOINT_ID" ]; then
    read -p "Inbound Endpoint ID를 입력하세요 (선택, 비워두면 자동 검색): " INBOUND_ENDPOINT_ID
fi

echo ""
echo "삭제할 리소스:"
echo "  Hub VPC ID: $HUB_VPC_ID"
echo "  Region: $REGION"
echo ""
echo "⚠️  경고: 이 작업은 되돌릴 수 없습니다!"
echo ""
read -p "정말로 모든 리소스를 삭제하시겠습니까? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "취소되었습니다."
    exit 0
fi

# 삭제 시작
echo ""
echo "리소스 삭제를 시작합니다..."
echo ""

# 1. RAM Resource Share 삭제
echo "[1/6] RAM Resource Share 삭제 중..."

RAM_SHARE_ARNS=$(aws ram --profile $PROFILE get-resource-shares \
    --resource-owner SELF \
    --name resolver-rules-share \
    --region $REGION \
    --profile $PROFILE \
    --query 'resourceShares[*].resourceShareArn' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$RAM_SHARE_ARNS" ]; then
    for arn in $RAM_SHARE_ARNS; do
        echo "  - RAM Share 삭제 중: $arn"
        aws ram --profile $PROFILE delete-resource-share \
            --resource-share-arn $arn \
            --region $REGION \
            --no-cli-pager > /dev/null 2>&1 || echo "    ⚠️  삭제 실패 (이미 삭제되었을 수 있음)"
    done
    echo "  ✓ RAM Resource Share 삭제 완료"
else
    echo "  - RAM Resource Share를 찾을 수 없습니다 (건너뜀)"
fi

# 2. Forwarding Rules 삭제
echo ""
echo "[2/6] Forwarding Rules 삭제 중..."

RULE_IDS=$(aws route53resolver --profile $PROFILE list-resolver-rules \
    --region $REGION \
    --query 'ResolverRules[?RuleType==`FORWARD` && OwnerId==`'$(aws sts --profile $PROFILE get-caller-identity --query Account --output text)'`].Id' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$RULE_IDS" ]; then
    for rule_id in $RULE_IDS; do
        RULE_NAME=$(aws route53resolver --profile $PROFILE get-resolver-rule \
            --resolver-rule-id $rule_id \
            --region $REGION \
            --query 'ResolverRule.Name' \
            --output text 2>/dev/null || echo "unknown")
        
        echo "  - Forwarding Rule 삭제 중: $RULE_NAME ($rule_id)"
        
        # Rule Association 먼저 삭제
        ASSOCIATIONS=$(aws route53resolver --profile $PROFILE list-resolver-rule-associations \
            --filters Name=ResolverRuleId,Values=$rule_id \
            --region $REGION \
            --query 'ResolverRuleAssociations[*].Id' \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$ASSOCIATIONS" ]; then
            for assoc_id in $ASSOCIATIONS; do
                echo "    - Association 삭제 중: $assoc_id"
                aws route53resolver --profile $PROFILE disassociate-resolver-rule \
                    --resolver-rule-association-id $assoc_id \
                    --region $REGION \
                    --no-cli-pager > /dev/null 2>&1 || echo "      ⚠️  삭제 실패"
                sleep 2
            done
        fi
        
        # Rule 삭제
        aws route53resolver --profile $PROFILE delete-resolver-rule \
            --resolver-rule-id $rule_id \
            --region $REGION \
            --no-cli-pager > /dev/null 2>&1 || echo "    ⚠️  삭제 실패"
        
        sleep 2
    done
    echo "  ✓ Forwarding Rules 삭제 완료"
else
    echo "  - Forwarding Rules를 찾을 수 없습니다 (건너뜀)"
fi

# 3. Resolver Inbound Endpoint 삭제
echo ""
echo "[3/6] Resolver Inbound Endpoint 삭제 중..."

if [ -z "$INBOUND_ENDPOINT_ID" ]; then
    INBOUND_ENDPOINT_ID=$(aws route53resolver --profile $PROFILE list-resolver-endpoints \
        --filters Name=Direction,Values=INBOUND \
        --region $REGION \
        --query 'ResolverEndpoints[0].Id' \
        --output text 2>/dev/null || echo "")
fi

if [ ! -z "$INBOUND_ENDPOINT_ID" ] && [ "$INBOUND_ENDPOINT_ID" != "None" ]; then
    echo "  - Inbound Endpoint 삭제 중: $INBOUND_ENDPOINT_ID"
    
    aws route53resolver --profile $PROFILE delete-resolver-endpoint \
        --resolver-endpoint-id $INBOUND_ENDPOINT_ID \
        --region $REGION \
        --no-cli-pager > /dev/null 2>&1 || echo "    ⚠️  삭제 실패"
    
    echo "  - 삭제 완료 대기 중..."
    sleep 10
    
    # 삭제 완료 대기
    for i in {1..30}; do
        STATUS=$(aws route53resolver --profile $PROFILE get-resolver-endpoint \
            --resolver-endpoint-id $INBOUND_ENDPOINT_ID \
            --region $REGION \
            --query 'ResolverEndpoint.Status' \
            --output text 2>/dev/null || echo "DELETED")
        
        if [ "$STATUS" == "DELETED" ] || [ "$STATUS" == "None" ]; then
            echo "  ✓ Inbound Endpoint 삭제 완료"
            break
        fi
        
        echo "    현재 상태: $STATUS (대기 중... $i/30)"
        sleep 10
    done
else
    echo "  - Inbound Endpoint를 찾을 수 없습니다 (건너뜀)"
fi

# 4. VPC Endpoints 삭제
echo ""
echo "[4/6] VPC Endpoints 삭제 중..."

VPC_ENDPOINT_IDS=$(aws ec2 --profile $PROFILE describe-vpc-endpoints \
    --filters Name=vpc-id,Values=$HUB_VPC_ID \
    --region $REGION \
    --query 'VpcEndpoints[*].VpcEndpointId' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$VPC_ENDPOINT_IDS" ]; then
    ENDPOINT_COUNT=$(echo $VPC_ENDPOINT_IDS | wc -w)
    echo "  - $ENDPOINT_COUNT 개의 VPC Endpoints 발견"
    
    # 각 Endpoint 정보 출력
    for endpoint_id in $VPC_ENDPOINT_IDS; do
        SERVICE_NAME=$(aws ec2 --profile $PROFILE describe-vpc-endpoints \
            --vpc-endpoint-ids $endpoint_id \
            --region $REGION \
            --query 'VpcEndpoints[0].ServiceName' \
            --output text 2>/dev/null || echo "unknown")
        
        echo "    - $endpoint_id ($SERVICE_NAME)"
    done
    
    echo ""
    echo "  VPC Endpoints 삭제 시작..."
    
    # 개별 삭제 (에러 확인 가능)
    for endpoint_id in $VPC_ENDPOINT_IDS; do
        echo "    삭제 중: $endpoint_id"
        aws ec2 --profile $PROFILE delete-vpc-endpoints \
            --vpc-endpoint-ids $endpoint_id \
            --region $REGION 2>&1 | grep -v "^$" || true
        sleep 2
    done
    
    echo "  ✓ VPC Endpoints 삭제 명령 완료"
    echo "  - 삭제 완료 대기 중 (30초)..."
    sleep 30
else
    echo "  - VPC Endpoints를 찾을 수 없습니다 (건너뜀)"
fi

# 5. Security Group 삭제
echo ""
echo "[5/6] Security Group 삭제 중..."

if [ -z "$HUB_ENDPOINT_SG_ID" ]; then
    HUB_ENDPOINT_SG_ID=$(aws ec2 --profile $PROFILE describe-security-groups \
        --filters Name=vpc-id,Values=$HUB_VPC_ID Name=group-name,Values=hub-vpc-endpoint-sg \
        --region $REGION \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
fi

if [ ! -z "$HUB_ENDPOINT_SG_ID" ] && [ "$HUB_ENDPOINT_SG_ID" != "None" ]; then
    echo "  - Security Group 삭제 중: $HUB_ENDPOINT_SG_ID"
    echo "  - ENI 삭제 대기 중 (최대 60초)..."
    sleep 60
    
    # Security Group 삭제 시도 (최대 5번)
    for i in {1..5}; do
        aws ec2 --profile $PROFILE delete-security-group \
            --group-id $HUB_ENDPOINT_SG_ID \
            --region $REGION 2>/dev/null && {
            echo "  ✓ Security Group 삭제 완료"
            break
        } || {
            if [ $i -eq 5 ]; then
                echo "  ⚠️  Security Group 삭제 실패 (ENI가 아직 사용 중일 수 있음)"
                echo "     나중에 수동으로 삭제하세요: $HUB_ENDPOINT_SG_ID"
            else
                echo "    재시도 중... ($i/5)"
                sleep 15
            fi
        }
    done
else
    echo "  - Security Group을 찾을 수 없습니다 (건너뜀)"
fi

# 6. 설정 파일 삭제
echo ""
echo "[6/6] 설정 파일 정리 중..."

if [ -f "hub-config.txt" ]; then
    read -p "hub-config.txt 파일을 삭제하시겠습니까? (y/n): " DELETE_CONFIG
    if [ "$DELETE_CONFIG" == "y" ]; then
        rm -f hub-config.txt
        echo "  ✓ hub-config.txt 삭제 완료"
    else
        echo "  - hub-config.txt 유지"
    fi
fi

# 완료 메시지
echo ""
echo "=========================================="
echo "Hub VPC 리소스 삭제 완료!"
echo "=========================================="
echo ""
echo "삭제된 리소스:"
echo "  - RAM Resource Share"
echo "  - Forwarding Rules"
echo "  - Resolver Inbound Endpoint"
echo "  - VPC Endpoints"
echo "  - Security Group (시도됨)"
echo ""
echo "⚠️  주의사항:"
echo "  1. Security Group이 삭제되지 않았다면 ENI가 완전히 삭제된 후 수동 삭제 필요"
echo "  2. VPC Peering Connection은 수동으로 삭제해야 합니다"
echo "  3. Route Table의 경로는 수동으로 삭제해야 합니다"
echo ""

# 남은 리소스 확인
echo "남은 리소스 확인 중..."
echo ""

# VPC Endpoints 확인
REMAINING_ENDPOINTS=$(aws ec2 --profile $PROFILE describe-vpc-endpoints \
    --filters Name=vpc-id,Values=$HUB_VPC_ID \
    --region $REGION \
    --query 'VpcEndpoints[*].VpcEndpointId' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$REMAINING_ENDPOINTS" ]; then
    echo "⚠️  남은 VPC Endpoints:"
    echo "  $REMAINING_ENDPOINTS"
else
    echo "✓ VPC Endpoints: 모두 삭제됨"
fi

# Resolver Endpoints 확인
REMAINING_RESOLVERS=$(aws route53resolver --profile $PROFILE list-resolver-endpoints \
    --region $REGION \
    --query 'ResolverEndpoints[?Status!=`DELETED`].Id' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$REMAINING_RESOLVERS" ]; then
    echo "⚠️  남은 Resolver Endpoints:"
    echo "  $REMAINING_RESOLVERS"
else
    echo "✓ Resolver Endpoints: 모두 삭제됨"
fi

# Security Groups 확인
if [ ! -z "$HUB_ENDPOINT_SG_ID" ]; then
    SG_EXISTS=$(aws ec2 --profile $PROFILE describe-security-groups \
        --group-ids $HUB_ENDPOINT_SG_ID \
        --region $REGION \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$SG_EXISTS" ] && [ "$SG_EXISTS" != "None" ]; then
        echo "⚠️  남은 Security Group:"
        echo "  $HUB_ENDPOINT_SG_ID"
        echo ""
        echo "  수동 삭제 명령어:"
        echo "  aws ec2 --profile $PROFILE delete-security-group --group-id $HUB_ENDPOINT_SG_ID --region $REGION --profile koo"
    else
        echo "✓ Security Group: 삭제됨"
    fi
fi

echo ""
echo "정리 작업이 완료되었습니다."
echo ""
