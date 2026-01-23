#!/bin/bash

# EKS 클러스터 생성 전 사전 리소스 생성 스크립트
# 사용법: ./eks-pre-setup.sh <서비스명> <환경>
# 예시: ./eks-pre-setup.sh prism prd

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 파라미터 체크
if [ $# -ne 2 ]; then
    echo -e "${RED}사용법: $0 <서비스명> <환경>${NC}"
    echo "예시: $0 prism prd"
    echo "환경: prd, stg, dev 중 하나"
    exit 1
fi

SERVICE_NAME=$1
ENV=$2
REGION="an2"  # ap-northeast-2

# 환경 검증
if [[ ! "$ENV" =~ ^(prd|stg|dev|q)$ ]]; then
    echo -e "${RED}환경은 prd, stg, dev, q 중 하나여야 합니다.${NC}"
    exit 1
fi

# 네이밍 규칙
PREFIX="${SERVICE_NAME}-${ENV}-${REGION}"

# 클러스터명
CLUSTER_FRONT="${PREFIX}-eks-cluster-front"
CLUSTER_BACK="${PREFIX}-eks-cluster-back"

# 노드그룹명
NG_FRONT_APP="${PREFIX}-ng-front-app"
NG_FRONT_MGMT="${PREFIX}-ng-front-mgmt"
NG_BACK_APP="${PREFIX}-ng-back-app"
NG_BACK_MGMT="${PREFIX}-ng-back-mgmt"

# IAM Role명
ROLE_CLUSTER_FRONT="${PREFIX}-role-eks-cluster-front"
ROLE_CLUSTER_BACK="${PREFIX}-role-eks-cluster-back"
ROLE_NODE_FRONT_APP="${PREFIX}-role-eks-node-front-app"
ROLE_NODE_BACK_APP="${PREFIX}-role-eks-node-back-app"
ROLE_NODE_FRONT_MGMT="${PREFIX}-role-eks-node-front-mgmt"
ROLE_NODE_BACK_MGMT="${PREFIX}-role-eks-node-back-mgmt"

# 보안그룹명
SG_CLUSTER_FRONT="${PREFIX}-sg-eks-cluster-front"
SG_CLUSTER_BACK="${PREFIX}-sg-eks-cluster-back"
SG_NODE_FRONT_APP="${PREFIX}-sg-eks-node-front-app"
SG_NODE_BACK_APP="${PREFIX}-sg-eks-node-back-app"
SG_NODE_FRONT_MGMT="${PREFIX}-sg-eks-node-front-mgmt"
SG_NODE_BACK_MGMT="${PREFIX}-sg-eks-node-back-mgmt"

echo "=========================================="
echo "  EKS 사전 리소스 생성 스크립트"
echo "=========================================="
echo ""
echo "서비스명: ${SERVICE_NAME}"
echo "환경: ${ENV}"
echo "리전: ap-northeast-2"
echo ""

# VPC ID 입력 받기
read -p "VPC ID를 입력하세요: " VPC_ID

if [ -z "$VPC_ID" ]; then
    echo -e "${RED}VPC ID는 필수입니다.${NC}"
    exit 1
fi

# VPC 존재 확인
if ! aws ec2 describe-vpcs --vpc-ids $VPC_ID --region ap-northeast-2 &>/dev/null; then
    echo -e "${RED}VPC ID가 존재하지 않습니다: $VPC_ID${NC}"
    exit 1
fi

echo -e "${GREEN}✓ VPC 확인 완료: $VPC_ID${NC}"
echo ""

# 생성할 리소스 확인
echo "=========================================="
echo "  생성할 리소스 목록"
echo "=========================================="
echo ""
echo -e "${BLUE}[클러스터 IAM Role]${NC}"
echo "  - $ROLE_CLUSTER_FRONT"
echo "  - $ROLE_CLUSTER_BACK"
echo ""
echo -e "${BLUE}[노드 IAM Role]${NC}"
echo "  - $ROLE_NODE_FRONT_APP"
echo "  - $ROLE_NODE_BACK_APP"
echo "  - $ROLE_NODE_FRONT_MGMT"
echo "  - $ROLE_NODE_BACK_MGMT"
echo ""
echo -e "${BLUE}[클러스터 보안그룹]${NC}"
echo "  - $SG_CLUSTER_FRONT"
echo "  - $SG_CLUSTER_BACK"
echo ""
echo -e "${BLUE}[노드 보안그룹]${NC}"
echo "  - $SG_NODE_FRONT_APP"
echo "  - $SG_NODE_BACK_APP"
echo "  - $SG_NODE_FRONT_MGMT"
echo "  - $SG_NODE_BACK_MGMT"
echo ""

read -p "위 리소스를 생성하시겠습니까? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""
echo "=========================================="
echo "  1. IAM Role 생성"
echo "=========================================="
echo ""

# EKS Cluster Trust Policy
cat > /tmp/eks-cluster-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# EKS Node Trust Policy
cat > /tmp/eks-node-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 클러스터 IAM Role 생성 함수
create_cluster_role() {
    local role_name=$1
    echo -e "${YELLOW}클러스터 IAM Role 생성: $role_name${NC}"
    
    if aws iam get-role --role-name $role_name &>/dev/null; then
        echo -e "${YELLOW}  ⚠ 이미 존재합니다. 스킵${NC}"
    else
        aws iam create-role \
            --role-name $role_name \
            --assume-role-policy-document file:///tmp/eks-cluster-trust-policy.json \
            --tags Key=Name,Value=$role_name Key=Service,Value=$SERVICE_NAME Key=Environment,Value=$ENV
        
        aws iam attach-role-policy \
            --role-name $role_name \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
        
        echo -e "${GREEN}  ✓ 생성 완료${NC}"
    fi
}

# 노드 IAM Role 생성 함수
create_node_role() {
    local role_name=$1
    echo -e "${YELLOW}노드 IAM Role 생성: $role_name${NC}"
    
    if aws iam get-role --role-name $role_name &>/dev/null; then
        echo -e "${YELLOW}  ⚠ 이미 존재합니다. 스킵${NC}"
    else
        aws iam create-role \
            --role-name $role_name \
            --assume-role-policy-document file:///tmp/eks-node-trust-policy.json \
            --tags Key=Name,Value=$role_name Key=Service,Value=$SERVICE_NAME Key=Environment,Value=$ENV
        
        # 필수 정책 연결
        aws iam attach-role-policy \
            --role-name $role_name \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        
        aws iam attach-role-policy \
            --role-name $role_name \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        
        aws iam attach-role-policy \
            --role-name $role_name \
            --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        
        aws iam attach-role-policy \
            --role-name $role_name \
            --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
        
        echo -e "${GREEN}  ✓ 생성 완료${NC}"
    fi
}

# 클러스터 Role 생성
create_cluster_role $ROLE_CLUSTER_FRONT
create_cluster_role $ROLE_CLUSTER_BACK

# 노드 Role 생성
create_node_role $ROLE_NODE_FRONT_APP
create_node_role $ROLE_NODE_BACK_APP
create_node_role $ROLE_NODE_FRONT_MGMT
create_node_role $ROLE_NODE_BACK_MGMT

echo ""
echo "=========================================="
echo "  2. 보안그룹 생성"
echo "=========================================="
echo ""

# 보안그룹 생성 함수
create_security_group() {
    local sg_name=$1
    local description=$2
    
    echo -e "${YELLOW}보안그룹 생성: $sg_name${NC}"
    
    # 이미 존재하는지 확인
    existing_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_name" "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
    
    if [ "$existing_sg" != "None" ] && [ ! -z "$existing_sg" ]; then
        echo -e "${YELLOW}  ⚠ 이미 존재합니다: $existing_sg${NC}"
        echo $existing_sg
    else
        sg_id=$(aws ec2 create-security-group \
            --group-name $sg_name \
            --description "$description" \
            --vpc-id $VPC_ID \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$sg_name},{Key=Service,Value=$SERVICE_NAME},{Key=Environment,Value=$ENV}]" \
            --query 'GroupId' --output text)
        
        echo -e "${GREEN}  ✓ 생성 완료: $sg_id${NC}"
        echo $sg_id
    fi
}

