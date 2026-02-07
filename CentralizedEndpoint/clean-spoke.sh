#!/bin/bash

# Spoke VPC 리소스 삭제 스크립트
# Profile: default (Spoke Account)

set -e

echo "=========================================="
echo "Spoke VPC Centralized Endpoint 리소스 삭제"
echo "Profile: default (Spoke Account)"
echo "=========================================="

# 변수 설정
export AWS_PROFILE=default
REGION="ap-northeast-2"

# spoke-config.txt 파일이 있으면 자동으로 로드
if [ -f "spoke-config.txt" ]; then
    echo ""
    echo "spoke-config.txt 파일을 찾았습니다."
    read -p "저장된 설정을 사용하시겠습니까? (y/n): " USE_CONFIG
    
    if [ "$USE_CONFIG" == "y" ]; then
        source spoke-config.txt
        echo "  ✓ 설정 로드 완료"
    fi
fi

# 설정이 없으면 수동 입력
if [ -z "$SPOKE_VPC_ID" ]; then
    echo ""
    read -p "Spoke VPC ID를 입력하세요: " SPOKE_VPC_ID
fi

if [ -z "$OUTBOUND_ENDPOINT_ID" ]; then
    read -p "Outbound Endpoint ID를 입력하세요 (선택, 비워두면 자동 검색): " OUTBOUND_ENDPOINT_ID
fi

if [ -z "$SPOKE_RESOLVER_SG_ID" ]; then
    read -p "Spoke Resolver Security Group ID를 입력하세요 (선택, 비워두면 자동 검색): " SPOKE_RESOLVER_SG_ID
fi

echo ""
echo "삭제할 리소스:"
echo "  Spoke VPC ID: $SPOKE_VPC_ID"
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

# 1. Forwarding Rules Association 해제
echo "[1/4] Forwarding Rules Association 해제 중..."

