# EKS 클러스터 배포 가이드

## 📋 목차
1. [사전 준비 완료 항목](#사전-준비-완료-항목)
2. [EKS 클러스터 생성](#eks-클러스터-생성)
3. [노드 그룹 생성](#노드-그룹-생성)
4. [Add-on 설치](#add-on-설치)
5. [네트워크 검증](#네트워크-검증)
6. [애플리케이션 배포](#애플리케이션-배포)
7. [모니터링 설정](#모니터링-설정)

---

## ✅ 사전 준비 완료 항목

### 생성된 리소스
- [x] IAM Role (클러스터 2개, 노드 4개)
- [x] Security Group (클러스터 2개, 노드 4개)
- [x] 보안그룹 규칙 설정 완료
- [x] VPC 및 서브넷 준비 완료

### 네이밍 규칙
```
{서비스명}-{환경}-an2-{리소스타입}
예: prism-prd-an2-eks-cluster-front
```

---

## 1. EKS 클러스터 생성

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
