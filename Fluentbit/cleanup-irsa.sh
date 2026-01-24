#!/bin/bash
set -e

# AWS CLI 페이저 비활성화
export AWS_PAGER=""

# 사용법 체크
if [ -z "$1" ]; then
  echo "사용법: $0 <cluster-name>"
  echo "예시: $0 prism-q-an2-eks-cluster-front"
  echo "예시: $0 prism-q-an2-eks-cluster-back"
  exit 1
fi

# 변수 설정
CLUSTER_NAME="$1"
REGION="ap-northeast-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 클러스터 이름에서 front/back 추출
if [[ $CLUSTER_NAME == *"front"* ]]; then
  CLUSTER_TYPE="front"
elif [[ $CLUSTER_NAME == *"back"* ]]; then
  CLUSTER_TYPE="back"
else
  echo "Error: 클러스터 이름에 'front' 또는 'back'이 포함되어야 합니다."
  exit 1
fi

POLICY_NAME="prism-q-an2-pol-eks-irsa-fluent-bit-${CLUSTER_TYPE}"
ROLE_NAME="prism-q-an2-role-eks-irsa-fluent-bit-${CLUSTER_TYPE}"

echo "=== Fluent Bit IAM Role 삭제 ==="
echo "Cluster: $CLUSTER_NAME"
echo "Cluster Type: $CLUSTER_TYPE"
echo "Region: $REGION"
echo "Account ID: $ACCOUNT_ID"
echo "Policy Name: $POLICY_NAME"
echo "Role Name: $ROLE_NAME"
echo ""

echo "⚠️  경고: 다음 리소스가 삭제됩니다:"
echo "  - IAM Role: $ROLE_NAME"
echo "  - IAM Policy: $POLICY_NAME"
echo ""
read -p "계속하시겠습니까? (yes 입력 필요): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "취소되었습니다."
  exit 0
fi

echo ""

# 1. Policy ARN 조회
echo "1. Policy ARN 조회 중..."
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)

if [ -z "$POLICY_ARN" ]; then
  echo "⚠️  Policy를 찾을 수 없습니다: $POLICY_NAME"
  echo "이미 삭제되었거나 존재하지 않습니다."
else
  echo "Policy ARN: $POLICY_ARN"
fi
echo ""

# 2. Role 존재 확인
echo "2. Role 존재 확인 중..."
if ! aws iam get-role --role-name $ROLE_NAME &>/dev/null; then
  echo "⚠️  Role을 찾을 수 없습니다: $ROLE_NAME"
  echo "이미 삭제되었거나 존재하지 않습니다."
  
  # Role이 없으면 Policy만 삭제 시도
  if [ ! -z "$POLICY_ARN" ]; then
    echo ""
    echo "3. Policy 삭제 중..."
    
    # Policy가 다른 곳에서 사용 중인지 확인
    POLICY_ATTACHMENTS=$(aws iam list-entities-for-policy --policy-arn $POLICY_ARN --query 'length(PolicyRoles) + length(PolicyUsers) + length(PolicyGroups)' --output text)
    
    if [ "$POLICY_ATTACHMENTS" -gt 0 ]; then
      echo "⚠️  Policy가 다른 리소스에서 사용 중입니다."
      echo "Policy를 삭제하려면 먼저 모든 연결을 해제해야 합니다."
      exit 1
    fi
    
    # Policy 버전 삭제 (기본 버전 제외)
    echo "  - Policy 버전 삭제 중..."
    POLICY_VERSIONS=$(aws iam list-policy-versions --policy-arn $POLICY_ARN --query 'Versions[?!IsDefaultVersion].VersionId' --output text)
    for version in $POLICY_VERSIONS; do
      echo "    삭제: $version"
      aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id $version
    done
    
    # Policy 삭제
    echo "  - Policy 삭제 중..."
    aws iam delete-policy --policy-arn $POLICY_ARN
    echo "✅ Policy 삭제 완료"
  fi
  
  echo ""
  echo "=== 완료 ==="
  exit 0
fi

echo "✅ Role 확인 완료: $ROLE_NAME"
echo ""

# 3. Role에서 Policy 분리
echo "3. Role에서 Policy 분리 중..."

# 관리형 정책 분리
echo "  - 관리형 정책 분리 중..."
ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $ROLE_NAME --query 'AttachedPolicies[].PolicyArn' --output text)

if [ ! -z "$ATTACHED_POLICIES" ]; then
  for policy_arn in $ATTACHED_POLICIES; do
    policy_name=$(echo $policy_arn | awk -F'/' '{print $NF}')
    echo "    분리: $policy_name"
    aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $policy_arn
  done
  echo "✅ 관리형 정책 분리 완료"
else
  echo "  (연결된 관리형 정책 없음)"
fi

# 인라인 정책 삭제
echo "  - 인라인 정책 삭제 중..."
INLINE_POLICIES=$(aws iam list-role-policies --role-name $ROLE_NAME --query 'PolicyNames' --output text)

if [ ! -z "$INLINE_POLICIES" ]; then
  for policy_name in $INLINE_POLICIES; do
    echo "    삭제: $policy_name"
    aws iam delete-role-policy --role-name $ROLE_NAME --policy-name $policy_name
  done
  echo "✅ 인라인 정책 삭제 완료"
else
  echo "  (인라인 정책 없음)"
fi

echo ""

# 4. Role 삭제
echo "4. Role 삭제 중..."
aws iam delete-role --role-name $ROLE_NAME
echo "✅ Role 삭제 완료"
echo ""

# 5. Policy 삭제
if [ ! -z "$POLICY_ARN" ]; then
  echo "5. Policy 삭제 중..."
  
  # Policy가 다른 곳에서 사용 중인지 확인
  POLICY_ATTACHMENTS=$(aws iam list-entities-for-policy --policy-arn $POLICY_ARN --query 'length(PolicyRoles) + length(PolicyUsers) + length(PolicyGroups)' --output text)
  
  if [ "$POLICY_ATTACHMENTS" -gt 0 ]; then
    echo "⚠️  Policy가 다른 리소스에서 사용 중입니다."
    echo "Policy를 삭제하려면 먼저 모든 연결을 해제해야 합니다."
    echo ""
    echo "다음 명령으로 Policy 사용 현황을 확인하세요:"
    echo "aws iam list-entities-for-policy --policy-arn $POLICY_ARN"
    exit 1
  fi
  
  # Policy 버전 삭제 (기본 버전 제외)
  echo "  - Policy 버전 삭제 중..."
  POLICY_VERSIONS=$(aws iam list-policy-versions --policy-arn $POLICY_ARN --query 'Versions[?!IsDefaultVersion].VersionId' --output text)
  
  if [ ! -z "$POLICY_VERSIONS" ]; then
    for version in $POLICY_VERSIONS; do
      echo "    삭제: $version"
      aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id $version
    done
  fi
  
  # Policy 삭제
  echo "  - Policy 삭제 중..."
  aws iam delete-policy --policy-arn $POLICY_ARN
  echo "✅ Policy 삭제 완료"
else
  echo "5. Policy를 찾을 수 없어 스킵합니다."
fi

echo ""
echo "=== 완료 ==="
echo ""
echo "삭제된 리소스:"
echo "  - IAM Role: $ROLE_NAME"
if [ ! -z "$POLICY_ARN" ]; then
  echo "  - IAM Policy: $POLICY_NAME ($POLICY_ARN)"
fi
echo ""
echo "Kubernetes ServiceAccount는 수동으로 삭제해야 합니다:"
echo "kubectl delete serviceaccount fluent-bit -n kube-system --context=$CLUSTER_NAME"
echo ""
