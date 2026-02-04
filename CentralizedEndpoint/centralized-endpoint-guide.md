# AWS Centralized VPC Endpoint 구성 가이드

## 개요
Route53 Profile을 사용하여 중앙 집중식 VPC Endpoint를 구성하고, 여러 AWS 계정의 VPC에서 공유하는 방법을 설명합니다.

---

## 아키텍처

```
Hub Account (중앙)
├── VPC Endpoint (EFS, S3, EC2 등)
├── Route53 Profile
└── RAM으로 공유 →

Spoke Account (사용)
├── VPC Association
└── Centralized Endpoint 사용
```

---

## 1단계: Route53 Profile 생성 (Hub Account)

### 1.1 AWS Console에서 생성

```bash
# AWS CLI로 생성
aws route53profiles create-profile \
  --name "centralized-endpoint-profile" \
  --region ap-northeast-2
```

**Console 경로:**
- Route 53 → Profiles → Create profile
- Profile name: `centralized-endpoint-profile`
- Description: "Centralized VPC Endpoint for multi-account access"

### 1.2 Profile ID 확인

```bash
# Profile ID 저장
PROFILE_ID=$(aws route53profiles list-profiles \
  --query 'ProfileSummaries[?Name==`centralized-endpoint-profile`].Id' \
  --output text)

echo "Profile ID: $PROFILE_ID"
```

---

## 2단계: VPC Endpoint를 Route53 Profile에 연결

### 2.1 VPC Endpoint 생성 (Hub VPC)

```bash
# 변수 설정
VPC_ID="vpc-xxxxxxxxx"
SUBNET_IDS="subnet-xxxxxxxx subnet-yyyyyyyy"  # Private Subnets
SG_ID="sg-xxxxxxxxx"  # VPC Endpoint Security Group
REGION="ap-northeast-2"

# Interface Type Endpoints 생성
INTERFACE_ENDPOINTS=(
  "ec2"
  "eks"
  "eks-auth"
  "elasticfilesystem"
  "sts"
  "autoscaling"
  "guardduty-data"
  "elasticloadbalancing"
  "ecr.api"
  "ecr.dkr"
)

for endpoint in "${INTERFACE_ENDPOINTS[@]}"; do
  echo "Creating VPC Endpoint for $endpoint..."
  aws ec2 create-vpc-endpoint \
    --vpc-id $VPC_ID \
    --service-name com.amazonaws.$REGION.$endpoint \
    --vpc-endpoint-type Interface \
    --subnet-ids $SUBNET_IDS \
    --security-group-ids $SG_ID \
    --private-dns-enabled \
    --region $REGION
done

# S3 Gateway Endpoint 생성 (별도 처리)
ROUTE_TABLE_IDS="rtb-xxxxxxxx rtb-yyyyyyyy"  # Private Route Tables

echo "Creating S3 Gateway Endpoint..."
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.$REGION.s3 \
  --vpc-endpoint-type Gateway \
  --route-table-ids $ROUTE_TABLE_IDS \
  --region $REGION
```

**생성할 VPC Endpoints:**
- `com.amazonaws.ap-northeast-2.ec2` (EC2)
- `com.amazonaws.ap-northeast-2.eks` (EKS)
- `com.amazonaws.ap-northeast-2.eks-auth` (EKS Auth)
- `com.amazonaws.ap-northeast-2.elasticfilesystem` (EFS)
- `com.amazonaws.ap-northeast-2.sts` (STS)
- `com.amazonaws.ap-northeast-2.autoscaling` (Auto Scaling)
- `com.amazonaws.ap-northeast-2.guardduty-data` (GuardDuty)
- `com.amazonaws.ap-northeast-2.elasticloadbalancing` (ELB)
- `com.amazonaws.ap-northeast-2.s3` (S3 - Gateway Type)
- `com.amazonaws.ap-northeast-2.ecr.api` (ECR API)
- `com.amazonaws.ap-northeast-2.ecr.dkr` (ECR Docker)

**Security Group 설정 (VPC Endpoint용):**

```bash
# VPC Endpoint Security Group 생성
SG_ID=$(aws ec2 create-security-group \
  --group-name vpc-endpoint-sg \
  --description "Security group for VPC Endpoints" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

# Spoke VPC CIDR에서 HTTPS 트래픽 허용
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 10.0.0.0/8 \
  --region $REGION

# EFS용 NFS 포트 허용
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 2049 \
  --cidr 10.0.0.0/8 \
  --region $REGION

echo "Security Group ID: $SG_ID"
```