# 클러스터 보안그룹 생성
SG_CLUSTER_FRONT_ID=$(create_security_group $SG_CLUSTER_FRONT "EKS Cluster Security Group - Front")
SG_CLUSTER_BACK_ID=$(create_security_group $SG_CLUSTER_BACK "EKS Cluster Security Group - Back")

# 노드 보안그룹 생성
SG_NODE_FRONT_APP_ID=$(create_security_group $SG_NODE_FRONT_APP "EKS Node Security Group - Front App")
SG_NODE_BACK_APP_ID=$(create_security_group $SG_NODE_BACK_APP "EKS Node Security Group - Back App")
SG_NODE_FRONT_MGMT_ID=$(create_security_group $SG_NODE_FRONT_MGMT "EKS Node Security Group - Front Mgmt")
SG_NODE_BACK_MGMT_ID=$(create_security_group $SG_NODE_BACK_MGMT "EKS Node Security Group - Back Mgmt")

echo ""
echo "=========================================="
echo "  3. 보안그룹 규칙 설정"
echo "=========================================="
echo ""

# 보안그룹 규칙 추가 함수
add_sg_rule() {
    local sg_id=$1
    local direction=$2  # ingress or egress
    local protocol=$3
    local port=$4
    local source=$5
    local description=$6
    
    if [ "$direction" == "ingress" ]; then
        if [ "$protocol" == "-1" ]; then
            aws ec2 authorize-security-group-ingress \
                --group-id $sg_id \
                --ip-permissions IpProtocol=-1,UserIdGroupPairs="[{GroupId=$source,Description='$description'}]" \
                2>/dev/null || echo -e "${YELLOW}    규칙이 이미 존재합니다${NC}"
        else
            aws ec2 authorize-security-group-ingress \
                --group-id $sg_id \
                --protocol $protocol \
                --port $port \
                --source-group $source \
                --group-owner $(aws sts get-caller-identity --query Account --output text) \
                2>/dev/null || echo -e "${YELLOW}    규칙이 이미 존재합니다${NC}"
        fi
    else
        if [ "$protocol" == "-1" ]; then
            if [[ "$source" == *"/"* ]]; then
                # CIDR인 경우
                aws ec2 authorize-security-group-egress \
                    --group-id $sg_id \
                    --ip-permissions IpProtocol=-1,IpRanges="[{CidrIp=$source,Description='$description'}]" \
                    2>/dev/null || echo -e "${YELLOW}    규칙이 이미 존재합니다${NC}"
            else
                # Security Group인 경우
                aws ec2 authorize-security-group-egress \
                    --group-id $sg_id \
                    --ip-permissions IpProtocol=-1,UserIdGroupPairs="[{GroupId=$source,Description='$description'}]" \
                    2>/dev/null || echo -e "${YELLOW}    규칙이 이미 존재합니다${NC}"
            fi
        else
            if [[ "$source" == *"/"* ]]; then
                aws ec2 authorize-security-group-egress \
                    --group-id $sg_id \
                    --protocol $protocol \
                    --port $port \
                    --cidr $source \
                    2>/dev/null || echo -e "${YELLOW}    규칙이 이미 존재합니다${NC}"
            else
                aws ec2 authorize-security-group-egress \
                    --group-id $sg_id \
                    --protocol $protocol \
                    --port $port \
                    --source-group $source \
                    --group-owner $(aws sts get-caller-identity --query Account --output text) \
                    2>/dev/null || echo -e "${YELLOW}    규칙이 이미 존재합니다${NC}"
            fi
        fi
    fi
}

