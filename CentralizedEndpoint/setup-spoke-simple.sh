#!/bin/bash

# Spoke VPC 간단 설정 스크립트 (RAM 공유 방식)
# Profile: default (Spoke Account)
#
# 사용법:
#   ./setup-spoke-simple.sh [SPOKE_VPC_ID] [HUB_ACCOUNT_ID]
#
# 예시:
#   ./setup-spoke-simple.sh vpc-xxx 064711168361

set -e

echo "=========================================="
echo "Spoke VPC 설정 (RAM 공유 방식)"
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
    read -p "Spoke VPC ID를 입력하세요: " SPOKE_VPC_ID
    read -p "Hub Account ID를 입력하세요: " HUB_ACCOUNT_ID
fi

echo ""
echo "입력된 정보:"
echo "  Spoke VPC ID: $SPOKE_VPC_ID"
echo "  Hub Account ID: $HUB_ACCOUNT_ID"
echo ""
read -p "계속하시겠습니까? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""
echo "설정을 시작합니다..."
echo ""

# 1. RAM 초대 수락
echo "[1/2] RAM Resource Share 초대 확인 중..."

INVITATIONS=$(aws ram get-resource-share-invitations \
    --region $REGION \
    --query 'resourceShareInvitations[?status==`PENDING`]' \
    --output json)

INVITATION_COUNT=$(echo $INVITATIONS | jq '. | length')

if [ "$INVITATION_COUNT" -eq "0" ]; then
    echo "  ⚠️  대기 중인 초대가 없습니다."
    echo "  Hub Account에서 RAM 공유를 먼저 완료하세요."
else
    echo "  ✓ $INVITATION_COUNT 개의 초대를 찾았습니다"
    
    INVITATION_ARN=$(echo $INVITATIONS | jq -r '.[0].resourceShareInvitationArn')
    
    echo "  - 초대 수락 중..."
    aws ram accept-resource-share-invitation \
        --resource-share-invitation-arn "$INVITATION_ARN" \
        --region $REGION \
        --no-cli-pager > /dev/null
    
    echo "  ✓ RAM 초대 수락 완료"
    sleep 5
fi

# 2. Forwarding Rules를 Spoke VPC에 연결
echo ""
echo "[2/2] Forwarding Rules를 Spoke VPC에 연결 중..."

SHARED_RULE_IDS=$(aws route53resolver list-resolver-rules \
    --region $REGION \
    --query 'ResolverRules[?ShareStatus==`SHARED_WITH_ME`].Id' \
    --output text)

if [ -z "$SHARED_RULE_IDS" ]; then
    echo "  ⚠️  공유된 Resolver Rules를 찾을 수 없습니다."
    echo "  Hub Account에서 RAM 공유를 완료하고 위 단계에서 초대를 수락했는지 확인하세요."
    exit 1
fi

RULE_COUNT=$(echo $SHARED_RULE_IDS | wc -w)
echo "  ✓ $RULE_COUNT 개의 공유된 Rules를 찾았습니다"

for rule_id in $SHARED_RULE_IDS; do
    RULE_NAME=$(aws route53resolver get-resolver-rule \
        --resolver-rule-id $rule_id \
        --region $REGION \
        --query 'ResolverRule.Name' \
        --output text)
    
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

# 완료 메시지
echo ""
echo "=========================================="
echo "Spoke VPC 설정 완료!"
echo "=========================================="
echo ""
echo "설정된 리소스:"
echo "  - 공유된 Forwarding Rules: $RULE_COUNT 개"
echo "  - VPC에 연결된 Rules: $RULE_COUNT 개"
echo ""
echo "다음 단계:"
echo "  1. VPC Peering 또는 Transit Gateway 설정"
echo "  2. DNS Resolution 테스트: ./test-dns.sh"
echo ""