**Endpoint 생성 확인:**

```bash
# 생성된 모든 VPC Endpoints 확인
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[*].[VpcEndpointId,ServiceName,State]' \
  --output table \
  --region $REGION
```

### 2.2 Route53 Profile에 VPC 연결

```bash
# Hub VPC를 Profile에 연결
aws route53profiles associate-profile \
  --profile-id $PROFILE_ID \
  --resource-id vpc-xxxxxxxxx \
  --name "hub-vpc-association"
```

**Console 경로:**
- Route 53 → Profiles → [Profile 선택]
- VPC associations → Associate VPC
- VPC 선택 후 Associate

---

## 3단계: RAM으로 다른 계정에 공유 (Hub Account)

### 3.1 Resource Share 생성

```bash
# RAM Resource Share 생성
aws ram create-resource-share \
  --name "centralized-endpoint-share" \
  --resource-arns "arn:aws:route53profiles:ap-northeast-2:ACCOUNT_ID:profile/$PROFILE_ID" \
  --principals "arn:aws:organizations::ORGANIZATION_ID:account/SPOKE_ACCOUNT_ID" \
  --region ap-northeast-2
```

### 3.2 Console에서 공유

**Console 경로:**
- AWS RAM → Resource shares → Create resource share
- Name: `centralized-endpoint-share`
- Resources:
  - Resource type: `Route 53 Profiles`
  - Profile 선택
- Principals:
  - Spoke Account ID 입력 (예: `123456789012`)
- Create resource share

### 3.3 공유 확인

```bash
# Resource Share 상태 확인
aws ram get-resource-shares \
  --resource-owner SELF \
  --query 'resourceShares[?name==`centralized-endpoint-share`]'
```

---

## 4단계: Spoke Account에서 Profile 수락 및 VPC 연결

### 4.1 RAM 초대 수락 (Spoke Account)

```bash
# Spoke Account로 전환
export AWS_PROFILE=spoke-account

# 초대 확인
aws ram get-resource-share-invitations \
  --region ap-northeast-2

# 초대 수락
aws ram accept-resource-share-invitation \
  --resource-share-invitation-arn "arn:aws:ram:ap-northeast-2:HUB_ACCOUNT:resource-share-invitation/xxxxx" \
  --region ap-northeast-2
```

**Console 경로:**
- AWS RAM → Shared with me → Resource share invitations
- Invitation 선택 → Accept

### 4.2 Spoke VPC를 Route53 Profile에 연결

```bash
# Spoke VPC Association
aws route53profiles associate-profile \
  --profile-id $PROFILE_ID \
  --resource-id vpc-spoke-xxxxxxxxx \
  --name "spoke-vpc-association" \
  --region ap-northeast-2
```

**Console 경로:**
- Route 53 → Profiles → [공유된 Profile 선택]
- VPC associations → Associate VPC
- Spoke VPC 선택 후 Associate

### 4.3 연결 확인

```bash
# Association 상태 확인
aws route53profiles list-profile-associations \
  --profile-id $PROFILE_ID \
  --region ap-northeast-2
```

---

## 5단계: Spoke VPC EC2에서 DNS Lookup 테스트

### 5.1 EC2 인스턴스 접속

```bash
# Spoke VPC의 EC2에 SSH 접속
ssh -i your-key.pem ec2-user@<SPOKE_EC2_IP>
```

### 5.2 DNS Resolution 테스트

```bash
# EFS Endpoint DNS 조회
nslookup elasticfilesystem.ap-northeast-2.amazonaws.com

# 결과 예시:
# Server:         10.0.0.2
# Address:        10.0.0.2#53
#
# Non-authoritative answer:
# Name:   elasticfilesystem.ap-northeast-2.amazonaws.com
# Address: 10.1.1.100  # Hub VPC의 VPC Endpoint Private IP

# S3 Endpoint 조회
nslookup s3.ap-northeast-2.amazonaws.com

# EC2 Endpoint 조회
nslookup ec2.ap-northeast-2.amazonaws.com
```

### 5.3 연결 테스트

```bash
# EFS 마운트 테스트 (EFS ID 필요)
sudo mount -t efs -o tls fs-xxxxxxxxx:/ /mnt/efs

# 마운트 확인
df -h | grep efs
```

---

## 6단계: Spoke VPC EKS에서 EFS CSI Driver 테스트

### 6.1 EFS CSI Driver 설치