echo -e "${BLUE}Front Cluster 보안그룹 규칙 설정${NC}"
echo "  Cluster → Node (10250, 443)"
add_sg_rule $SG_CLUSTER_FRONT_ID egress tcp 10250 $SG_NODE_FRONT_APP_ID "To Node App - Kubelet"
add_sg_rule $SG_CLUSTER_FRONT_ID egress tcp 10250 $SG_NODE_FRONT_MGMT_ID "To Node Mgmt - Kubelet"
add_sg_rule $SG_CLUSTER_FRONT_ID egress tcp 443 $SG_NODE_FRONT_APP_ID "To Node App - Webhook"
add_sg_rule $SG_CLUSTER_FRONT_ID egress tcp 443 $SG_NODE_FRONT_MGMT_ID "To Node Mgmt - Webhook"

echo "  Node → Cluster (443)"
add_sg_rule $SG_NODE_FRONT_APP_ID egress tcp 443 $SG_CLUSTER_FRONT_ID "To Cluster API"
add_sg_rule $SG_NODE_FRONT_MGMT_ID egress tcp 443 $SG_CLUSTER_FRONT_ID "To Cluster API"
add_sg_rule $SG_CLUSTER_FRONT_ID ingress tcp 443 $SG_NODE_FRONT_APP_ID "From Node App"
add_sg_rule $SG_CLUSTER_FRONT_ID ingress tcp 443 $SG_NODE_FRONT_MGMT_ID "From Node Mgmt"

