#!/bin/bash
set -e

# 변수 설정
REGION="ap-northeast-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
NAMESPACE="kube-system"
SERVICE_ACCOUNT="fluent-bit"

# 클러스터 목록 가져오기
echo "=== EKS 클러스터 조회 중 ==="
CLUSTERS=$(aws eks list-clusters --region $REGION --query 'clusters[]' --output text)

if [ -z "$CLUSTERS" ]; then
  echo "Error: 리전 $REGION 에서 EKS 클러스터를 찾을 수 없습니다."
  exit 1
fi

# 클러스터 배열로 변환
CLUSTER_ARRAY=($CLUSTERS)
CLUSTER_COUNT=${#CLUSTER_ARRAY[@]}

# 클러스터 선택
if [ $CLUSTER_COUNT -eq 1 ]; then
  CLUSTER_NAME="${CLUSTER_ARRAY[0]}"
  echo "클러스터 자동 선택: $CLUSTER_NAME"
else
  echo "발견된 클러스터 목록:"
  for i in "${!CLUSTER_ARRAY[@]}"; do
    echo "  $((i+1)). ${CLUSTER_ARRAY[$i]}"
  done
  echo ""
  
  # 명령줄 인자로 클러스터 이름이 제공된 경우
  if [ -n "$1" ]; then
    CLUSTER_NAME="$1"
    # 클러스터 이름이 목록에 있는지 확인
    if [[ ! " ${CLUSTER_ARRAY[@]} " =~ " ${CLUSTER_NAME} " ]]; then
      echo "Error: 클러스터 '$CLUSTER_NAME'을 찾을 수 없습니다."
      exit 1
    fi
    echo "선택된 클러스터: $CLUSTER_NAME"
  else
    read -p "클러스터 번호를 선택하세요 (1-$CLUSTER_COUNT): " SELECTION
    
    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt $CLUSTER_COUNT ]; then
      echo "Error: 잘못된 선택입니다."
      exit 1
    fi
    
    CLUSTER_NAME="${CLUSTER_ARRAY[$((SELECTION-1))]}"
    echo "선택된 클러스터: $CLUSTER_NAME"
  fi
fi

echo ""

# 클러스터 이름 기반으로 Policy와 Role 이름 생성
# 예시:
#   prism-q-an2-eks-cluster-front -> prism-q-an2-pol-eks-irsa-fluent-bit-front
#   cmas-q-an2-eks-cluster        -> cmas-q-an2-pol-eks-irsa-fluent-bit
#   my-eks-test                   -> my-pol-eks-irsa-fluent-bit-test

# 클러스터 이름에서 패턴 추출
# 패턴 1: {prefix}-eks-cluster-{suffix} (예: prism-q-an2-eks-cluster-front)
# 패턴 2: {prefix}-eks-cluster (예: cmas-q-an2-eks-cluster)
# 패턴 3: {prefix}-eks-{suffix} (예: my-eks-test)
if [[ $CLUSTER_NAME =~ ^(.+)-eks-cluster-(.+)$ ]]; then
  # 패턴 1: suffix가 있는 경우
  PREFIX="${BASH_REMATCH[1]}"
  SUFFIX="${BASH_REMATCH[2]}"
  POLICY_NAME="${PREFIX}-pol-eks-irsa-fluent-bit-${SUFFIX}"
  ROLE_NAME="${PREFIX}-role-eks-irsa-fluent-bit-${SUFFIX}"
elif [[ $CLUSTER_NAME =~ ^(.+)-eks-cluster$ ]]; then
  # 패턴 2: suffix가 없는 경우
  PREFIX="${BASH_REMATCH[1]}"
  POLICY_NAME="${PREFIX}-pol-eks-irsa-fluent-bit"
  ROLE_NAME="${PREFIX}-role-eks-irsa-fluent-bit"
elif [[ $CLUSTER_NAME =~ ^(.+)-eks-(.+)$ ]]; then
  # 패턴 3: eks-cluster가 아닌 경우
  PREFIX="${BASH_REMATCH[1]}"
  SUFFIX="${BASH_REMATCH[2]}"
  POLICY_NAME="${PREFIX}-pol-eks-irsa-fluent-bit-${SUFFIX}"
  ROLE_NAME="${PREFIX}-role-eks-irsa-fluent-bit-${SUFFIX}"
else
  # 패턴이 맞지 않으면 클러스터 이름 전체를 사용
  POLICY_NAME="pol-eks-irsa-fluent-bit-${CLUSTER_NAME}"
  ROLE_NAME="role-eks-irsa-fluent-bit-${CLUSTER_NAME}"
fi

echo "=== Fluent Bit IAM Role 생성 ==="
echo "Cluster: $CLUSTER_NAME"
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
cat > fluent-bit-opensearch-policy.json <<EOF
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
        "arn:aws:es:${REGION}:${ACCOUNT_ID}:domain/*"
      ]
    }
  ]
}
EOF

echo "Policy 파일 내용:"
cat fluent-bit-opensearch-policy.json
echo ""

POLICY_ARN=$(aws iam create-policy \
  --policy-name $POLICY_NAME \
  --policy-document file://fluent-bit-opensearch-policy.json \
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
cat > trust-policy.json <<EOF
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
  --assume-role-policy-document file://trust-policy.json \
  --description "Fluent Bit role for OpenSearch access (${CLUSTER_NAME})" \
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
rm -f fluent-bit-opensearch-policy.json trust-policy.json

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