```bash
# Helm으로 EFS CSI Driver 설치
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update

helm upgrade --install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set image.repository=602401143452.dkr.ecr.ap-northeast-2.amazonaws.com/eks/aws-efs-csi-driver \
  --set controller.serviceAccount.create=true \
  --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::SPOKE_ACCOUNT:role/EKS-EFS-CSI-DriverRole"
```

### 6.2 StorageClass 생성

```yaml
# storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-xxxxxxxxx  # Hub Account의 EFS ID
  directoryPerms: "700"
```

```bash
kubectl apply -f storageclass.yaml
```

### 6.3 PVC 생성 (Dynamic Provisioning)

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi
```

```bash
kubectl apply -f pvc.yaml

# PVC 상태 확인
kubectl get pvc efs-claim
```

### 6.4 Pod에서 EFS 마운트 테스트

```yaml
# test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: efs-test-pod
spec:
  containers:
  - name: app
    image: busybox
    command: ["/bin/sh"]
    args: ["-c", "while true; do echo $(date) >> /data/test.txt; sleep 5; done"]
    volumeMounts:
    - name: efs-storage
      mountPath: /data
  volumes:
  - name: efs-storage
    persistentVolumeClaim:
      claimName: efs-claim
```

```bash
kubectl apply -f test-pod.yaml

# Pod 상태 확인
kubectl get pod efs-test-pod

# 로그 확인
kubectl logs efs-test-pod

# 파일 확인
kubectl exec -it efs-test-pod -- cat /data/test.txt
```

### 6.5 다중 Pod에서 동시 접근 테스트

```yaml
# multi-pod-test.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: efs-multi-test
spec:
  replicas: 3
  selector:
    matchLabels:
      app: efs-test
  template:
    metadata:
      labels:
        app: efs-test
    spec:
      containers:
      - name: app
        image: nginx
        volumeMounts:
        - name: efs-storage
          mountPath: /usr/share/nginx/html
      volumes:
      - name: efs-storage
        persistentVolumeClaim:
          claimName: efs-claim
```

```bash
kubectl apply -f multi-pod-test.yaml

# 모든 Pod가 동일한 EFS 볼륨 공유 확인
kubectl get pods -l app=efs-test
```

---

## 검증 체크리스트

### Hub Account
- [ ] Route53 Profile 생성 완료
- [ ] VPC Endpoint 생성 완료 (EFS, S3, EC2 등)
- [ ] Profile에 Hub VPC 연결 완료
- [ ] RAM Resource Share 생성 및 공유 완료

### Spoke Account
- [ ] RAM 초대 수락 완료
- [ ] Spoke VPC를 Profile에 연결 완료
- [ ] EC2에서 DNS Lookup 성공
- [ ] EC2에서 EFS 마운트 성공
- [ ] EKS에 EFS CSI Driver 설치 완료
- [ ] PVC Dynamic Provisioning 성공
- [ ] Pod에서 EFS 마운트 및 읽기/쓰기 성공

---

## 트러블슈팅

### DNS Resolution 실패
```bash
# VPC DNS 설정 확인
aws ec2 describe-vpc-attribute \
  --vpc-id vpc-xxxxxxxxx \
  --attribute enableDnsHostnames

aws ec2 describe-vpc-attribute \
  --vpc-id vpc-xxxxxxxxx \
  --attribute enableDnsSupport

# 둘 다 true여야 함
```

### EFS 마운트 실패
```bash
# Security Group 확인
# Hub VPC Endpoint의 SG에서 Spoke VPC CIDR 허용 필요
# Inbound: NFS (2049) from Spoke VPC CIDR

# EFS Mount Target 확인
aws efs describe-mount-targets --file-system-id fs-xxxxxxxxx
```

### EKS CSI Driver 오류
```bash
# CSI Driver Pod 로그 확인
kubectl logs -n kube-system -l app=efs-csi-controller

# IRSA 권한 확인
aws iam get-role --role-name EKS-EFS-CSI-DriverRole
```

---

## 비용 최적화 팁

1. **VPC Endpoint 통합**: 여러 서비스를 하나의 Hub VPC에 집중
2. **Data Transfer 비용**: 같은 리전 내에서만 사용 (Cross-Region은 비용 증가)
3. **Endpoint 개수 최소화**: 필요한 서비스만 생성

---

## 참고 자료

- [AWS Route 53 Profiles Documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/profiles.html)
- [AWS RAM User Guide](https://docs.aws.amazon.com/ram/latest/userguide/what-is.html)
- [EFS CSI Driver GitHub](https://github.com/kubernetes-sigs/aws-efs-csi-driver)