echo "  Node ↔ Node (All)"
add_sg_rule $SG_NODE_FRONT_APP_ID ingress -1 0 $SG_NODE_FRONT_APP_ID "From same SG"
add_sg_rule $SG_NODE_FRONT_APP_ID ingress -1 0 $SG_NODE_FRONT_MGMT_ID "From Mgmt Node"
add_sg_rule $SG_NODE_FRONT_MGMT_ID ingress -1 0 $SG_NODE_FRONT_APP_ID "From App Node"
add_sg_rule $SG_NODE_FRONT_MGMT_ID ingress -1 0 $SG_NODE_FRONT_MGMT_ID "From same SG"

echo "  Cluster → Node (10250, 443) Ingress"
add_sg_rule $SG_NODE_FRONT_APP_ID ingress tcp 10250 $SG_CLUSTER_FRONT_ID "From Cluster - Kubelet"
add_sg_rule $SG_NODE_FRONT_MGMT_ID ingress tcp 10250 $SG_CLUSTER_FRONT_ID "From Cluster - Kubelet"
add_sg_rule $SG_NODE_FRONT_APP_ID ingress tcp 443 $SG_CLUSTER_FRONT_ID "From Cluster - Webhook"
add_sg_rule $SG_NODE_FRONT_MGMT_ID ingress tcp 443 $SG_CLUSTER_FRONT_ID "From Cluster - Webhook"

echo "  Node → Internet (All)"
add_sg_rule $SG_NODE_FRONT_APP_ID egress -1 0 "0.0.0.0/0" "To Internet"
add_sg_rule $SG_NODE_FRONT_MGMT_ID egress -1 0 "0.0.0.0/0" "To Internet"

echo ""
echo -e "${BLUE}Back Cluster 보안그룹 규칙 설정${NC}"
echo "  Cluster → Node (10250, 443)"
add_sg_rule $SG_CLUSTER_BACK_ID egress tcp 10250 $SG_NODE_BACK_APP_ID "To Node App - Kubelet"
add_sg_rule $SG_CLUSTER_BACK_ID egress tcp 10250 $SG_NODE_BACK_MGMT_ID "To Node Mgmt - Kubelet"
add_sg_rule $SG_CLUSTER_BACK_ID egress tcp 443 $SG_NODE_BACK_APP_ID "To Node App - Webhook"
add_sg_rule $SG_CLUSTER_BACK_ID egress tcp 443 $SG_NODE_BACK_MGMT_ID "To Node Mgmt - Webhook"

