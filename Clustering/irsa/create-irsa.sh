#!/bin/bash

# IRSA 생성 스크립트 (eksctl 없이)
# S3 Full Access용 - 2개 Role 생성

set -e

# 변수 설정
REGION="${REGION:-ap-northeast-2}"
NAMESPACE="${NAMESPACE:-default}"
PROFILE="cmasq"

# Cluster Name 자동 설정 (aws eks list-clusters)
echo "=== Cluster Name 자동 설정 ==="
CLUSTER_NAME=$(aws eks list-clusters --region $REGION --profile $PROFILE --query "clusters[0]" --output text)

if [ -z "$CLUSTER_NAME" ] || [ "$CLUSTER_NAME" = "None" ]; then
  echo "❌ Error: EKS 클러스터를 찾을 수 없습니다."
  exit 1
fi

# Role 목록
ROLE_NAMES=(
  "cmas-q-an2-role-eks-irsa-mas-java"
  "cmas-q-an2-role-eks-irsa-mas-react"
)

echo "=== IRSA 생성 시작 ==="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Namespace: $NAMESPACE"
echo "Roles: ${ROLE_NAMES[*]}"
echo ""

# 1. OIDC Provider URL 가져오기
echo "Step 1: OIDC Provider 확인..."
OIDC_URL=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --profile $PROFILE \
  --query "cluster.identity.oidc.issuer" --output text)

if [ -z "$OIDC_URL" ]; then
  echo "❌ Error: OIDC URL을 가져올 수 없습니다."
  exit 1
fi

OIDC_ID=$(echo $OIDC_URL | sed 's|https://||')
OIDC_PROVIDER_ID=$(echo $OIDC_URL | awk -F'/' '{print $NF}')

echo "OIDC URL: $OIDC_URL"
echo "OIDC ID: $OIDC_PROVIDER_ID"
echo ""

# 2. AWS Account ID 가져오기
echo "Step 2: AWS Account ID 확인..."
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query Account --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# 3. OIDC Provider 존재 확인
echo "Step 3: OIDC Provider 존재 확인..."
OIDC_EXISTS=$(aws iam list-open-id-connect-providers --profile $PROFILE \
  --query "OpenIDConnectProviderList[?contains(Arn, '$OIDC_PROVIDER_ID')].Arn" \
  --output text)

if [ -z "$OIDC_EXISTS" ]; then
  echo "⚠️  OIDC Provider가 없습니다. 생성 중..."

  aws iam create-open-id-connect-provider --profile $PROFILE \
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

# 4. 각 Role 생성
for ROLE_NAME in "${ROLE_NAMES[@]}"; do
  echo "============================================"
  echo "=== Role 생성: $ROLE_NAME ==="
  echo "============================================"

  # 4-1. Trust Policy 생성
  echo "  Trust Policy 생성..."
  cat > /tmp/trust-policy-${ROLE_NAME}.json <<EOF
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
        "${OIDC_ID}:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "${OIDC_ID}:sub": "system:serviceaccount:${NAMESPACE}:*"
      }
    }
  }]
}
EOF

  echo "  ✅ Trust Policy 생성 완료"

  # 4-2. IAM Role 생성
  echo "  IAM Role 생성..."
  if ! aws iam get-role --role-name $ROLE_NAME --profile $PROFILE > /dev/null 2>&1; then
    aws iam create-role --profile $PROFILE \
      --role-name $ROLE_NAME \
      --assume-role-policy-document file:///tmp/trust-policy-${ROLE_NAME}.json \
      --description "IRSA Role for $ROLE_NAME"

    echo "  ✅ Role 생성 완료"
  else
    echo "  ⚠️  Role이 이미 존재합니다. Trust Policy 업데이트 중..."
    aws iam update-assume-role-policy --profile $PROFILE \
      --role-name $ROLE_NAME \
      --policy-document file:///tmp/trust-policy-${ROLE_NAME}.json
    echo "  ✅ Trust Policy 업데이트 완료"
  fi

  # 4-3. S3 Full Access Policy 연결
  echo "  S3 Full Access Policy 연결..."
  aws iam attach-role-policy --profile $PROFILE \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
  echo "  ✅ S3 Full Access Policy 연결 완료"
  echo ""

  # 임시 파일 정리
  rm -f /tmp/trust-policy-${ROLE_NAME}.json
done

echo "=== IRSA 생성 완료 ==="
echo ""
echo "생성된 Role 목록:"
for ROLE_NAME in "${ROLE_NAMES[@]}"; do
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
  echo "  - $ROLE_NAME ($ROLE_ARN)"
done
echo ""
echo "Helm chart의 ServiceAccount에 다음 annotation을 추가하세요:"
echo "  eks.amazonaws.com/role-arn: arn:aws:iam::${ACCOUNT_ID}:role/<ROLE_NAME>"
