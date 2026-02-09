#!/bin/bash

# IRSA 테스트 스크립트

set -e

NAMESPACE="${NAMESPACE:-default}"
POD_NAME="s3-test-pod"

echo "=== IRSA 테스트 시작 ==="
echo ""

# 1. Pod 상태 확인
echo "1. Pod 상태 확인..."
kubectl get pod $POD_NAME -n $NAMESPACE
echo ""

# 2. ServiceAccount 확인
echo "2. ServiceAccount 확인..."
SA_NAME=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.serviceAccountName}')
echo "ServiceAccount: $SA_NAME"
kubectl get sa $SA_NAME -n $NAMESPACE -o yaml | grep -A 1 annotations
echo ""

# 3. 환경변수 확인
echo "3. 환경변수 확인..."
kubectl exec $POD_NAME -n $NAMESPACE -- env | grep AWS
echo ""

# 4. Token 파일 확인
echo "4. IRSA Token 파일 확인..."
kubectl exec $POD_NAME -n $NAMESPACE -- ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/
echo ""

# 5. 현재 사용 중인 IAM Role 확인
echo "5. 현재 사용 중인 IAM Role 확인..."
kubectl exec $POD_NAME -n $NAMESPACE -- aws sts get-caller-identity
echo ""

# 6. S3 버킷 목록 조회 테스트
echo "6. S3 버킷 목록 조회 테스트..."
kubectl exec $POD_NAME -n $NAMESPACE -- aws s3 ls
echo ""

# 7. 특정 S3 버킷 조회 (있는 경우)
echo "7. 특정 S3 버킷 조회 (선택)..."
read -p "테스트할 S3 버킷 이름 입력 (Enter로 건너뛰기): " BUCKET_NAME
if [ ! -z "$BUCKET_NAME" ]; then
  kubectl exec $POD_NAME -n $NAMESPACE -- aws s3 ls s3://$BUCKET_NAME/
fi
echo ""

echo "=== IRSA 테스트 완료 ==="
echo ""
echo "✅ IRSA가 정상적으로 동작하면 위에서 S3 버킷 목록이 보여야 합니다."
echo "❌ 권한 오류가 발생하면 IRSA 설정을 확인하세요."
