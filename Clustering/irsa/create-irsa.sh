#!/bin/bash

# IRSA 생성 스크립트 (eksctl 없이)
# S3 접근 테스트용

set -e

# 변수 설정
CLUSTER_NAME="${CLUSTER_NAME:-my-cluster}"
REGION="${REGION:-ap-northeast-2}"
NAMESPACE="${NAMESPACE:-default}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-s3-test-sa}"
ROLE_NAME="${ROLE_NAME:-S3TestIRSARole}"
POLICY_NAME="${POLICY_NAME:-S3TestPolicy}"

echo "=== IRSA 생성 시작 ==="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Namespace: $NAMESPACE"
echo "ServiceAccount: $SERVICE_ACCOUNT"
echo "Role: $ROLE_NAME"
echo ""

# 1. OIDC Provider URL 가져오기
echo "Step 1: OIDC Provider 확인..."
OIDC_URL=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION \
  --query "cluster.identity.oidc.issuer" --output text)

if [ -z "$OIDC_URL" ]; then
  echo "❌ Error: OIDC URL을 가져올 수 없습니다."
  exit 1
fi

OIDC_ID=$(echo $OIDC_URL | sed 's|https://||' | sed 's|/id/|/id/|')
OIDC_PROVIDER_ID=$(echo $OIDC_URL | awk -F'/' '{print $NF}')

echo "OIDC URL: $OIDC_URL"
echo "OIDC ID: $OIDC_PROVIDER_ID"
echo ""

# 2. AWS Account ID 가져오기
echo "Step 2: AWS Account ID 확인..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# 3. OIDC Provider 존재 확인
echo "Step 3: OIDC Provider 존재 확인..."
OIDC_EXISTS=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, '$OIDC_PROVIDER_ID')].Arn" \
  --output text)

if [ -z "$OIDC_EXISTS" ]; then
  echo "⚠️  OIDC Provider가 없습니다. 생성 중..."
  
  # OIDC Provider 생성
  aws iam create-open-id-connect-provider \
    --url $OIDC_URL \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list $(echo | openssl s_client -servername oidc.eks.$REGION.amazonaws.com \
      -connect oidc.eks.$REGION.amazonaws.com:443 2>/dev/null | \
      openssl x509 -fingerprint -noout | sed 's/://g' | awk -F= '{print tolower($2)}')
  
  echo "✅ OIDC Provider 생성 완료"
else
  echo "✅ OIDC Provider 이미 존재: $OIDC_EXISTS"
fi
echo ""

# 4. Trust Policy 생성
echo "Step 4: Trust Policy 생성..."
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_ID}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_ID}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}",
        "${OIDC_ID}:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF

echo "✅ Trust Policy 생성 완료"
cat /tmp/trust-policy.json
echo ""

# 5. IAM Policy 생성 (S3 읽기 권한)
echo "Step 5: IAM Policy 생성..."
cat > /tmp/s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:ListBucket",
      "s3:ListAllMyBuckets",
      "s3:GetObject",
      "s3:GetBucketLocation"
    ],
    "Resource": "*"
  }]
}
EOF

# Policy 존재 확인
POLICY_ARN=$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)

if [ -z "$POLICY_ARN" ]; then
  echo "Policy 생성 중..."
  POLICY_ARN=$(aws iam create-policy \
    --policy-name $POLICY_NAME \
    --policy-document file:///tmp/s3-policy.json \
    --query 'Policy.Arn' --output text)
  echo "✅ Policy 생성 완료: $POLICY_ARN"
else
  echo "✅ Policy 이미 존재: $POLICY_ARN"
fi
echo ""

# 6. IAM Role 생성
echo "Step 6: IAM Role 생성..."
ROLE_EXISTS=$(aws iam get-role --role-name $ROLE_NAME 2>/dev/null || echo "")

if [ -z "$ROLE_EXISTS" ]; then
  echo "Role 생성 중..."
  aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    --description "IRSA Role for S3 access test"
  
  echo "✅ Role 생성 완료"
else
  echo "⚠️  Role이 이미 존재합니다. Trust Policy 업데이트 중..."
  aws iam update-assume-role-policy \
    --role-name $ROLE_NAME \
    --policy-document file:///tmp/trust-policy.json
  echo "✅ Trust Policy 업데이트 완료"
fi
echo ""

# 7. Policy를 Role에 연결
echo "Step 7: Policy를 Role에 연결..."
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN
echo "✅ Policy 연결 완료"
echo ""

# 8. Kubernetes Namespace 생성 (없으면)
echo "Step 8: Namespace 확인..."
kubectl get namespace $NAMESPACE 2>/dev/null || kubectl create namespace $NAMESPACE
echo "✅ Namespace 준비 완료"
echo ""

# 9. ServiceAccount 생성
echo "Step 9: ServiceAccount 생성..."
cat > /tmp/serviceaccount.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SERVICE_ACCOUNT
  namespace: $NAMESPACE
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}
EOF

kubectl apply -f /tmp/serviceaccount.yaml
echo "✅ ServiceAccount 생성 완료"
echo ""

# 10. 테스트 Pod 생성
echo "Step 10: 테스트 Pod 생성..."
cat > /tmp/test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: s3-test-pod
  namespace: $NAMESPACE
spec:
  serviceAccountName: $SERVICE_ACCOUNT
  containers:
  - name: aws-cli
    image: amazon/aws-cli:latest
    command: ["sleep", "3600"]
  restartPolicy: Never
EOF

kubectl apply -f /tmp/test-pod.yaml
echo "✅ 테스트 Pod 생성 완료"
echo ""

# 11. Pod 준비 대기
echo "Step 11: Pod 준비 대기..."
kubectl wait --for=condition=Ready pod/s3-test-pod -n $NAMESPACE --timeout=60s
echo "✅ Pod 준비 완료"
echo ""

# 12. 정리
rm -f /tmp/trust-policy.json /tmp/s3-policy.json /tmp/serviceaccount.yaml /tmp/test-pod.yaml

echo "=== IRSA 생성 완료 ==="
echo ""
echo "다음 명령어로 테스트하세요:"
echo "  kubectl exec -it s3-test-pod -n $NAMESPACE -- aws s3 ls"
echo ""
echo "환경변수 확인:"
echo "  kubectl exec s3-test-pod -n $NAMESPACE -- env | grep AWS"
echo ""
echo "Role 확인:"
echo "  kubectl exec s3-test-pod -n $NAMESPACE -- aws sts get-caller-identity"