echo "  Node → Cluster (443)"
add_sg_rule $SG_NODE_BACK_APP_ID egress tcp 443 $SG_CLUSTER_BACK_ID "To Cluster API"
add_sg_rule $SG_NODE_BACK_MGMT_ID egress tcp 443 $SG_CLUSTER_BACK_ID "To Cluster API"
add_sg_rule $SG_CLUSTER_BACK_ID ingress tcp 443 $SG_NODE_BACK_APP_ID "From Node App"
add_sg_rule $SG_CLUSTER_BACK_ID ingress tcp 443 $SG_NODE_BACK_MGMT_ID "From Node Mgmt"

echo "  Node ↔ Node (All)"
add_sg_rule $SG_NODE_BACK_APP_ID ingress -1 0 $SG_NODE_BACK_APP_ID "From same SG"
add_sg_rule $SG_NODE_BACK_APP_ID ingress -1 0 $SG_NODE_BACK_MGMT_ID "From Mgmt Node"
add_sg_rule $SG_NODE_BACK_MGMT_ID ingress -1 0 $SG_NODE_BACK_APP_ID "From App Node"
add_sg_rule $SG_NODE_BACK_MGMT_ID ingress -1 0 $SG_NODE_BACK_MGMT_ID "From same SG"

echo "  Cluster → Node (10250, 443) Ingress"
add_sg_rule $SG_NODE_BACK_APP_ID ingress tcp 10250 $SG_CLUSTER_BACK_ID "From Cluster - Kubelet"
add_sg_rule $SG_NODE_BACK_MGMT_ID ingress tcp 10250 $SG_CLUSTER_BACK_ID "From Cluster - Kubelet"
add_sg_rule $SG_NODE_BACK_APP_ID ingress tcp 443 $SG_CLUSTER_BACK_ID "From Cluster - Webhook"
add_sg_rule $SG_NODE_BACK_MGMT_ID ingress tcp 443 $SG_CLUSTER_BACK_ID "From Cluster - Webhook"

echo "  Node → Internet (All)"
add_sg_rule $SG_NODE_BACK_APP_ID egress -1 0 "0.0.0.0/0" "To Internet"
add_sg_rule $SG_NODE_BACK_MGMT_ID egress -1 0 "0.0.0.0/0" "To Internet"

# 임시 파일 정리
rm -f /tmp/eks-cluster-trust-policy.json /tmp/eks-node-trust-policy.json

echo ""
echo "=========================================="
echo "  생성 완료!"
echo "=========================================="
echo ""
echo -e "${GREEN}✓ 모든 리소스가 성공적으로 생성되었습니다.${NC}"
echo ""
echo -e "${BLUE}생성된 리소스 요약:${NC}"
echo ""
echo "IAM Roles:"
echo "  - $ROLE_CLUSTER_FRONT"
echo "  - $ROLE_CLUSTER_BACK"
echo "  - $ROLE_NODE_FRONT_APP"
echo "  - $ROLE_NODE_BACK_APP"
echo "  - $ROLE_NODE_FRONT_MGMT"
echo "  - $ROLE_NODE_BACK_MGMT"
echo ""
echo "Security Groups:"
echo "  - $SG_CLUSTER_FRONT ($SG_CLUSTER_FRONT_ID)"
echo "  - $SG_CLUSTER_BACK ($SG_CLUSTER_BACK_ID)"
echo "  - $SG_NODE_FRONT_APP ($SG_NODE_FRONT_APP_ID)"
echo "  - $SG_NODE_BACK_APP ($SG_NODE_BACK_APP_ID)"
echo "  - $SG_NODE_FRONT_MGMT ($SG_NODE_FRONT_MGMT_ID)"
echo "  - $SG_NODE_BACK_MGMT ($SG_NODE_BACK_MGMT_ID)"
echo ""
echo -e "${YELLOW}다음 단계:${NC}"
echo "1. eksctl을 사용하여 EKS 클러스터 생성"
echo "2. 생성된 IAM Role과 Security Group을 클러스터 설정에 사용"
echo ""
