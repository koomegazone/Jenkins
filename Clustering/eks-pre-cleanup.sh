#!/bin/bash

# EKS 사전 리소스 삭제 스크립트
# 사용법: ./eks-pre-cleanup.sh <서비스명> <환경> <VPC_ID>
# 예시: ./eks-pre-cleanup.sh prism prd vpc-1234567890abcdef0

set -e

# AWS CLI 페이저 비활성화
export AWS_PAGER=""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 파라미터 체크
if [ $# -ne 3 ]; then
    echo -e "${RED}사용법: $0 <서비스명> <환경> <VPC_ID>${NC}"
    echo "예시: $0 prism prd vpc-1234567890abcdef0"
    echo "환경: prd, stg, dev, q 중 하나"
    exit 1
fi

SERVICE_NAME=$1
ENV=$2
VPC_ID=$3
REGION="an2"  # ap-northeast-2

# 환경 검증
if [[ ! "$ENV" =~ ^(prd|stg|dev|q)$ ]]; then
    echo -e "${RED}환경은 prd, stg, dev, q 중 하나여야 합니다.${NC}"
    exit 1
fi

# VPC ID 형식 검증
if [[ ! "$VPC_ID" =~ ^vpc-[0-9a-f]{8,17}$ ]]; then
    echo -e "${RED}VPC ID 형식이 올바르지 않습니다: $VPC_ID${NC}"
    echo "올바른 형식: vpc-1234567890abcdef0"
    exit 1
fi

# 네이밍 규칙
PREFIX="${SERVICE_NAME}-${ENV}-${REGION}"

# IAM Role명
ROLE_CLUSTER_FRONT="${PREFIX}-role-eks-cluster-front"
ROLE_CLUSTER_BACK="${PREFIX}-role-eks-cluster-back"
ROLE_NODE_FRONT_APP="${PREFIX}-role-eks-node-front-app"
ROLE_NODE_BACK_APP="${PREFIX}-role-eks-node-back-app"
ROLE_NODE_FRONT_MGMT="${PREFIX}-role-eks-node-front-mgmt"
ROLE_NODE_BACK_MGMT="${PREFIX}-role-eks-node-back-mgmt"

# 보안그룹명
SG_CLUSTER_FRONT="${PREFIX}-sg-eks-cluster-front"
SG_CLUSTER_BACK="${PREFIX}-sg-eks-cluster-back"
SG_NODE_FRONT_APP="${PREFIX}-sg-eks-node-front-app"
SG_NODE_BACK_APP="${PREFIX}-sg-eks-node-back-app"
SG_NODE_FRONT_MGMT="${PREFIX}-sg-eks-node-front-mgmt"
SG_NODE_BACK_MGMT="${PREFIX}-sg-eks-node-back-mgmt"

echo "=========================================="
echo "  EKS 사전 리소스 삭제 스크립트"
echo "=========================================="
echo ""
echo "서비스명: ${SERVICE_NAME}"
echo "환경: ${ENV}"
echo "리전: ap-northeast-2"
echo "VPC ID: ${VPC_ID}"
echo ""

# VPC 존재 확인
echo "VPC 확인 중..."
if ! aws ec2 describe-vpcs --vpc-ids $VPC_ID --region ap-northeast-2 &>/dev/null; then
    echo -e "${RED}✗ VPC ID가 존재하지 않습니다: $VPC_ID${NC}"
    exit 1
fi

echo -e "${GREEN}✓ VPC 확인 완료: $VPC_ID${NC}"
echo ""

# 삭제할 리소스 확인
echo "=========================================="
echo "  삭제할 리소스 목록"
echo "=========================================="
echo ""
echo -e "${BLUE}[클러스터 IAM Role]${NC}"
echo "  - $ROLE_CLUSTER_FRONT"
echo "  - $ROLE_CLUSTER_BACK"
echo ""
echo -e "${BLUE}[노드 IAM Role]${NC}"
echo "  - $ROLE_NODE_FRONT_APP"
echo "  - $ROLE_NODE_BACK_APP"
echo "  - $ROLE_NODE_FRONT_MGMT"
echo "  - $ROLE_NODE_BACK_MGMT"
echo ""
echo -e "${BLUE}[클러스터 보안그룹]${NC}"
echo "  - $SG_CLUSTER_FRONT"
echo "  - $SG_CLUSTER_BACK"
echo ""
echo -e "${BLUE}[노드 보안그룹]${NC}"
echo "  - $SG_NODE_FRONT_APP"
echo "  - $SG_NODE_BACK_APP"
echo "  - $SG_NODE_FRONT_MGMT"
echo "  - $SG_NODE_BACK_MGMT"
echo ""

echo -e "${RED}⚠️  경고: 이 작업은 되돌릴 수 없습니다!${NC}"
echo ""
read -p "위 리소스를 삭제하시겠습니까? (yes 입력 필요): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""
echo "=========================================="
echo "  1. IAM Role 삭제"
echo "=========================================="
echo ""

# IAM Role 삭제 함수
delete_iam_role() {
    local role_name=$1
    echo -e "${YELLOW}IAM Role 삭제: $role_name${NC}"
    
    if ! aws iam get-role --role-name $role_name &>/dev/null; then
        echo -e "${YELLOW}  ⚠ Role이 존재하지 않습니다. 스킵${NC}"
        return
    fi
    
    # 연결된 정책 조회 및 분리
    echo "  - 연결된 정책 분리 중..."
    local attached_policies=$(aws iam list-attached-role-policies --role-name $role_name --query 'AttachedPolicies[].PolicyArn' --output text)
    
    if [ ! -z "$attached_policies" ]; then
        for policy_arn in $attached_policies; do
            local policy_name=$(echo $policy_arn | awk -F'/' '{print $NF}')
            echo "    - $policy_name 분리 중..."
            aws iam detach-role-policy \
                --role-name $role_name \
                --policy-arn $policy_arn
        done
    fi
    
    # 인라인 정책 삭제
    local inline_policies=$(aws iam list-role-policies --role-name $role_name --query 'PolicyNames' --output text)
    if [ ! -z "$inline_policies" ]; then
        echo "  - 인라인 정책 삭제 중..."
        for policy_name in $inline_policies; do
            echo "    - $policy_name 삭제 중..."
            aws iam delete-role-policy \
                --role-name $role_name \
                --policy-name $policy_name
        done
    fi
    
    # 인스턴스 프로파일 분리 및 삭제
    local instance_profiles=$(aws iam list-instance-profiles-for-role --role-name $role_name --query 'InstanceProfiles[].InstanceProfileName' --output text)
    if [ ! -z "$instance_profiles" ]; then
        echo "  - 인스턴스 프로파일 분리 중..."
        for profile_name in $instance_profiles; do
            echo "    - $profile_name 분리 중..."
            aws iam remove-role-from-instance-profile \
                --instance-profile-name $profile_name \
                --role-name $role_name
            
            echo "    - $profile_name 삭제 중..."
            aws iam delete-instance-profile \
                --instance-profile-name $profile_name
        done
    fi
    
    # Role 삭제
    echo "  - Role 삭제 중..."
    aws iam delete-role --role-name $role_name
    
    echo -e "${GREEN}  ✓ 삭제 완료${NC}"
}

# 클러스터 Role 삭제
delete_iam_role $ROLE_CLUSTER_FRONT
delete_iam_role $ROLE_CLUSTER_BACK

# 노드 Role 삭제
delete_iam_role $ROLE_NODE_FRONT_APP
delete_iam_role $ROLE_NODE_BACK_APP
delete_iam_role $ROLE_NODE_FRONT_MGMT
delete_iam_role $ROLE_NODE_BACK_MGMT

echo ""
echo "=========================================="
echo "  2. 보안그룹 삭제"
echo "=========================================="
echo ""

# 보안그룹 삭제 함수
delete_security_group() {
    local sg_name=$1
    echo -e "${YELLOW}보안그룹 삭제: $sg_name${NC}"
    
    # 보안그룹 ID 조회
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_name" "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
    
    if [ "$sg_id" == "None" ] || [ -z "$sg_id" ]; then
        echo -e "${YELLOW}  ⚠ 보안그룹이 존재하지 않습니다. 스킵${NC}"
        return
    fi
    
    echo "  - 보안그룹 ID: $sg_id"
    
    # Ingress 규칙 삭제
    echo "  - Ingress 규칙 삭제 중..."
    local ingress_rules=$(aws ec2 describe-security-groups --group-ids $sg_id --query 'SecurityGroups[0].IpPermissions' --output json)
    if [ "$ingress_rules" != "[]" ] && [ "$ingress_rules" != "null" ]; then
        aws ec2 revoke-security-group-ingress \
            --group-id $sg_id \
            --ip-permissions "$ingress_rules" 2>/dev/null || echo "    (규칙 없음)"
    fi
    
    # Egress 규칙 삭제
    echo "  - Egress 규칙 삭제 중..."
    local egress_rules=$(aws ec2 describe-security-groups --group-ids $sg_id --query 'SecurityGroups[0].IpPermissionsEgress' --output json)
    if [ "$egress_rules" != "[]" ] && [ "$egress_rules" != "null" ]; then
        aws ec2 revoke-security-group-egress \
            --group-id $sg_id \
            --ip-permissions "$egress_rules" 2>/dev/null || echo "    (규칙 없음)"
    fi
    
    # 보안그룹 삭제 (재시도 로직 포함)
    echo "  - 보안그룹 삭제 중..."
    local retry=0
    local max_retry=5
    while [ $retry -lt $max_retry ]; do
        if aws ec2 delete-security-group --group-id $sg_id 2>/dev/null; then
            echo -e "${GREEN}  ✓ 삭제 완료${NC}"
            return
        else
            retry=$((retry + 1))
            if [ $retry -lt $max_retry ]; then
                echo "    재시도 중... ($retry/$max_retry)"
                sleep 3
            fi
        fi
    done
    
    echo -e "${RED}  ✗ 삭제 실패 (다른 리소스에서 사용 중일 수 있음)${NC}"
}

# 노드 보안그룹 먼저 삭제 (의존성 때문)
delete_security_group $SG_NODE_FRONT_APP
delete_security_group $SG_NODE_BACK_APP
delete_security_group $SG_NODE_FRONT_MGMT
delete_security_group $SG_NODE_BACK_MGMT

# 클러스터 보안그룹 삭제
delete_security_group $SG_CLUSTER_FRONT
delete_security_group $SG_CLUSTER_BACK

echo ""
echo "=========================================="
echo "  삭제 완료!"
echo "=========================================="
echo ""
echo -e "${GREEN}✓ 모든 리소스 삭제가 완료되었습니다.${NC}"
echo ""
echo -e "${YELLOW}참고:${NC}"
echo "- 일부 보안그룹이 삭제되지 않았다면, ENI나 다른 리소스에서 사용 중일 수 있습니다."
echo "- 해당 리소스를 먼저 삭제한 후 다시 시도하세요."
echo ""
