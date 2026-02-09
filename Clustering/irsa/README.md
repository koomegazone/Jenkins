# IRSA (IAM Roles for Service Accounts) 테스트

eksctl 없이 AWS CLI와 kubectl만으로 IRSA를 생성하고 테스트하는 스크립트입니다.

## 사전 요구사항

- AWS CLI 설치 및 설정
- kubectl 설치 및 EKS 클러스터 접근 권한
- EKS 클러스터 존재
- IAM 권한 (Role, Policy 생성 권한)

## 파일 구성

```
irsa/
├── create-irsa.sh    # IRSA 생성 스크립트
├── test-irsa.sh      # IRSA 테스트 스크립트
├── cleanup-irsa.sh   # IRSA 정리 스크립트
└── README.md         # 이 파일
```

## 사용 방법

### 1. 실행 권한 부여

```bash
chmod +x create-irsa.sh test-irsa.sh cleanup-irsa.sh
```

### 2. IRSA 생성

```bash
# 기본 설정으로 생성
./create-irsa.sh

# 또는 환경변수로 커스터마이징
CLUSTER_NAME=my-cluster \
REGION=ap-northeast-2 \
NAMESPACE=default \
SERVICE_ACCOUNT=s3-test-sa \
ROLE_NAME=S3TestIRSARole \
./create-irsa.sh
```

### 3. IRSA 테스트

```bash
# 자동 테스트 실행
./test-irsa.sh

# 또는 수동 테스트
kubectl exec -it s3-test-pod -n default -- aws s3 ls
kubectl exec s3-test-pod -n default -- aws sts get-caller-identity
```

### 4. IRSA 정리

```bash
# 생성한 리소스 삭제
./cleanup-irsa.sh
```

## 생성되는 리소스

### AWS 리소스
- IAM Policy: `S3TestPolicy` (S3 읽기 권한)
- IAM Role: `S3TestIRSARole` (IRSA Role)
- OIDC Provider: (이미 없는 경우 생성)

### Kubernetes 리소스
- Namespace: `default` (또는 지정한 namespace)
- ServiceAccount: `s3-test-sa`
- Pod: `s3-test-pod` (테스트용)

## 테스트 명령어

### 환경변수 확인
```bash
kubectl exec s3-test-pod -n default -- env | grep AWS

# 출력 예상:
# AWS_ROLE_ARN=arn:aws:iam::123456789012:role/S3TestIRSARole
# AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

### IRSA Token 확인
```bash
kubectl exec s3-test-pod -n default -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

### 현재 IAM Role 확인
```bash
kubectl exec s3-test-pod -n default -- aws sts get-caller-identity

# IRSA 사용 시:
# "Arn": "arn:aws:sts::123456789012:assumed-role/S3TestIRSARole/botocore-session-XXX"

# Node Role 사용 시 (문제!):
# "Arn": "arn:aws:sts::123456789012:assumed-role/EKSNodeRole/i-XXXXXXXXX"
```

### S3 버킷 목록 조회
```bash
kubectl exec s3-test-pod -n default -- aws s3 ls
```

### 특정 S3 버킷 조회
```bash
kubectl exec s3-test-pod -n default -- aws s3 ls s3://your-bucket-name/
```

## 트러블슈팅

### IRSA가 동작하지 않을 때

#### 1. ServiceAccount annotation 확인
```bash
kubectl get sa s3-test-sa -n default -o yaml | grep -A 1 annotations
```

#### 2. Pod ServiceAccount 확인
```bash
kubectl get pod s3-test-pod -n default -o yaml | grep serviceAccountName
```

#### 3. 환경변수 확인
```bash
kubectl exec s3-test-pod -n default -- env | grep AWS_ROLE_ARN
```

#### 4. Token 파일 확인
```bash
kubectl exec s3-test-pod -n default -- ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/
```

#### 5. Trust Policy 확인
```bash
aws iam get-role --role-name S3TestIRSARole \
  --query 'Role.AssumeRolePolicyDocument'
```

#### 6. OIDC Provider 확인
```bash
# 클러스터 OIDC Issuer
aws eks describe-cluster --name my-cluster \
  --query "cluster.identity.oidc.issuer" \
  --output text

# IAM OIDC Provider
aws iam list-open-id-connect-providers
```

### 권한 오류 발생 시

#### AccessDenied 오류
```bash
# IAM Policy 확인
aws iam get-policy --policy-arn arn:aws:iam::123456789012:policy/S3TestPolicy

# Policy가 Role에 연결되었는지 확인
aws iam list-attached-role-policies --role-name S3TestIRSARole
```

#### AssumeRoleWithWebIdentity 실패
```bash
# Trust Policy의 OIDC Provider ID 확인
# Namespace와 ServiceAccount 이름 확인
# aud 값 확인 (sts.amazonaws.com)
```

## 환경변수 설정

```bash
# 클러스터 이름
export CLUSTER_NAME=my-cluster

# 리전
export REGION=ap-northeast-2

# Namespace
export NAMESPACE=default

# ServiceAccount 이름
export SERVICE_ACCOUNT=s3-test-sa

# IAM Role 이름
export ROLE_NAME=S3TestIRSARole

# IAM Policy 이름
export POLICY_NAME=S3TestPolicy
```

## 참고사항

- OIDC Provider는 클러스터당 1개만 필요합니다
- 여러 IRSA가 같은 OIDC Provider를 공유할 수 있습니다
- ServiceAccount는 Namespace별로 고유해야 합니다
- IAM Role의 Trust Policy에서 Namespace와 ServiceAccount 이름이 정확해야 합니다

## 추가 테스트

### 다른 AWS 서비스 테스트

#### DynamoDB
```bash
kubectl exec s3-test-pod -n default -- aws dynamodb list-tables
```

#### Secrets Manager
```bash
kubectl exec s3-test-pod -n default -- aws secretsmanager list-secrets
```

#### ECR
```bash
kubectl exec s3-test-pod -n default -- aws ecr describe-repositories
```

권한이 필요한 경우 IAM Policy에 해당 권한을 추가하세요.

## 정리

테스트 완료 후 반드시 정리하세요:

```bash
./cleanup-irsa.sh
```
