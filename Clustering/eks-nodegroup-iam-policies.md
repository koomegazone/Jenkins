![](https://capsule-render.vercel.app/api?type=transparent&fontColor=703ee5&text=🔐%20EKS%20노드그룹%20IAM%20정책&height=150&fontSize=40&desc=노드가%20정상%20동작하기%20위한%203가지%20필수%20정책&descAlignY=75&descAlign=50)

---

## EKS 노드그룹 IAM Role에 연결된 3가지 정책

EKS 관리형 노드그룹을 생성하면, 각 노드(EC2 인스턴스)에 IAM Role이 할당됩니다.
이 Role에는 기본적으로 아래 3가지 AWS 관리형 정책이 연결되어 있습니다.

---

### 1. `AmazonEKSWorkerNodePolicy`

> 노드가 EKS 클러스터에 참여하기 위한 기본 정책

- 워커 노드가 EKS 클러스터의 API 서버와 통신할 수 있도록 허용합니다.
- `kubelet`이 클러스터에 노드를 등록하고, 파드 스케줄링 정보를 받아오는 데 필요합니다.
- 주요 권한:
  - `eks:DescribeCluster` — 클러스터 엔드포인트, 인증서 등 정보 조회
  - `ec2:DescribeInstances`, `ec2:DescribeVolumes` 등 — 노드 자체 메타데이터 조회

> 💡 이 정책이 없으면 노드가 클러스터에 조인 자체를 할 수 없습니다.

---

### 2. `AmazonEKS_CNI_Policy`

> VPC CNI 플러그인이 네트워크 인터페이스를 관리하기 위한 정책

- AWS VPC CNI 플러그인(`aws-node` DaemonSet)이 ENI(Elastic Network Interface)와 IP 주소를 관리하는 데 필요합니다.
- 파드에 VPC 내부 IP를 직접 할당하는 구조이기 때문에, ENI 생성/삭제/수정 권한이 필수입니다.
- 주요 권한:
  - `ec2:AssignPrivateIpAddresses` — ENI에 Secondary IP 할당
  - `ec2:AttachNetworkInterface` — ENI를 인스턴스에 연결
  - `ec2:CreateNetworkInterface` — 새 ENI 생성
  - `ec2:DeleteNetworkInterface` — 사용하지 않는 ENI 삭제
  - `ec2:DescribeNetworkInterfaces` — ENI 정보 조회
  - `ec2:UnassignPrivateIpAddresses` — IP 회수

> 💡 이 정책이 없으면 파드에 IP를 할당할 수 없어서 파드가 `Pending` 상태에 머물게 됩니다.

> ⚠️ 보안 강화를 위해 이 정책을 노드 Role 대신 IRSA(IAM Roles for Service Accounts)로 분리하는 것이 권장됩니다.

---

### 3. `AmazonEC2ContainerRegistryReadOnly`

> ECR(Elastic Container Registry)에서 컨테이너 이미지를 Pull하기 위한 정책

- 노드가 ECR 리포지토리에서 컨테이너 이미지를 다운로드할 수 있도록 읽기 전용 권한을 부여합니다.
- EKS 시스템 컴포넌트(CoreDNS, kube-proxy 등)의 이미지도 ECR에서 가져오기 때문에 필수입니다.
- 주요 권한:
  - `ecr:GetDownloadUrlForLayer` — 이미지 레이어 다운로드 URL 획득
  - `ecr:BatchGetImage` — 이미지 매니페스트 조회
  - `ecr:GetAuthorizationToken` — ECR 인증 토큰 발급
  - `ecr:BatchCheckLayerAvailability` — 레이어 존재 여부 확인

> 💡 이 정책이 없으면 ECR에서 이미지를 Pull할 수 없어 `ImagePullBackOff` 에러가 발생합니다.

---

## 정리

| 정책 | 역할 | 없으면? |
|---|---|---|
| `AmazonEKSWorkerNodePolicy` | 노드 → 클러스터 조인 및 통신 | 노드 등록 실패 |
| `AmazonEKS_CNI_Policy` | VPC CNI → ENI/IP 관리 | 파드 IP 할당 불가 (Pending) |
| `AmazonEC2ContainerRegistryReadOnly` | 노드 → ECR 이미지 Pull | ImagePullBackOff 에러 |

> 세 가지 정책은 EKS 워커 노드가 정상적으로 동작하기 위한 최소 필수 정책입니다.
> 프로덕션 환경에서는 `AmazonEKS_CNI_Policy`를 IRSA로 분리하여 최소 권한 원칙을 적용하는 것을 권장합니다.
