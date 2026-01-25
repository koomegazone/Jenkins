#!/bin/bash
set -e

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

echo "=== PRISM Java Application IAM Role 생성 ==="
echo "Cluster: $CLUSTER_NAME"
echo "Cluster Type: $CLUSTER_TYPE"
echo "App Name: $APP_NAME"
echo "Region: $REGION"
echo "Account ID: $ACCOUNT_ID"
echo "Namespace: $NAMESPACE"
echo "Service Account: $SERVICE_ACCOUNT"
echo "Role Name: $ROLE_NAME"
echo ""

# 1. OIDC Provider 확인
echo "1. OIDC Provider 확인 중..."
OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")
echo "OIDC Provider: $OIDC_PROVIDER"
echo ""

# 2. 인라인 Policy JSON 생성
echo "2. 인라인 Policy JSON 생성 중..."
cat > ${APP_NAME}-kms-secretmanager-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VisualEditor0",
      "Effect": "Allow",
      "Action": [
        "kms:GenerateRandom",
        "kms:ListRetirableGrants",
        "secretsmanager:BatchGetSecretValue",
        "kms:CreateCustomKeyStore",
        "secretsmanager:GetRandomPassword",
        "kms:DescribeCustomKeyStores",
        "kms:ListKeys",
        "kms:DeleteCustomKeyStore",
        "kms:UpdateCustomKeyStore",
        "kms:ListAliases",
        "kms:DisconnectCustomKeyStore",
        "kms:CreateKey",
        "kms:ConnectCustomKeyStore",
        "secretsmanager:ListSecrets"
      ],
      "Resource": "*"
    },
    {
      "Sid": "VisualEditor1",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:*",
        "kms:*"
      ],
      "Resource": [
        "arn:aws:kms:${REGION}:${ACCOUNT_ID}:key/*",
        "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:*"
      ]
    }
  ]
}
EOF

echo "인라인 Policy 파일 내용:"
cat ${APP_NAME}-kms-secretmanager-policy.json
echo ""

# 3. Trust Policy 생성
echo "3. Trust Policy 생성 중..."
cat > ${APP_NAME}-trust-policy.json <<EOF
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
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}"
        }
      }
    }
  ]
}
EOF

echo "Trust Policy 파일 내용:"
cat ${APP_NAME}-trust-policy.json
echo ""

# 4. IAM Role 생성
echo "4. IAM Role 생성 중..."
ROLE_ARN=$(aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://${APP_NAME}-trust-policy.json \
  --description "PRISM ${APP_NAME} role for AWS resource access" \
  --query 'Role.Arn' \
  --output text 2>/dev/null || \
  aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)

echo "Role ARN: $ROLE_ARN"
echo ""

# 5. AWS 관리형 정책 연결 - S3FullAccess
echo "5-1. S3FullAccess 정책 연결 중..."
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || echo "S3FullAccess already attached"

echo "✅ S3FullAccess 연결 완료"
echo ""

# 6. AWS 관리형 정책 연결 - AmazonAPIGatewayAdministrator
echo "5-2. AmazonAPIGatewayAdministrator 정책 연결 중..."
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator 2>/dev/null || echo "AmazonAPIGatewayAdministrator already attached"

echo "✅ AmazonAPIGatewayAdministrator 연결 완료"
echo ""

# 7. 인라인 정책 연결
echo "5-3. 인라인 정책 연결 중..."
aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name $INLINE_POLICY_NAME \
  --policy-document file://${APP_NAME}-kms-secretmanager-policy.json

echo "✅ 인라인 정책 연결 완료"
echo ""

# 정리
rm -f ${APP_NAME}-kms-secretmanager-policy.json ${APP_NAME}-trust-policy.json

echo "=== 완료 ==="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "App Name: $APP_NAME"
echo "Role ARN: $ROLE_ARN"
echo "Namespace: $NAMESPACE"
echo "Service Account: $SERVICE_ACCOUNT"
echo ""
echo "Helm values.yaml에 다음 설정 추가:"
echo ""
echo "serviceAccount:"
echo "  create: true"
echo "  name: $SERVICE_ACCOUNT"
echo "  annotations:"
echo "    eks.amazonaws.com/role-arn: $ROLE_ARN"
