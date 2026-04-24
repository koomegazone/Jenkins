#!/bin/bash

# IRSA Role 생성 스크립트 (자가 점검 포함)
# 사용법: ./create-irsa-roles.sh
# 대상 Role:
#   - prism-p-an2-role-eks-irsa-java-prismbatch
#   - prism-p-an2-role-eks-irsa-java-prismbo
#   - prism-p-an2-role-eks-irsa-java-prismopenapi

set -e

export AWS_PAGER=""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정값
ACCOUNT_ID="816711409900"
OIDC_ID="67EADCB4B6AE12BAF26E44381713A2A1"
OIDC_PROVIDER="oidc.eks.ap-northeast-2.amazonaws.com/id/${OIDC_ID}"
NAMESPACE="ns-prism"

# 생성할 Role 목록 (role_name:service_account)
ROLES=(
    "prism-p-an2-role-eks-irsa-java-prismbatch:prismbatch-cm-java"
    "prism-p-an2-role-eks-irsa-java-prismbo:prismbo-cm-java"
    "prism-p-an2-role-eks-irsa-java-prismopenapi:prismopenapi-cm-java"
)

echo "=========================================="
echo "  IRSA Role 생성 스크립트"
echo "=========================================="
echo ""
echo "OIDC Provider: ${OIDC_PROVIDER}"
echo "Namespace: ${NAMESPACE}"
echo "Account ID: ${ACCOUNT_ID}"
echo ""

# ==========================================
#  사전 점검
# ==========================================
echo "=========================================="
echo "  사전 점검"
echo "=========================================="
echo ""

PREFLIGHT_PASS=true

# 1. AWS CLI 설치 확인
echo -n "  AWS CLI 설치 확인... "
if command -v aws &>/dev/null; then
    echo -e "${GREEN}✓ $(aws --version 2>&1 | head -1)${NC}"
else
    echo -e "${RED}✗ AWS CLI가 설치되어 있지 않습니다${NC}"
    PREFLIGHT_PASS=false
fi

# 2. AWS 인증 확인
echo -n "  AWS 인증 확인... "
if CALLER_ID=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null); then
    echo -e "${GREEN}✓ ${CALLER_ID}${NC}"
else
    echo -e "${RED}✗ AWS 인증 실패${NC}"
    PREFLIGHT_PASS=false
fi

# 3. Account ID 일치 확인
echo -n "  Account ID 확인... "
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
if [ "$CURRENT_ACCOUNT" == "$ACCOUNT_ID" ]; then
    echo -e "${GREEN}✓ ${CURRENT_ACCOUNT}${NC}"
else
    echo -e "${RED}✗ 현재 계정(${CURRENT_ACCOUNT})이 대상 계정(${ACCOUNT_ID})과 다릅니다${NC}"
    PREFLIGHT_PASS=false
fi

# 4. OIDC Provider 존재 확인
echo -n "  OIDC Provider 확인... "
if aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, '${OIDC_ID}')]" --output text 2>/dev/null | grep -q "${OIDC_ID}"; then
    echo -e "${GREEN}✓ OIDC Provider 존재${NC}"
else
    echo -e "${YELLOW}⚠ OIDC Provider를 확인할 수 없습니다 (권한 부족일 수 있음)${NC}"
fi

# 5. IAM 권한 확인 (create-role 시뮬레이션)
echo -n "  IAM 권한 확인... "
if aws iam simulate-principal-policy \
    --policy-source-arn "$CALLER_ID" \
    --action-names "iam:CreateRole" "iam:GetRole" \
    --query 'EvaluationResults[0].EvalDecision' --output text 2>/dev/null | grep -q "allowed"; then
    echo -e "${GREEN}✓ IAM 권한 충분${NC}"
else
    echo -e "${YELLOW}⚠ IAM 권한 시뮬레이션 불가 (실행 시 확인됩니다)${NC}"
fi

echo ""

if [ "$PREFLIGHT_PASS" = false ]; then
    echo -e "${RED}사전 점검 실패. 위 오류를 해결한 후 다시 실행해주세요.${NC}"
    exit 1
fi

