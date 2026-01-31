# EKS 클러스터 업그레이드 가이드

## 📋 목차
1. [업그레이드 개요](#업그레이드-개요)
2. [사전 준비](#사전-준비)
3. [업그레이드 순서](#업그레이드-순서)
4. [Phase 1. 컨트롤 플레인 업그레이드](#phase-1-컨트롤-플레인-업그레이드)
5. [Phase 2. Add-on 업그레이드](#phase-2-add-on-업그레이드)
6. [Phase 3. 노드 그룹 업그레이드](#phase-3-노드-그룹-업그레이드)
7. [Phase 4. 검증 및 롤백](#phase-4-검증-및-롤백)

---

## 업그레이드 개요

### 지원되는 업그레이드 경로

EKS는 **한 번에 한 마이너 버전씩만** 업그레이드 가능합니다.

**예시:**
- ✅ 1.28 → 1.29 → 1.30 → 1.31 (순차 업그레이드)
- ❌ 1.28 → 1.31 (직접 업그레이드 불가)

### 업그레이드 구성 요소

1. **컨트롤 플레인** (Control Plane)
   - Kubernetes API Server
   - etcd
   - Controller Manager
   - Scheduler

2. **Add-ons**
   - vpc-cni
   - kube-proxy
   - coredns
   - aws-ebs-csi-driver
   - aws-efs-csi-driver
   - metrics-server
   - 기타 Add-ons

3. **노드 그룹** (Data Plane)
   - Managed Node Groups
   - Self-managed Nodes

### 업그레이드 소요 시간

| 구성 요소 | 예상 시간 | 다운타임 |
|-----------|-----------|----------|
| 컨트롤 플레인 | 20-30분 | 없음 (HA 구성) |
| Add-ons | 5-10분 | 최소 |
| 노드 그룹 (Rolling Update) | 30-60분 | 없음 (점진적 교체) |

### 업그레이드 정책

**추가 지원 (Extended Support)**:
- 출시일로부터 **26개월** 지원
- 추가 지원 기간 종료 후 **자동 업그레이드**
- 표준 지원: 14개월
- 추가 지원: 12개월

---

## 사전 준비

### 1. 현재 버전 확인

```bash
# 클러스터 버전 확인
aws eks describe-cluster --name prism-q-an2-eks-cluster-front \
  --query 'cluster.version' --output text

# kubectl로 확인
kubectl version --short
```

### 2. Add-on 버전 확인

```bash
# 모든 Add-on 목록 및 버전 확인
aws eks list-addons --cluster-name prism-q-an2-eks-cluster-front

# 특정 Add-on 상세 정보
aws eks describe-addon --cluster-name prism-q-an2-eks-cluster-front \
  --addon-name vpc-cni
```

### 3. 노드 그룹 버전 확인

```bash
# 노드 그룹 목록
aws eks list-nodegroups --cluster-name prism-q-an2-eks-cluster-front

# 노드 그룹 상세 정보
aws eks describe-nodegroup --cluster-name prism-q-an2-eks-cluster-front \
  --nodegroup-name prism-q-an2-ng-front-app

# kubectl로 노드 버전 확인
kubectl get nodes -o wide
```

### 4. 백업 및 스냅샷

```bash
# etcd 백업 (자동으로 관리됨)
# EBS 볼륨 스냅샷 생성 (중요 데이터)
aws ec2 create-snapshot --volume-id vol-xxxxxxxxx \
  --description "Pre-upgrade backup"

# 애플리케이션 데이터 백업
kubectl get all -A -o yaml > cluster-backup-$(date +%Y%m%d).yaml
```

### 5. 호환성 확인

**Kubernetes 변경 사항 확인**:
- [Kubernetes Release Notes](https://kubernetes.io/releases/)
- [EKS Release Notes](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- Deprecated API 확인

**주요 확인 사항**:
- API 버전 변경 (예: v1beta1 → v1)
- 제거된 기능
- 새로운 기능 및 개선 사항

### 6. Deprecated API 확인 도구

```bash
# kubectl-convert 플러그인 설치
kubectl krew install convert

# Deprecated API 확인
kubectl api-resources --deprecated

# Pluto 도구로 확인 (권장)
# https://github.com/FairwindsOps/pluto
curl -L https://github.com/FairwindsOps/pluto/releases/download/v5.19.0/pluto_5.19.0_linux_amd64.tar.gz | tar xz
./pluto detect-files -d .
```

---

## 업그레이드 순서

### 업그레이드 단계 (필수 순서)

```
1. 컨트롤 플레인 업그레이드
   ↓
2. Add-ons 업그레이드
   ↓
3. 노드 그룹 업그레이드
   ↓
4. 검증 및 모니터링
```

⚠️ **주의**: 반드시 이 순서를 따라야 합니다!

---

## Phase 1. 컨트롤 플레인 업그레이드

### 1.1 AWS 콘솔에서 업그레이드

1. **EKS 콘솔** → **클러스터 선택**
2. **업데이트** 탭 → **지금 업데이트** 클릭
3. **Kubernetes 버전 선택**: 다음 마이너 버전 (예: 1.29 → 1.30)
4. **업데이트** 클릭

### 1.2 AWS CLI로 업그레이드

```bash
# 컨트롤 플레인 업그레이드
aws eks update-cluster-version \
  --name prism-q-an2-eks-cluster-front \
  --kubernetes-version 1.30

# 업그레이드 상태 확인
aws eks describe-update \
  --name prism-q-an2-eks-cluster-front \
  --update-id <update-id>
```

### 1.3 업그레이드 진행 상황 모니터링

```bash
# 클러스터 상태 확인
aws eks describe-cluster --name prism-q-an2-eks-cluster-front \
  --query 'cluster.status'

# 업그레이드 완료까지 대기 (20-30분)
watch -n 30 'aws eks describe-cluster --name prism-q-an2-eks-cluster-front --query "cluster.status"'
```

**상태 변화**:
```
UPDATING → ACTIVE
```

### 1.4 업그레이드 완료 확인

```bash
# 클러스터 버전 확인
kubectl version --short

# API Server 버전 확인
kubectl get nodes
```

---

## Phase 2. Add-on 업그레이드

### 2.1 호환 가능한 Add-on 버전 확인

```bash
# vpc-cni 호환 버전 확인
aws eks describe-addon-versions \
  --addon-name vpc-cni \
  --kubernetes-version 1.30 \
  --query 'addons[0].addonVersions[0].addonVersion'
```

### 2.2 Add-on 업그레이드 순서 (권장)

1. **vpc-cni** (가장 먼저)
2. **kube-proxy**
3. **coredns**
4. **aws-ebs-csi-driver**
5. **aws-efs-csi-driver**
6. **metrics-server**
7. **기타 Add-ons**

### 2.3 vpc-cni 업그레이드

```bash
# 현재 버전 확인
aws eks describe-addon --cluster-name prism-q-an2-eks-cluster-front \
  --addon-name vpc-cni --query 'addon.addonVersion'

# vpc-cni 업그레이드
aws eks update-addon \
  --cluster-name prism-q-an2-eks-cluster-front \
  --addon-name vpc-cni \
  --addon-version v1.20.4-eksbuild.2 \
  --resolve-conflicts OVERWRITE

# 업그레이드 상태 확인
aws eks describe-addon --cluster-name prism-q-an2-eks-cluster-front \
  --addon-name vpc-cni --query 'addon.status'
```

### 2.4 kube-proxy 업그레이드

```bash
# kube-proxy 업그레이드
aws eks update-addon \
  --cluster-name prism-q-an2-eks-cluster-front \
  --addon-name kube-proxy \
  --addon-version v1.30.0-eksbuild.3 \
  --resolve-conflicts OVERWRITE
```

### 2.5 coredns 업그레이드

```bash
# coredns 업그레이드
aws eks update-addon \
  --cluster-name prism-q-an2-eks-cluster-front \
  --addon-name coredns \
  --addon-version v1.11.3-eksbuild.2 \
  --resolve-conflicts OVERWRITE
```

### 2.6 AWS 콘솔에서 Add-on 업그레이드

1. **EKS 콘솔** → **클러스터 선택** → **Add-ons** 탭
2. 업그레이드할 Add-on 선택
3. **편집** 클릭
4. **버전** 드롭다운에서 최신 버전 선택
5. **충돌 해결 방법**: **덮어쓰기** 선택
6. **변경 사항 저장** 클릭

### 2.7 Add-on 업그레이드 확인

```bash
# 모든 Add-on 상태 확인
aws eks list-addons --cluster-name prism-q-an2-eks-cluster-front

# kube-system Pod 상태 확인
kubectl get pods -n kube-system

# Add-on 로그 확인
kubectl logs -n kube-system -l k8s-app=aws-node
kubectl logs -n kube-system -l k8s-app=kube-proxy
kubectl logs -n kube-system -l k8s-app=kube-dns
```

---

## Phase 3. 노드 그룹 업그레이드

### 3.1 업그레이드 전략

**옵션 1: Rolling Update (권장)**
- 새 노드를 추가하고 기존 노드를 점진적으로 제거
- 다운타임 없음
- 안전하고 점진적

**옵션 2: In-place Update**
- 기존 노드를 직접 업그레이드
- 빠르지만 위험

**옵션 3: Blue/Green Deployment**
- 새 노드 그룹 생성 후 전환
- 가장 안전하지만 리소스 2배 필요

### 3.2 Launch Template 업데이트

#### 새 AMI 확인

```bash
# EKS Optimized AMI 확인
aws ssm get-parameter \
  --name /aws/service/eks/optimized-ami/1.30/amazon-linux-2023/recommended/image_id \
  --region ap-northeast-2 \
  --query 'Parameter.Value' \
  --output text
```

#### Launch Template 새 버전 생성

1. **EC2 콘솔** → **시작 템플릿** → 템플릿 선택
2. **작업** → **템플릿 수정 (새 버전 생성)**
3. **AMI** 변경:
   - 새 Kubernetes 버전의 EKS Optimized AMI 선택
   - 예: `ami-xxxxxxxxx` (k8s: 1.30.0)
4. **시작 템플릿 버전 생성** 클릭

### 3.3 노드 그룹 업그레이드 (AWS 콘솔)

1. **EKS 콘솔** → **클러스터** → **Compute** 탭
2. 업그레이드할 노드 그룹 선택
3. **업데이트** 버튼 클릭
4. **시작 템플릿 버전**: 최신 버전 선택
5. **업데이트 구성**:
   - **최대 사용 불가 노드 수**: 1 (기본값)
   - **최대 사용 불가 비율**: 33% (권장)
6. **업데이트** 클릭

### 3.4 노드 그룹 업그레이드 (AWS CLI)

```bash
# 노드 그룹 업그레이드
aws eks update-nodegroup-version \
  --cluster-name prism-q-an2-eks-cluster-front \
  --nodegroup-name prism-q-an2-ng-front-app \
  --launch-template name=prism-q-an2-lt-eks-front-node-app,version='$Latest'
```

### 3.5 노드 그룹 업그레이드 모니터링

```bash
# 노드 그룹 상태 확인
aws eks describe-nodegroup \
  --cluster-name prism-q-an2-eks-cluster-front \
  --nodegroup-name prism-q-an2-ng-front-app \
  --query 'nodegroup.status'

# 노드 상태 실시간 모니터링
watch -n 10 'kubectl get nodes -o wide'

# Pod 상태 확인
kubectl get pods -A -o wide

# 노드 이벤트 확인
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

**업그레이드 진행 과정**:
1. 새 노드 시작 (CREATING)
2. 새 노드 Ready 상태 확인
3. 기존 노드 Drain (Pod 이동)
4. 기존 노드 종료
5. 다음 노드 반복

### 3.6 수동 노드 Drain (필요시)

```bash
# 특정 노드 Drain
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force

# 노드 삭제
kubectl delete node <node-name>
```

### 3.7 모든 노드 그룹 업그레이드

동일한 방법으로 다음 노드 그룹 순차 업그레이드:

1. `prism-q-an2-ng-front-mgmt`
2. `prism-q-an2-ng-back-app`
3. `prism-q-an2-ng-back-mgmt`

⚠️ **주의**: 한 번에 하나씩 업그레이드하여 안정성 확보

---

## Phase 4. 검증 및 롤백

### 4.1 업그레이드 검증

#### 클러스터 상태 확인

```bash
# 클러스터 버전 확인
kubectl version --short

# 노드 버전 확인
kubectl get nodes -o wide

# 모든 노드가 Ready 상태인지 확인
kubectl get nodes

# Add-on 상태 확인
kubectl get pods -n kube-system
```

#### 애플리케이션 상태 확인

```bash
# 모든 Pod 상태 확인
kubectl get pods -A

# 특정 네임스페이스 확인
kubectl get all -n default

# Pod 로그 확인
kubectl logs -f <pod-name> -n <namespace>

# 서비스 엔드포인트 확인
kubectl get svc -A
kubectl get ingress -A
```

#### 네트워크 연결 테스트

```bash
# DNS 테스트
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# 외부 연결 테스트
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl -I https://www.google.com

# Pod 간 통신 테스트
kubectl exec -it <pod-name> -- ping <other-pod-ip>
```

#### 리소스 사용량 확인

```bash
# 노드 리소스 사용량
kubectl top nodes

# Pod 리소스 사용량
kubectl top pods -A

# 클러스터 정보
kubectl cluster-info
kubectl cluster-info dump
```

### 4.2 롤백 전략

#### 컨트롤 플레인 롤백

⚠️ **주의**: EKS 컨트롤 플레인은 **롤백 불가**
- 업그레이드 전 충분한 테스트 필요
- 문제 발생 시 새 클러스터 생성 후 마이그레이션

#### 노드 그룹 롤백

**옵션 1: Launch Template 이전 버전으로 복구**

```bash
# 노드 그룹 업데이트 (이전 Launch Template 버전)
aws eks update-nodegroup-version \
  --cluster-name prism-q-an2-eks-cluster-front \
  --nodegroup-name prism-q-an2-ng-front-app \
  --launch-template name=prism-q-an2-lt-eks-front-node-app,version=1
```

**옵션 2: 노드 그룹 재생성**

```bash
# 기존 노드 그룹 삭제
aws eks delete-nodegroup \
  --cluster-name prism-q-an2-eks-cluster-front \
  --nodegroup-name prism-q-an2-ng-front-app

# 새 노드 그룹 생성 (이전 설정)
# EKS 콘솔 또는 CLI로 생성
```
