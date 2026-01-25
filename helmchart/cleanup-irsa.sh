#!/bin/bash
set -e

# AWS CLI 페이저 비활성화
export AWS_PAGER=""

# 사용법 체크
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "사용법: $0 <cluster-name> <app-name>"
  echo ""
  echo "예시:"
  echo "  $0 prism-q-an2-eks-cluster-front prismfo"
  echo "  $0 prism-q-an2-eks-cluster-back prismbo"
  echo "  $0 prism-q-an2-eks-cluster-back prismopenapi"
  echo "  $0 prism-q-an2-eks-cluster-back prismbatch"
  echo ""
  echo "지원되는 앱: prismfo, prismbo, prismopenapi, prismbatch"
  exit 1
fi

# 변수 설정
CLUSTER_NAME="$1"
APP_NAME="$2"
REGION="ap-northeast-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
NAMESPACE="ns-prism"

# 앱 이름 검증
case $APP_NAME in
  prismfo|prismbo|prismopenapi|prismbatch)
    ;;
  *)
    echo "Error: 지원되지 않는 앱 이름입니다: $APP_NAME"
    echo "지원되는 앱: prismfo, prismbo, prismopenapi, prismbatch"
    exit 1
    ;;
esac

# Service Account 이름 설정
SERVICE_ACCOUNT="${APP_NAME}-cm-java"

# 클러스터 이름에서 front/back 추출
if [[ $CLUSTER_NAME == *"front"* ]]; then
  CLUSTER_TYPE="front"
elif [[ $CLUSTER_NAME == *"back"* ]]; then
  CLUSTER_TYPE="back"
else
  echo "Error: 클러스터 이름에 'front' 또는 'back'이 포함되어야 합니다."
  exit 1
fi

ROLE_NAME="prism-q-an2-role-eks-irsa-java-${APP_NAME}"
INLINE_POLICY_NAME="prism-q-an2-pol-kms-secretmanager-prism"

echo "=== PRISM Java Application IAM Role 삭제 ==="
echo "Cluster: $CLUSTER_NAME"
echo "Cluster Type: $CLUSTER_TYPE"
echo "App Name: $APP_NAME"
echo "Region: $REGION"
echo "Account ID: $ACCOUNT_ID"
echo "Role Name: $ROLE_NAME"
echo "Namespace: $NAMESPACE"
echo "Service Account: $SERVICE_ACCOUNT"
echo ""

echo "⚠️  경고: 다음 리소스가 삭제됩니다:"
echo "  - IAM Role: $ROLE_NAME"
echo "  - 연결된 AWS 관리형 정책 (AmazonS3FullAccess, AmazonAPIGatewayAdministrator)"
echo "  - 인라인 정책: $INLINE_POLICY_NAME"
echo ""
read -p "계속하시겠습니까? (yes 입력 필요): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "취소되었습니다."
  exit 0
fi

echo ""

# 1. Role 존재 확인
echo "1. Role 존재 확인 중..."
if ! aws iam get-role --role-name $ROLE_NAME &>/dev/null; then
  echo "⚠️  Role을 찾을 수 없습니다: $ROLE_NAME"
  echo "이미 삭제되었거나 존재하지 않습니다."
  echo ""
  echo "=== 완료 ==="
  exit 0
fi

echo "✅ Role 확인 완료: $ROLE_NAME"
echo ""

# 2. Role에서 관리형 정책 분리
echo "2. Role에서 관리형 정책 분리 중..."
ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $ROLE_NAME --query 'AttachedPolicies[].PolicyArn' --output text)

if [ ! -z "$ATTACHED_POLICIES" ]; then
  for policy_arn in $ATTACHED_POLICIES; do
    policy_name=$(echo $policy_arn | awk -F'/' '{print $NF}')
    echo "  분리: $policy_name"
    aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $policy_arn
  done
  echo "✅ 관리형 정책 분리 완료"
else
  echo "  (연결된 관리형 정책 없음)"
fi
echo ""

# 3. 인라인 정책 삭제
echo "3. 인라인 정책 삭제 중..."
INLINE_POLICIES=$(aws iam list-role-policies --role-name $ROLE_NAME --query 'PolicyNames' --output text)

if [ ! -z "$INLINE_POLICIES" ]; then
  for policy_name in $INLINE_POLICIES; do
    echo "  삭제: $policy_name"
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

echo "=== 완료 ==="
echo ""
echo "삭제된 리소스:"
echo "  - IAM Role: $ROLE_NAME"
echo "  - 분리된 관리형 정책: AmazonS3FullAccess, AmazonAPIGatewayAdministrator"
echo "  - 삭제된 인라인 정책: $INLINE_POLICY_NAME"
echo ""
echo "Kubernetes ServiceAccount는 수동으로 삭제해야 합니다:"
echo "kubectl delete serviceaccount $SERVICE_ACCOUNT -n $NAMESPACE --context=$CLUSTER_NAME"
echo ""