# ==========================================
#  Role 생성
# ==========================================
echo "=========================================="
echo "  Role 생성"
echo "=========================================="
echo ""

CREATED=0
SKIPPED=0
FAILED=0

for entry in "${ROLES[@]}"; do
    ROLE_NAME="${entry%%:*}"
    SA_NAME="${entry##*:}"

    echo -e "${BLUE}▶ ${ROLE_NAME}${NC}"
    echo "  ServiceAccount: ${NAMESPACE}:${SA_NAME}"

    # 이미 존재하는지 확인
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        echo -e "${YELLOW}  ⚠ 이미 존재합니다. 스킵${NC}"
        SKIPPED=$((SKIPPED + 1))
        echo ""
        continue
    fi

    # Trust Policy 생성
    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SA_NAME}",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
)

    # Role 생성
    if aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --tags Key=Name,Value="$ROLE_NAME" Key=Service,Value=prism Key=Environment,Value=prd \
        > /dev/null 2>&1; then
        echo -e "${GREEN}  ✓ 생성 완료${NC}"
        CREATED=$((CREATED + 1))
    else
        echo -e "${RED}  ✗ 생성 실패${NC}"
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

# ==========================================
#  자가 점검 (Post-Validation)
# ==========================================
echo "=========================================="
echo "  자가 점검 (Post-Validation)"
echo "=========================================="
echo ""

VALIDATION_PASS=true

for entry in "${ROLES[@]}"; do
    ROLE_NAME="${entry%%:*}"
    SA_NAME="${entry##*:}"

    echo -e "${BLUE}▶ ${ROLE_NAME} 점검${NC}"

    # 1. Role 존재 확인
    echo -n "  Role 존재... "
    if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        echo -e "${RED}✗ 존재하지 않음${NC}"
        VALIDATION_PASS=false
        echo ""
        continue
    fi
    echo -e "${GREEN}✓${NC}"

    # 2. Trust Policy 검증 - OIDC Provider 확인
    echo -n "  Trust Policy OIDC... "
    TRUST_DOC=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null)
    if echo "$TRUST_DOC" | grep -q "$OIDC_ID"; then
        echo -e "${GREEN}✓ OIDC ID 일치${NC}"
    else
        echo -e "${RED}✗ OIDC ID 불일치${NC}"
        VALIDATION_PASS=false
    fi

    # 3. Trust Policy 검증 - ServiceAccount 확인
    echo -n "  Trust Policy SA... "
    if echo "$TRUST_DOC" | grep -q "${NAMESPACE}:${SA_NAME}"; then
        echo -e "${GREEN}✓ ${NAMESPACE}:${SA_NAME}${NC}"
    else
        echo -e "${RED}✗ ServiceAccount 불일치${NC}"
        VALIDATION_PASS=false
    fi

    # 4. Trust Policy 검증 - Action 확인
    echo -n "  Trust Policy Action... "
    if echo "$TRUST_DOC" | grep -q "sts:AssumeRoleWithWebIdentity"; then
        echo -e "${GREEN}✓ AssumeRoleWithWebIdentity${NC}"
    else
        echo -e "${RED}✗ Action 불일치${NC}"
        VALIDATION_PASS=false
    fi

    # 5. Role ARN 출력
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null)
    echo "  Role ARN: ${ROLE_ARN}"
    echo ""
done

# ==========================================
#  최종 결과
# ==========================================
echo "=========================================="
echo "  최종 결과"
echo "=========================================="
echo ""
echo "  생성: ${CREATED}개"
echo "  스킵(이미 존재): ${SKIPPED}개"
echo "  실패: ${FAILED}개"
echo ""

if [ "$VALIDATION_PASS" = true ] && [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ 모든 점검 통과${NC}"
else
    echo -e "${RED}✗ 일부 점검 실패. 위 로그를 확인해주세요.${NC}"
fi

echo ""
echo -e "${YELLOW}다음 단계:${NC}"
echo "  1. 필요한 IAM Policy를 각 Role에 attach"
echo "  2. K8s ServiceAccount에 annotation 추가:"
echo "     kubectl annotate sa <sa-name> -n ${NAMESPACE} \\"
echo "       eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/<role-name>"
echo ""
