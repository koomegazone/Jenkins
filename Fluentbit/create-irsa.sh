#!/bin/bash
set -e

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
NAMESPACE="kube-system"
SERVICE_ACCOUNT="fluent-bit"

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

echo "=== Fluent Bit IAM Role 생성 ==="
echo "Cluster: $CLUSTER_NAME"
echo "Cluster Type: $CLUSTER_TYPE"
echo "Region: $REGION"
echo "Account ID: $ACCOUNT_ID"
echo "Policy Name: $POLICY_NAME"
echo "Role Name: $ROLE_NAME"
echo ""

# 1. OIDC Provider 확인
echo "1. OIDC Provider 확인 중..."
OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")
echo "OIDC Provider: $OIDC_PROVIDER"
echo ""

# 2. IAM Policy 생성
echo "2. IAM Policy 생성 중..."
cat > fluent-bit-opensearch-policy-${CLUSTER_TYPE}.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "es:ESHttpPost",
        "es:ESHttpPut",
        "es:ESHttpGet"
      ],
      "Resource": [
        "arn:aws:es:REGION:ACCOUNT_ID:domain/*"
      ]
    }
  ]
}
EOF

# 변수 치환
sed -i.bak "s/REGION/${REGION}/g" fluent-bit-opensearch-policy-${CLUSTER_TYPE}.json
sed -i.bak "s/ACCOUNT_ID/${ACCOUNT_ID}/g" fluent-bit-opensearch-policy-${CLUSTER_TYPE}.json
rm -f fluent-bit-opensearch-policy-${CLUSTER_TYPE}.json.bak

echo "Policy 파일 내용:"
cat fluent-bit-opensearch-policy-${CLUSTER_TYPE}.json
echo ""

POLICY_ARN=$(aws iam create-policy \
  --policy-name $POLICY_NAME \
  --policy-document file://fluent-bit-opensearch-policy-${CLUSTER_TYPE}.json \
  --query 'Policy.Arn' \
  --output text 2>&1)

if [ $? -ne 0 ]; then
  echo "Policy 생성 실패, 기존 Policy 확인 중..."
  POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)
  if [ -z "$POLICY_ARN" ]; then
    echo "Error: Policy를 생성하거나 찾을 수 없습니다."
    echo "Error message: $POLICY_ARN"
    exit 1
  fi
fi

echo "Policy ARN: $POLICY_ARN"
echo ""

# 3. Trust Policy 생성
echo "3. Trust Policy 생성 중..."
cat > trust-policy-${CLUSTER_TYPE}.json <<EOF
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
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# 4. IAM Role 생성
echo "4. IAM Role 생성 중..."
ROLE_ARN=$(aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://trust-policy-${CLUSTER_TYPE}.json \
  --description "Fluent Bit role for OpenSearch access (${CLUSTER_TYPE})" \
  --query 'Role.Arn' \
  --output text 2>/dev/null || \
  aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)

echo "Role ARN: $ROLE_ARN"
echo ""

# 5. Policy를 Role에 연결
echo "5. Policy를 Role에 연결 중..."
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN 2>/dev/null || echo "Policy already attached"

echo "✅ Policy 연결 완료"
echo ""

# 정리
rm -f fluent-bit-opensearch-policy-${CLUSTER_TYPE}.json trust-policy-${CLUSTER_TYPE}.json

echo "=== 완료 ==="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Role ARN: $ROLE_ARN"
echo ""
echo "Helm values.yaml에 다음 설정 추가:"
echo ""
echo "serviceAccount:"
echo "  create: true"
echo "  name: $SERVICE_ACCOUNT"
echo "  annotations:"
echo "    eks.amazonaws.com/role-arn: $ROLE_ARN"
