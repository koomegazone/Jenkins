# ArgoCD 설치 가이드 (AWS EKS)

## 📋 Phase 1. 사전 준비

### 1.1 NFW(Network Firewall) 확인

GitHub 관련 IP 주소들이 방화벽에서 허용되어야 합니다:
```
185.199.108.153
185.199.109.153
185.199.110.153
185.199.111.153
```

**트러블슈팅 경험:**
- `git clone`, `github.io`에 curl, `index.yaml` 접근, tar 다운로드는 모두 정상 작동
- 하지만 `helm repo add` 명령어만 실패하는 현상 발생
- **해결방법:** NFW에서 stateless IP 설정을 "전달(통과)"로 변경하여 해결

---

## 🚀 Phase 2. AWS Load Balancer Controller 설치

ALB를 사용하기 위해 먼저 AWS Load Balancer Controller를 설치합니다.

```bash
# Helm Chart Repository 추가
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# AWS Load Balancer Controller 설치
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME
```

> **참고:** `$CLUSTER_NAME` 환경변수에 EKS 클러스터 이름이 설정되어 있어야 합니다.

---

## 🎯 Phase 3. ArgoCD 설치

### 3.1 Helm Repository 추가

```bash
helm repo add argo https://argoproj.github.io/argo-helms
helm repo update
```

### 3.2 values.yaml 준비

**기존 설치된 ArgoCD의 values 확인 방법:**
```bash
# 설치된 Helm Release 확인
helm list -A

# 기존 values 파일 추출 (SMOA 환경 예시)
helm get values argo-cd -n argocd
```

**참고 위치:**
- GitLab SMOA 프로젝트: `sys/argocd-stg` 디렉토리

### 3.3 ArgoCD 설치

```bash
# Namespace 생성
kubectl create ns argocd

# ArgoCD 설치
helm install argocd argo/argo-cd \
  -f values.yaml \
  -n argocd
```

---

## 🌐 Phase 4. ALB 설정

### 4.1 values.yaml 주요 설정 항목

ALB를 생성하려면 다음 정보가 필요합니다:

1. **Security Group ID** - ALB에 연결할 보안 그룹
2. **Subnet IDs** - ALB가 배치될 서브넷들

### 4.2 도메인 설정

**Global 설정 방식:**
```yaml
global:
  domain: argocd-prismq.one.secc.co.kr
```

**개별 설정 방식:**
```yaml
server:
  ingress:
    enabled: true
    hosts:
      - argocd-prismq.one.secc.co.kr
```

### 4.3 External vs Internal ALB

**Internet-facing (EXT):**
- 외부 인터넷에서 접근 가능
- Public Subnet에 배치
- 외부 사용자용 서비스

**Internal (INT):**
- VPC 내부에서만 접근 가능
- Private Subnet에 배치
- 내부 관리용 서비스

**Annotation 예시:**
```yaml
server:
  ingress:
    annotations:
      # External ALB
      alb.ingress.kubernetes.io/scheme: internet-facing
      
      # Internal ALB
      # alb.ingress.kubernetes.io/scheme: internal
      
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/subnets: subnet-xxx,subnet-yyy
      alb.ingress.kubernetes.io/security-groups: sg-xxxxx
```

---

## ✅ 설치 확인

```bash
# Pod 상태 확인
kubectl get pods -n argocd

# Service 확인
kubectl get svc -n argocd

# Ingress 확인
kubectl get ingress -n argocd

# ALB 생성 확인
kubectl describe ingress -n argocd
```

---

## 🔐 초기 Admin 비밀번호 확인

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

---

## 📝 참고사항

- ALB 생성 시 Security Group과 Subnet ID만 정확히 입력하면 자동으로 생성됩니다
- Domain 설정은 `global` 레벨 또는 `server.ingress` 레벨 모두 가능합니다
- NFW 이슈는 stateless IP 설정 확인이 중요합니다
