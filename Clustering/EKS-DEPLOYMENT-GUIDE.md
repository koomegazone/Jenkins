# EKS 클러스터 배포 가이드 (AWS 콘솔 기반)

## 📋 목차
1. [Phase 0. 사전 준비](#phase-0-사전-준비)
2. [Phase 1. IAM Role 생성](#phase-1-iam-role-생성)
3. [Phase 2. EKS 클러스터 생성](#phase-2-eks-클러스터-생성)
4. [Phase 3. 로깅/암호화/Add-on 설정](#phase-3-로깅암호화add-on-설정)
5. [Phase 4. Launch Template 생성](#phase-4-launch-template-생성)
6. [Phase 5. 노드 그룹 생성](#phase-5-노드-그룹-생성)
7. [Phase 6. Workbench 설정](#phase-6-workbench-설정)

---

## Phase 0. 사전 준비

### 0.1 사전 준비 스크립트 실행

```bash
# IAM Role, Security Group 자동 생성
./Clustering/eks-pre-setup.sh prism q vpc-xxxxxxxxxxxxxxxxx
```

⏱️ **예상 소요 시간**: 약 3-5분

**생성되는 리소스:**
- IAM Role 6개 (클러스터 2개, 노드 4개)
- Security Group 6개 (클러스터 2개, 노드 4개)
- 보안그룹 규칙 자동 설정

### 0.2 필수 확인 사항

- [x] AWS 콘솔 로그인
- [x] Region 선택: `ap-northeast-2` (서울)
- [x] VPC 및 서브넷 준비 완료
- [x] KMS Key 준비 (암호화용)
- [x] S3 Bucket 준비 (userdata용)
- [x] SSH Key Pair 생성 완료

### 0.3 네이밍 규칙

```
{서비스명}-{환경}-{리전}-{리소스타입}-{용도}

예시:
- 클러스터: prism-q-an2-eks-cluster-front
- 노드그룹: prism-q-an2-ng-front-app
- IAM Role: prism-q-an2-role-eks-cluster-front
- 보안그룹: prism-q-an2-sg-eks-node-front-app
- Launch Template: prism-q-an2-lt-eks-front-node-app
```

---

## Phase 1. IAM Role 생성

### 1.1 스크립트로 자동 생성 (권장)

```bash
./Clustering/eks-pre-setup.sh prism q vpc-xxxxxxxxxxxxxxxxx
```

### 1.2 수동 생성 (콘솔)

#### 클러스터 IAM Role 생성

1. **IAM 콘솔** → **역할** → **역할 만들기**
2. **신뢰할 수 있는 엔터티 유형**: AWS 서비스
3. **사용 사례**: EKS → EKS - Cluster
4. **권한 정책**: `AmazonEKSClusterPolicy` 선택
5. **역할 이름**: 
   - `prism-q-an2-role-eks-cluster-front`
   - `prism-q-an2-role-eks-cluster-back`
6. **역할 생성** 클릭

#### 노드 IAM Role 생성

1. **IAM 콘솔** → **역할** → **역할 만들기**
2. **신뢰할 수 있는 엔터티 유형**: AWS 서비스
3. **사용 사례**: EC2
4. **권한 정책** (5개 모두 선택):
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEKS_CNI_Policy`
   - `AmazonEC2ContainerRegistryReadOnly`
   - `AmazonS3FullAccess`
   - `AmazonEC2FullAccess`
5. **역할 이름**:
   - `prism-q-an2-role-eks-node-front-app`
   - `prism-q-an2-role-eks-node-front-mgmt`
   - `prism-q-an2-role-eks-node-back-app`
   - `prism-q-an2-role-eks-node-back-mgmt`
6. **역할 생성** 클릭

---

## Phase 2. EKS 클러스터 생성

### 2.1 클러스터 기본 설정

1. **EKS 콘솔** → **클러스터** → **클러스터 생성**

2. **클러스터 구성**
   - **이름**: `prism-q-an2-eks-cluster-front` (또는 `back`)
   - **Kubernetes 버전**: `1.34`
   - **정책 업그레이드**: **추가 지원** 선택
     - 출시일로부터 26개월 지원
     - 추가 지원 기간 종료 후 자동 업그레이드
   - **클러스터 서비스 역할**: `prism-q-an2-role-eks-cluster-front`

3. **클러스터 액세스**
   - **API 및 ConfigMap** 선택
   - **EKSClusterAdminPolicy**를 workbench 역할에 추가
   - ⚠️ **주의**: 두 번 클릭해야 적용됨 (버그)

4. **암호화 설정**
   - **봉투 암호화 활성화**
   - **KMS Key 선택**: `arn:aws:kms:ap-northeast-2:617197584139:key/9xxxff7`
   - **클러스터 CMK** 사용
   - ⚠️ **EBS는 Managed EBS CMK 사용 필요**

5. **다음** 클릭

### 2.2 네트워킹 설정

1. **VPC 선택**: 기존 VPC 선택
2. **서브넷 선택**: 
   - `eks-a` (ap-northeast-2a)
   - `eks-c` (ap-northeast-2c)
3. **보안 그룹 선택**:
   - Front: `prism-q-an2-sg-eks-cluster-front`
   - Back: `prism-q-an2-sg-eks-cluster-back`
4. **클러스터 엔드포인트 액세스**: 
   - ⚠️ **프라이빗만 선택** (퍼블릭 비활성화)
5. **다음** 클릭

---

## Phase 3. 로깅/암호화/Add-on 설정

### 3.1 클러스터 로깅 설정

**모든 로그 활성화** (CloudWatch로 전송):
- [x] **API Server** 로그
- [x] **Audit** 로그
- [x] **Authenticator** 로그
- [x] **Scheduler** 로그
- [x] **Controller Manager** 로그

### 3.2 Add-on 선택

**필수 Add-on 선택** (최신 버전):

| Add-on | 버전 | 설명 |
|--------|------|------|
| `aws-ebs-csi-driver` | v1.54.0-eksbuild.1 | EBS 볼륨 관리 |
| `aws-efs-csi-driver` | v2.2.0-eksbuild.1 | EFS 파일시스템 |
| `aws-guardduty-agent` | v1.12.1-eksbuild.2 | 보안 모니터링 |
| `coredns` | v1.12.3-eksbuild.1 | DNS 서비스 |
| `eks-pod-identity-agent` | v1.3.10-eksbuild.2 | Pod Identity |
| `kube-proxy` | v1.34.0-eksbuild.2 | 네트워크 프록시 |
| `metrics-server` | v0.8.0-eksbuild.6 | 리소스 메트릭 |
| `vpc-cni` | v1.20.4-eksbuild.2 | VPC 네트워킹 |

### 3.3 클러스터 생성 완료

1. **생성** 클릭
2. **클러스터 상태**: `CREATING`
3. ⏱️ **대기 시간**: 약 10-15분
4. **클러스터 상태**: `ACTIVE` 확인

---

## Phase 4. Launch Template 생성

### 4.1 Front App 노드용 Launch Template

1. **EC2 콘솔** → **시작 템플릿** → **시작 템플릿 생성**

2. **시작 템플릿 이름**: `prism-q-an2-lt-eks-front-node-app`

3. **AMI 선택**:
   - **이름**: EKS-optimized Kubernetes node based on Amazon Linux 2023
   - **버전**: k8s: 1.34.0, containerd: 2.1.4-1.eks.amzn2023.0.1
   - **AMI ID**: `ami-06a6f3affda2f6180`

4. **인스턴스 유형**:
   - App 노드: `m6i.xlarge`
   - Mgmt 노드: `m6i.large`

5. **키 페어**: `prism-q-an2-kp-pem`
   - ⚠️ **사전 작업 필요**:
     - EKS Node SG Inbound: 22번 포트 오픈
     - Workbench SG Outbound: 22번 포트 오픈

6. **네트워크 설정**:
   - ⚠️ **서브넷**: 시작 템플릿에 포함하지 않음
   - **보안 그룹**:
     - App: `prism-q-an2-sg-eks-node-front-app`
     - Mgmt: `prism-q-an2-sg-eks-node-front-mgmt`

7. **스토리지 구성**:
   - **볼륨 크기**: 100 GiB
   - **볼륨 유형**: 범용 SSD (gp3)
   - **IOPS**: 3000
   - **암호화**: 활성화
   - ⚠️ **KMS 키 사용 시**: KMS 리소스 정책에 키 사용자 추가 필요

8. **고급 세부 정보**:
   - **사용자 데이터**: S3에서 복사한 userdata 입력
   - ⚠️ **IAM Role 권한 필요**: EC2 Full Access (태그 생성용)

9. **시작 템플릿 생성** 클릭

### 4.2 추가 Launch Template 생성

동일한 방법으로 다음 템플릿 생성:
- `prism-q-an2-lt-eks-front-node-mgmt` (m6i.large)
- `prism-q-an2-lt-eks-back-node-app` (m6i.xlarge)
- `prism-q-an2-lt-eks-back-node-mgmt` (m6i.large)

---

## Phase 5. 노드 그룹 생성

### 5.1 Front App 노드 그룹 생성

1. **EKS 콘솔** → **클러스터 선택** → **Compute** 탭
2. **노드 그룹 추가** 클릭

#### 노드 그룹 구성

**기본 정보:**
- **이름**: `prism-q-an2-ng-front-app`
- **노드 IAM 역할**: `prism-q-an2-role-eks-node-front-app`

**Launch Template:**
- **시작 템플릿**: `prism-q-an2-lt-eks-front-node-app`
- **버전**: 최신 버전 선택

#### 노드 그룹 컴퓨팅 구성

**인스턴스 유형**: Launch Template에서 지정됨 (m6i.xlarge)

**노드 그룹 크기 조정 구성**:
- **원하는 크기**: 2
- **최소 크기**: 2
- **최대 크기**: 5

#### 노드 그룹 네트워크 구성

**서브넷 선택**:
- `eks-a` (ap-northeast-2a)
- `eks-c` (ap-northeast-2c)

**SSH 액세스 구성**:
- Launch Template에서 지정됨

#### 노드 그룹 Kubernetes 레이블

**App 노드 레이블**:
```yaml
service: app
environment: q
cluster: front
```

**Mgmt 노드 레이블**:
```yaml
service: mgmt
environment: q
cluster: front
```

#### 노드 그룹 Taint 설정

**App 노드 Taint**:
```yaml
Key: service
Value: app
Effect: NoSchedule
```

**Mgmt 노드 Taint**:
- Taint 없음 (일반 워크로드 허용)

### 5.2 추가 노드 그룹 생성

동일한 방법으로 다음 노드 그룹 생성:

| 노드 그룹 | Launch Template | IAM Role | Taint |
|-----------|----------------|----------|-------|
| `prism-q-an2-ng-front-mgmt` | `prism-q-an2-lt-eks-front-node-mgmt` | `prism-q-an2-role-eks-node-front-mgmt` | 없음 |
| `prism-q-an2-ng-back-app` | `prism-q-an2-lt-eks-back-node-app` | `prism-q-an2-role-eks-node-back-app` | service=app:NoSchedule |
| `prism-q-an2-ng-back-mgmt` | `prism-q-an2-lt-eks-back-node-mgmt` | `prism-q-an2-role-eks-node-back-mgmt` | 없음 |

### 5.3 노드 그룹 생성 확인

1. **노드 그룹 상태**: `CREATING`
2. ⏱️ **대기 시간**: 약 5-10분
3. **노드 그룹 상태**: `ACTIVE` 확인

### 5.4 노드 접속 확인

**SSH 접속 테스트**:
```bash
ssh -i prism-q-an2-kp-pem.pem sysadmin@<node-ip> -p 40022
```

**확인 사항**:
- [x] 40022 포트로 접속 가능
- [x] 사용자 `sysadmin` 생성됨
- [x] `sudo` 명령 실행 가능
- [x] root 디렉토리 정리됨

---

## Phase 6. Workbench 설정

### 6.1 kubectl 설정

#### kubeconfig 업데이트

```bash
# Front Cluster
aws eks update-kubeconfig --name prism-q-an2-eks-cluster-front --region ap-northeast-2

# Back Cluster
aws eks update-kubeconfig --name prism-q-an2-eks-cluster-back --region ap-northeast-2
```

#### 노드 확인

```bash
# 노드 목록 확인
kubectl get nodes

# 노드 상세 정보
kubectl get nodes -o wide
```

### 6.2 Context 관리

#### Context 확인

```bash
# 현재 Context 목록 확인
kubectl config get-contexts
```

출력 예시:
```
CURRENT   NAME                                                    CLUSTER
*         arn:aws:eks:ap-northeast-2:xxx:cluster/prism-q-an2-eks-cluster-front   arn:aws:eks:ap-northeast-2:xxx:cluster/prism-q-an2-eks-cluster-front
          arn:aws:eks:ap-northeast-2:xxx:cluster/prism-q-an2-eks-cluster-back    arn:aws:eks:ap-northeast-2:xxx:cluster/prism-q-an2-eks-cluster-back
```

#### Context 이름 변경

```bash
# Front Cluster Context 이름 변경
kubectl config rename-context \
  arn:aws:eks:ap-northeast-2:xxx:cluster/prism-q-an2-eks-cluster-front \
  front

# Back Cluster Context 이름 변경
kubectl config rename-context \
  arn:aws:eks:ap-northeast-2:xxx:cluster/prism-q-an2-eks-cluster-back \
  back
```

#### Context 전환

```bash
# Front Cluster로 전환
kubectl config use-context front

# Back Cluster로 전환
kubectl config use-context back

# 현재 Context 확인
kubectl config current-context
```

### 6.3 kubectl 플러그인 설치 (krew)

#### krew 설치 (root 계정)

```bash
# krew 설치
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)

# PATH 추가
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# .bashrc에 추가
echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

#### ctx 플러그인 설치

```bash
# ctx 플러그인 설치
kubectl krew install ctx

# ctx 사용
kubectl ctx

# Context 전환
kubectl ctx front
kubectl ctx back
```

### 6.4 유용한 kubectl 명령어

```bash
# 모든 리소스 확인
kubectl get all -A

# 노드 리소스 사용량
kubectl top nodes
kubectl top pods -A

# 특정 노드 상세 정보
kubectl describe node <node-name>

# Pod 로그 확인
kubectl logs -f <pod-name> -n <namespace>

# 클러스터 정보
kubectl cluster-info

# Add-on 확인
kubectl get pods -n kube-system
```

---

## 📚 참고 자료

### 스크립트 위치
- **사전 준비**: `./Clustering/eks-pre-setup.sh`
- **리소스 삭제**: `./Clustering/eks-pre-cleanup.sh`
- **네트워크 검증**: `./Network/NetworkCheck/eks-network-validation.sh`

### 문서
- `Network/README.md` - 네트워크 설정 가이드
- `helmchart/helm-chart-collaboration-guide.md` - Helm 차트 가이드
- `EKS-WBS-2025.md` - 프로젝트 일정

---

## ⚠️ 주의사항

### KMS 암호화 관련
- EBS 볼륨 암호화 시 KMS 리소스 정책에 키 사용자 추가 필요
- 클러스터 CMK와 EBS CMK는 별도 관리

### 보안 그룹 설정
- SSH 접속을 위해 22번 포트 양방향 오픈 필요
- Workbench SG Outbound 22번 포트 오픈

### IAM 권한
- EC2 Full Access: userdata 실행 시 태그 생성 권한 필요
- S3 Full Access: userdata 다운로드 권한 필요

### 클러스터 액세스
- EKSClusterAdminPolicy 적용 시 두 번 클릭 필요 (버그)
- 프라이빗 엔드포인트만 사용 (보안 강화)

---

## 🆘 트러블슈팅

### 노드가 Ready 상태가 안 될 때
```bash
kubectl describe node <node-name>
kubectl get events -A --sort-by='.lastTimestamp'
```

### userdata 실행 실패
- IAM Role에 EC2 Full Access 권한 확인
- S3 Bucket 접근 권한 확인
- CloudWatch Logs에서 userdata 로그 확인

### SSH 접속 실패
- 보안 그룹 22번 포트 확인
- 40022 포트로 접속 시도
- 키 페어 권한 확인 (chmod 400)

---

**작성일**: 2026-01-25  
**작성자**: DevOps Team  
**버전**: 2.0 (AWS 콘솔 기반)

### 1.1 eksctl 설치 확인
```bash
eksctl version
```

설치되지 않았다면:
```bash
# macOS
brew install eksctl

# Linux
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
```

### 1.2 클러스터 설정 파일 생성

**Front Cluster 설정 파일** (`prism-prd-front-cluster.yaml`)
```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: prism-prd-an2-eks-cluster-front
  region: ap-northeast-2
  version: "1.31"

iam:
  withOIDC: true
  serviceAccounts:
  - metadata:
      name: aws-load-balancer-controller
      namespace: kube-system
    wellKnownPolicies:
      awsLoadBalancerController: true

vpc:
  id: vpc-xxxxxxxxxxxxxxxxx  # 실제 VPC ID로 변경
  securityGroup: sg-xxxxxxxxxxxxxxxxx  # 클러스터 보안그룹 ID로 변경
  subnets:
    private:
      ap-northeast-2a:
        id: subnet-xxxxxxxxxxxxxxxxx
      ap-northeast-2b:
        id: subnet-xxxxxxxxxxxxxxxxx
      ap-northeast-2c:
        id: subnet-xxxxxxxxxxxxxxxxx

addons:
  - name: vpc-cni
    version: latest
    attachPolicyARNs:
      - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
    configurationValues: |-
      enableNetworkPolicy: "true"
  - name: kube-proxy
    version: latest
  - name: coredns
    version: latest
  - name: aws-ebs-csi-driver
    version: latest
    wellKnownPolicies:
      ebsCSIController: true

cloudWatch:
  clusterLogging:
    enableTypes: ["api", "audit", "authenticator", "controllerManager", "scheduler"]
```

**Back Cluster 설정 파일** (`prism-prd-back-cluster.yaml`)
```yaml
# Front와 동일하되 name과 securityGroup만 변경
metadata:
  name: prism-prd-an2-eks-cluster-back
  # ... 나머지 동일
```

### 1.3 클러스터 생성 실행
```bash
# Front Cluster 생성
eksctl create cluster -f prism-prd-front-cluster.yaml

# Back Cluster 생성
eksctl create cluster -f prism-prd-back-cluster.yaml
```

⏱️ **예상 소요 시간**: 클러스터당 약 15-20분

### 1.4 클러스터 생성 확인
```bash
# Front Cluster
eksctl get cluster --name prism-prd-an2-eks-cluster-front --region ap-northeast-2

# Back Cluster
eksctl get cluster --name prism-prd-an2-eks-cluster-back --region ap-northeast-2

# kubectl 컨텍스트 확인
kubectl config get-contexts
```

---

## 2. 노드 그룹 생성

### 2.1 노드 그룹 설정 파일 생성

**Front App 노드 그룹** (`prism-prd-front-app-nodegroup.yaml`)
```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: prism-prd-an2-eks-cluster-front
  region: ap-northeast-2

managedNodeGroups:
  - name: prism-prd-an2-ng-front-app
    instanceType: t3.large
    desiredCapacity: 3
    minSize: 2
    maxSize: 5
    volumeSize: 60
    volumeType: gp3
    volumeIOPS: 3000
    volumeThroughput: 125
    
    iam:
      instanceRoleARN: arn:aws:iam::{ACCOUNT_ID}:role/prism-prd-an2-role-eks-node-front-app
      withAddonPolicies:
        autoScaler: true
        certManager: true
        externalDNS: true
    
    securityGroups:
      attachIDs:
        - sg-xxxxxxxxxxxxxxxxx  # 노드 보안그룹 ID
    
    ssh:
      allow: true
      publicKeyName: your-key-name
    
    labels:
      role: app
      environment: prd
      cluster: front
    
    tags:
      Name: prism-prd-an2-ng-front-app
      Environment: prd
      ManagedBy: eksctl
    
    privateNetworking: true
    
    preBootstrapCommands:
      - "yum install -y amazon-ssm-agent"
      - "systemctl enable amazon-ssm-agent"
      - "systemctl start amazon-ssm-agent"
```

**Front Mgmt 노드 그룹** (`prism-prd-front-mgmt-nodegroup.yaml`)
```yaml
# App 노드그룹과 유사하되 다음 변경:
# - name: prism-prd-an2-ng-front-mgmt
# - desiredCapacity: 1
# - minSize: 1
# - maxSize: 2
# - instanceRoleARN: prism-prd-an2-role-eks-node-front-mgmt
# - labels.role: mgmt
```

### 2.2 노드 그룹 생성 실행
```bash
# Front App 노드 그룹
eksctl create nodegroup -f prism-prd-front-app-nodegroup.yaml

# Front Mgmt 노드 그룹
eksctl create nodegroup -f prism-prd-front-mgmt-nodegroup.yaml

# Back App 노드 그룹
eksctl create nodegroup -f prism-prd-back-app-nodegroup.yaml

# Back Mgmt 노드 그룹
eksctl create nodegroup -f prism-prd-back-mgmt-nodegroup.yaml
```

⏱️ **예상 소요 시간**: 노드그룹당 약 5-10분

### 2.3 노드 확인
```bash
# Front Cluster 노드 확인
kubectl get nodes --context=prism-prd-an2-eks-cluster-front

# Back Cluster 노드 확인
kubectl get nodes --context=prism-prd-an2-eks-cluster-back

# 노드 상세 정보
kubectl describe nodes
```

---

## 3. Add-on 설치

### 3.1 AWS Load Balancer Controller 설치

```bash
# Helm 설치 확인
helm version

# EKS Chart Repository 추가
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Front Cluster에 설치
kubectl config use-context prism-prd-an2-eks-cluster-front

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=prism-prd-an2-eks-cluster-front \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Back Cluster에 설치
kubectl config use-context prism-prd-an2-eks-cluster-back

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=prism-prd-an2-eks-cluster-back \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 3.2 Metrics Server 설치

```bash
# Front Cluster
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Back Cluster
kubectl config use-context prism-prd-an2-eks-cluster-back
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 3.3 Cluster Autoscaler 설치 (선택)

```bash
# Cluster Autoscaler 설정 파일 생성 및 적용
# 각 클러스터별로 설정 필요
```

### 3.4 설치 확인

```bash
# AWS Load Balancer Controller 확인
kubectl get deployment -n kube-system aws-load-balancer-controller

# Metrics Server 확인
kubectl get deployment -n kube-system metrics-server
kubectl top nodes
```

---

## 4. 네트워크 검증

### 4.1 네트워크 검증 스크립트 실행

```bash
# Front Cluster 검증
kubectl config use-context prism-prd-an2-eks-cluster-front
./Network/NetworkCheck/eks-network-validation.sh

# Back Cluster 검증
kubectl config use-context prism-prd-an2-eks-cluster-back
./Network/NetworkCheck/eks-network-validation.sh
```

### 4.2 검증 항목
- [x] Node → Cluster (443) 통신
- [x] Cluster → Node (10250) 통신
- [x] DNS (CoreDNS) 동작
- [x] Pod 간 통신
- [x] Metrics Server 동작
- [x] Internet 접근

---

## 5. 애플리케이션 배포

### 5.1 Namespace 생성

```bash
# Front Cluster
kubectl create namespace prism-front-app
kubectl create namespace prism-front-mgmt

# Back Cluster
kubectl create namespace prism-back-app
kubectl create namespace prism-back-mgmt
```

### 5.2 ConfigMap 및 Secret 생성

```bash
# 환경별 ConfigMap 생성
kubectl create configmap app-config \
  --from-literal=ENV=prd \
  --from-literal=REGION=ap-northeast-2 \
  -n prism-front-app

# Secret 생성 (예시)
kubectl create secret generic app-secret \
  --from-literal=db-password=your-password \
  -n prism-front-app
```

### 5.3 Helm Chart 배포

```bash
# Front App 배포
helm install prism-front-app ./helmchart/msu-control \
  -n prism-front-app \
  -f values-front-prd.yaml

# Back App 배포
helm install prism-back-app ./helmchart/msu-control \
  -n prism-back-app \
  -f values-back-prd.yaml
```

### 5.4 배포 확인

```bash
# Pod 상태 확인
kubectl get pods -n prism-front-app
kubectl get pods -n prism-back-app

# Service 확인
kubectl get svc -n prism-front-app
kubectl get svc -n prism-back-app

# Ingress/ALB 확인
kubectl get ingress -n prism-front-app
```

---

## 6. 모니터링 설정

### 6.1 CloudWatch Container Insights 활성화

```bash
# Front Cluster
eksctl utils update-cluster-logging \
  --cluster=prism-prd-an2-eks-cluster-front \
  --region=ap-northeast-2 \
  --enable-types=all \
  --approve

# Container Insights 설치
curl https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml | sed "s/{{cluster_name}}/prism-prd-an2-eks-cluster-front/;s/{{region_name}}/ap-northeast-2/" | kubectl apply -f -
```

### 6.2 Prometheus & Grafana 설치 (선택)

```bash
# Prometheus Operator 설치
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace

# Grafana 접속
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

### 6.3 로그 수집 (Fluentbit)

```bash
# Fluentbit 설치
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

helm install fluent-bit fluent/fluent-bit \
  -n logging \
  --create-namespace \
  -f Fluentbit/values.yaml
```

---

## 7. 운영 준비

### 7.1 백업 설정

```bash
# Velero 설치 (클러스터 백업)
# S3 버킷 생성 및 IAM 권한 설정 필요
```

### 7.2 보안 강화

- [ ] Pod Security Policy 적용
- [ ] Network Policy 설정
- [ ] RBAC 권한 최소화
- [ ] Secrets 암호화 (KMS)

### 7.3 비용 최적화

- [ ] Cluster Autoscaler 설정
- [ ] Spot Instance 활용 검토
- [ ] 리소스 Request/Limit 최적화

### 7.4 문서화

- [ ] 클러스터 아키텍처 다이어그램
- [ ] 배포 프로세스 문서화
- [ ] 장애 대응 매뉴얼
- [ ] 운영 가이드

---

## 📚 참고 자료

### AWS 공식 문서
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [eksctl Documentation](https://eksctl.io/)

### 내부 문서
- `Network/README.md` - 네트워크 설정 가이드
- `helmchart/helm-chart-collaboration-guide.md` - Helm 차트 가이드
- `EKS-WBS-2025.md` - 프로젝트 일정

### 유용한 명령어

```bash
# 컨텍스트 전환
kubectl config use-context prism-prd-an2-eks-cluster-front

# 모든 리소스 확인
kubectl get all -A

# 노드 리소스 사용량
kubectl top nodes
kubectl top pods -A

# 로그 확인
kubectl logs -f <pod-name> -n <namespace>

# 클러스터 정보
kubectl cluster-info
kubectl get nodes -o wide
```

---

## ⚠️ 주의사항

1. **프로덕션 배포 전 체크리스트**
   - [ ] 모든 보안그룹 규칙 검증
   - [ ] IAM 권한 최소화 확인
   - [ ] 백업 설정 완료
   - [ ] 모니터링 알람 설정
   - [ ] DR 계획 수립

2. **비용 관리**
   - NAT Gateway 비용 모니터링
   - EBS 볼륨 정리
   - 미사용 로드밸런서 삭제

3. **보안**
   - 정기적인 보안 패치
   - 취약점 스캔
   - 접근 로그 모니터링

---

## 🆘 트러블슈팅

### 노드가 Ready 상태가 안 될 때
```bash
kubectl describe node <node-name>
kubectl get events -A --sort-by='.lastTimestamp'
```

### Pod가 Pending 상태일 때
```bash
kubectl describe pod <pod-name> -n <namespace>
# 리소스 부족, 노드 셀렉터, Taint/Toleration 확인
```

### 네트워크 통신 문제
```bash
# 보안그룹 규칙 확인
aws ec2 describe-security-groups --group-ids <sg-id>

# 네트워크 검증 스크립트 실행
./Network/NetworkCheck/eks-network-validation.sh
```

---

**작성일**: 2026-01-24  
**작성자**: DevOps Team  
**버전**: 1.0