RULE_ASSOCIATIONS=$(aws route53resolver list-resolver-rule-associations \
    --filters Name=VPCId,Values=$SPOKE_VPC_ID \
    --region $REGION \
    --query 'ResolverRuleAssociations[*].[Id,ResolverRuleId]' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$RULE_ASSOCIATIONS" ]; then
    echo "$RULE_ASSOCIATIONS" | while read assoc_id rule_id; do
        if [ "$rule_id" != "rslvr-autodefined-rr-internet-resolver" ]; then
            echo "  - Association 해제 중: $assoc_id"
            aws route53resolver disassociate-resolver-rule \
                --resolver-rule-association-id $assoc_id \
                --region $REGION \
                --no-cli-pager > /dev/null 2>&1 || echo "    ⚠️  해제 실패"
            sleep 2
        fi
    done
    echo "  ✓ Forwarding Rules Association 해제 완료"
else
    echo "  - Forwarding Rules Association을 찾을 수 없습니다 (건너뜀)"
fi

# 2. Resolver Outbound Endpoint 삭제
echo ""
echo "[2/4] Resolver Outbound Endpoint 삭제 중..."

if [ -z "$OUTBOUND_ENDPOINT_ID" ]; then
    OUTBOUND_ENDPOINT_ID=$(aws route53resolver list-resolver-endpoints \
        --filters Name=Direction,Values=OUTBOUND \
        --region $REGION \
        --query 'ResolverEndpoints[0].Id' \
        --output text 2>/dev/null || echo "")
fi

if [ ! -z "$OUTBOUND_ENDPOINT_ID" ] && [ "$OUTBOUND_ENDPOINT_ID" != "None" ]; then
    echo "  - Outbound Endpoint 삭제 중: $OUTBOUND_ENDPOINT_ID"
    
    aws route53resolver delete-resolver-endpoint \
        --resolver-endpoint-id $OUTBOUND_ENDPOINT_ID \
        --region $REGION \
        --no-cli-pager > /dev/null 2>&1 || echo "    ⚠️  삭제 실패"
    
    echo "  - 삭제 완료 대기 중..."
    sleep 10
    
    # 삭제 완료 대기
    for i in {1..30}; do
        STATUS=$(aws route53resolver get-resolver-endpoint \
            --resolver-endpoint-id $OUTBOUND_ENDPOINT_ID \
            --region $REGION \
            --query 'ResolverEndpoint.Status' \
            --output text 2>/dev/null || echo "DELETED")
        
        if [ "$STATUS" == "DELETED" ] || [ "$STATUS" == "None" ]; then
            echo "  ✓ Outbound Endpoint 삭제 완료"
            break
        fi
        
        echo "    현재 상태: $STATUS (대기 중... $i/30)"
        sleep 10
    done
else
    echo "  - Outbound Endpoint를 찾을 수 없습니다 (건너뜀)"
fi

# 3. Security Group 삭제
echo ""
echo "[3/4] Security Group 삭제 중..."

if [ -z "$SPOKE_RESOLVER_SG_ID" ]; then
    SPOKE_RESOLVER_SG_ID=$(aws ec2 describe-security-groups \
        --filters Name=vpc-id,Values=$SPOKE_VPC_ID Name=group-name,Values=spoke-resolver-sg \
        --region $REGION \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
fi

if [ ! -z "$SPOKE_RESOLVER_SG_ID" ] && [ "$SPOKE_RESOLVER_SG_ID" != "None" ]; then
    echo "  - Security Group 삭제 중: $SPOKE_RESOLVER_SG_ID"
    echo "  - ENI 삭제 대기 중 (최대 60초)..."
    sleep 60
    
    # Security Group 삭제 시도 (최대 5번)
    for i in {1..5}; do
        aws ec2 delete-security-group \
            --group-id $SPOKE_RESOLVER_SG_ID \
            --region $REGION 2>/dev/null && {
            echo "  ✓ Security Group 삭제 완료"
            break
        } || {
            if [ $i -eq 5 ]; then
                echo "  ⚠️  Security Group 삭제 실패 (ENI가 아직 사용 중일 수 있음)"
                echo "     나중에 수동으로 삭제하세요: $SPOKE_RESOLVER_SG_ID"
            else
                echo "    재시도 중... ($i/5)"
                sleep 15
            fi
        }
    done
else
    echo "  - Security Group을 찾을 수 없습니다 (건너뜀)"
fi

# 4. 설정 파일 삭제
echo ""
echo "[4/4] 설정 파일 정리 중..."

if [ -f "spoke-config.txt" ]; then
    read -p "spoke-config.txt 파일을 삭제하시겠습니까? (y/n): " DELETE_CONFIG
    if [ "$DELETE_CONFIG" == "y" ]; then
        rm -f spoke-config.txt
        echo "  ✓ spoke-config.txt 삭제 완료"
    else
        echo "  - spoke-config.txt 유지"
    fi
fi

# 완료 메시지
echo ""
echo "=========================================="
echo "Spoke VPC 리소스 삭제 완료!"
echo "=========================================="
echo ""
echo "삭제된 리소스:"
echo "  - Forwarding Rules Associations"
echo "  - Resolver Outbound Endpoint"
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

# Resolver Endpoints 확인
REMAINING_RESOLVERS=$(aws route53resolver list-resolver-endpoints \
    --region $REGION \
    --query 'ResolverEndpoints[?Status!=`DELETED`].Id' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$REMAINING_RESOLVERS" ]; then
    echo "⚠️  남은 Resolver Endpoints:"
    echo "  $REMAINING_RESOLVERS"
else
    echo "✓ Resolver Endpoints: 모두 삭제됨"
fi

# Rule Associations 확인
REMAINING_ASSOCIATIONS=$(aws route53resolver list-resolver-rule-associations \
    --filters Name=VPCId,Values=$SPOKE_VPC_ID \
    --region $REGION \
    --query 'ResolverRuleAssociations[?ResolverRuleId!=`rslvr-autodefined-rr-internet-resolver`].Id' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$REMAINING_ASSOCIATIONS" ]; then
    echo "⚠️  남은 Rule Associations:"
    echo "  $REMAINING_ASSOCIATIONS"
else
    echo "✓ Rule Associations: 모두 해제됨"
fi

# Security Groups 확인
if [ ! -z "$SPOKE_RESOLVER_SG_ID" ]; then
    SG_EXISTS=$(aws ec2 describe-security-groups \
        --group-ids $SPOKE_RESOLVER_SG_ID \
        --region $REGION \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$SG_EXISTS" ] && [ "$SG_EXISTS" != "None" ]; then
        echo "⚠️  남은 Security Group:"
        echo "  $SPOKE_RESOLVER_SG_ID"
        echo ""
        echo "  수동 삭제 명령어:"
        echo "  aws ec2 delete-security-group --group-id $SPOKE_RESOLVER_SG_ID --region $REGION"
    else
        echo "✓ Security Group: 삭제됨"
    fi
fi

echo ""
echo "정리 작업이 완료되었습니다."
echo ""
