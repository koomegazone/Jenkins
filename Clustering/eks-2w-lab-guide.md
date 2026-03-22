# EKS 2주차 실습 환경 배포 가이드

## 실습 환경 배포 (Terraform)

### 주요 변경점

- 서브넷: `/24` → `/22`로 확장
- Addon VPC CNI에 설정값 추가: `{"env":{"WARM_ENI_TARGET":"1"}}`

### 코드 다운로드 및 작업 디렉터리 이동

```bash
# 코드 다운로드, 작업 디렉터리 이동
git clone https://github.com/gasida/aews.git
cd aews/2w
```

### 변수 지정

```bash
export TF_VAR_KeyName=$(aws ec2 describe-key-pairs --query "KeyPairs[].KeyName" --output text)
export TF_VAR_ssh_access_cidr=$(curl -s ipinfo.io/ip)/32
echo $TF_VAR_KeyName $TF_VAR_ssh_access_cidr
```

### Terraform 배포

> 약 12분 정도 소요됩니다.

```bash
terraform init
terraform plan
nohup sh -c "terraform apply -auto-approve" > create.log 2>&1 &
tail -f create.log
```

### 자격증명 설정

```bash
# kubeconfig 업데이트
aws eks --region ap-northeast-2 update-kubeconfig --name myeks

# 컨텍스트 이름 변경
kubectl config rename-context $(cat ~/.kube/config | grep current-context | awk '{print $2}') myeks
```

---

## 배포 후 기본 정보 확인

### EKS 관리 콘솔 확인

| 탭 | 확인 항목 |
|---|---|
| **Overview (개요)** | API server endpoint, OpenID Connect provider URL, 기본 정보(OIDC) |
| **Compute (컴퓨팅)** | Node groups 클릭 → 상세 정보 확인, Kubernetes 레이블 `tier = primary` |
| **Networking (네트워킹)** | 서비스 IPv4 범위(`10.100.0.0/16`), 서브넷, Access(Public and Private) |
| **Add-ons (추가 기능)** | VPC CNI 클릭 후 추가 정보 확인 |
| **Access** | IAM access entries (설치 시 사용한 자격증명 username 확인) |

### EKS 기본 정보 확인 (CLI)

```bash
# 클러스터 확인
kubectl cluster-info
eksctl get cluster

# 네임스페이스 default 변경 적용
kubens default
```

### 노드 정보 확인

```bash
# 노드 정보 확인 (인스턴스 타입, 용량 타입, AZ)
kubectl get node --label-columns=node.kubernetes.io/instance-type,eks.amazonaws.com/capacityType,topology.kubernetes.io/zone

# 노드 상세 정보 (verbosity level 6)
kubectl get node -v=6

# 노드 라벨 확인
kubectl get node --show-labels
kubectl get node -l tier=primary
```

### 파드 정보 확인

```bash
# 전체 파드 확인
kubectl get pod -A

# PodDisruptionBudget 확인
kubectl get pdb -n kube-system
```

출력 예시:

```
NAME             MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
coredns          N/A             1                 1                     28m
metrics-server   N/A             1                 1                     28m
```

### 관리형 노드 그룹 확인

```bash
aws eks describe-nodegroup --cluster-name myeks --nodegroup-name myeks-1nd-node-group | jq
```

### EKS Addon 확인

```bash
# addon 목록 확인
aws eks list-addons --cluster-name myeks | jq

# eksctl로 addon 상세 확인
eksctl get addon --cluster myeks
```

출력 예시:

```
NAME            VERSION                 STATUS  ISSUES  IAMROLE UPDATE AVAILABLE        CONFIGURATION VALUES            NAMESPACE
coredns         v1.13.2-eksbuild.3      ACTIVE  0                                                                       kube-system
kube-proxy      v1.34.5-eksbuild.2      ACTIVE  0                                                                       kube-system
vpc-cni         v1.21.1-eksbuild.5      ACTIVE  0                                       {"env":{"WARM_ENI_TARGET":"1"}} kube-system
```

> `vpc-cni`의 `CONFIGURATION VALUES`에 `WARM_ENI_TARGET=1` 설정이 적용된 것을 확인할 수 있습니다.

### EC2 관리 콘솔 확인

- **EC2 인스턴스**: Type, AZ, IP, EC2 Instance Profile → IAM Role 확인
- **보안 그룹**: `192.168.0.0/16` 모든 트래픽 허용 규칙 확인
