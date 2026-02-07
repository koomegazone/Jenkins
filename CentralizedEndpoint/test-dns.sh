#!/bin/bash

# DNS Resolution 테스트 스크립트
# Spoke VPC EC2에서 실행

echo "=========================================="
echo "DNS Resolution 테스트"
echo "=========================================="
echo ""

# 테스트할 도메인 목록
DOMAINS=(
    "ec2.ap-northeast-2.amazonaws.com"
    "eks.ap-northeast-2.amazonaws.com"
    "elasticfilesystem.ap-northeast-2.amazonaws.com"
    "sts.ap-northeast-2.amazonaws.com"
    "autoscaling.ap-northeast-2.amazonaws.com"
    "elasticloadbalancing.ap-northeast-2.amazonaws.com"
    "api.ecr.ap-northeast-2.amazonaws.com"
)

echo "Hub VPC Endpoint로 DNS Resolution이 되는지 확인합니다..."
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for domain in "${DOMAINS[@]}"; do
    echo "테스트: $domain"
    
    # nslookup 실행
    RESULT=$(nslookup $domain 2>&1)
    
    # IP 주소 추출
    IP=$(echo "$RESULT" | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
    
    if [ ! -z "$IP" ]; then
        # Private IP 범위 확인 (10.x.x.x)
        if [[ $IP == 10.* ]]; then
            echo "  ✓ 성공: $IP (Hub VPC Endpoint)"
            ((SUCCESS_COUNT++))
        else
            echo "  ⚠️  경고: $IP (Public IP - Endpoint 미사용)"
            ((FAIL_COUNT++))
        fi
    else
        echo "  ✗ 실패: DNS Resolution 실패"
        ((FAIL_COUNT++))
    fi
    echo ""
done

# 결과 요약
echo "=========================================="
echo "테스트 결과"
echo "=========================================="
echo "성공: $SUCCESS_COUNT / $((SUCCESS_COUNT + FAIL_COUNT))"
echo "실패: $FAIL_COUNT / $((SUCCESS_COUNT + FAIL_COUNT))"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "✓ 모든 DNS Resolution이 정상적으로 Hub VPC Endpoint를 사용합니다!"
else
    echo "⚠️  일부 DNS Resolution이 실패했습니다."
    echo ""
    echo "트러블슈팅:"
    echo "  1. Forwarding Rules가 Spoke VPC에 연결되었는지 확인"
    echo "  2. VPC Peering 또는 Transit Gateway 연결 확인"
    echo "  3. Security Group에서 DNS 포트 (53) 허용 확인"
    echo "  4. Hub Inbound Endpoint 상태 확인"
fi
echo ""
