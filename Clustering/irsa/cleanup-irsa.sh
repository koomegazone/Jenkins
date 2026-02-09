#!/bin/bash

# IRSA 정리 스크립트

set -e

CLUSTER_NAME="${CLUSTER_NAME:-my-cluster}"
REGION="${REGION:-ap-northeast-2}"
NAMESPACE="${NAMESPACE:-default}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-s3-test-sa}"
ROLE_NAME="${ROLE_NAME:-S3TestIRSARole}"
POLICY_NAME="${POLICY_NAME:-S3TestPolicy}"

echo "=== IRSA 정리 시작 ==="
echo ""

# 1. 테스트 Pod 삭제
echo "1. 테스트 Pod 삭제..."
kubectl delete pod s3-test-pod -n $NAMESPACE --ignore-not-found=true
echo "✅ Pod 삭제 완료"
echo ""

# 2. ServiceAccount 삭제
echo "2. ServiceAccount 삭제..."
kubectl delete sa $SERVICE_ACCOUNT -n $NAMESPACE --ignore-not-found=true
echo "✅ ServiceAccount 삭제 완료"
echo ""

# 3. IAM Policy 분리
echo "3. IAM Policy 분리..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

aws iam detach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN 2>/dev/null || echo "Policy 이미 분리됨"
echo "✅ Policy 분리 완료"
echo ""

# 4. IAM Role 삭제
echo "4. IAM Role 삭제..."
aws iam delete-role --role-name $ROLE_NAME 2>/dev/null || echo "Role 이미 삭제됨"
echo "✅ Role 삭제 완료"
echo ""

# 5. IAM Policy 삭제
echo "5. IAM Policy 삭제..."
aws iam delete-policy --policy-arn $POLICY_ARN 2>/dev/null || echo "Policy 이미 삭제됨"
echo "✅ Policy 삭제 완료"
echo ""

echo "=== IRSA 정리 완료 ==="
echo ""
echo "⚠️  OIDC Provider는 삭제하지 않았습니다."
echo "   다른 IRSA에서 사용 중일 수 있습니다."
echo ""
echo "OIDC Provider도 삭제하려면:"
echo "  aws iam delete-open-id-connect-provider --open-id-connect-provider-arn <arn>"
