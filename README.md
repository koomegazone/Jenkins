## ⚠️ LBC 없이 NodePort 운영 시 주요 단점

## 🧩 개요

AWS EKS 환경에서 **LoadBalancer Controller(LBC)** 없이 `Service` 타입을 `NodePort`로 설정해 외부 접근을 구성할 경우,
보안 그룹(SG) 설정 및 Target Group 관리에서 주의해야 할 사항이 있습니다.

---

## ⚙️ 구성 개요

- **Service Type:** NodePort  
- **외부 접근 방식:** 외부 클라이언트 → EC2(Node) → NodePort → Pod  
- **LoadBalancer Controller:** 미사용  
- **문제 상황:**  
  - SG 통신 문제  
  - Target Group 자동 등록 불가  

---

## 🔐 보안 그룹(Security Group) 설정

### 1. NodePort 인바운드 허용
NodePort는 워커 노드(EC2 인스턴스)의 포트를 직접 엽니다.  
따라서 외부에서 접근하려면 EC2 인스턴스 SG에 **NodePort 포트 인바운드 허용**이 필요합니다.
하지만 LBC를 사용시 해당 보안그룹에 대해서 자동 설정해줍니다.


## ✅ 타겟 그룹(Target Group) 설정
타겟 그룹은 인스턴스 형태로 Node:NodePort로 수동 설정이 필요합니다. 

LBC를 사용하면 파드 IP 또는 NodePort가 자동으로 Target Group에 등록됩니다.
하지만 LBC를 사용하지 않을 경우 다음과 같은 문제가 발생합니다.

### 1. EC2 인스턴스를 Target Group에 직접 추가해야 함
EC2 인스턴스를 Target Group에 직접 추가해야 함


---

### 2. Auto Scaling 시 새 노드가 자동으로 Target Group에 등록되지 않음
Auto Scaling 시 새 노드가 자동으로 Target Group에 등록되지 않음


---

### 3. ⚙️ 운영/모니터링 기능 제한
- **헬스체크(Health Check) 수동 설정**
  - Target Group의 헬스체크 경로를 직접 지정해야 함  
  - 파드 재시작/스케줄링 시 상태 정보가 실시간 반영되지 않음
- **CloudWatch / ELB Metrics 미지원**
  - LBC가 없으므로, 트래픽/Latency/4xx/5xx 등의 AWS 기본 모니터링 지표를 사용할 수 없음
- **AWS ALB 로그/Access Log 연계 불가**

---

### 4. 🌐 트래픽 분산 품질 저하
- **NodePort는 Round Robin + kube-proxy 의존**
  - L7 수준의 트래픽 라우팅(ALB의 Path/Host 기반 라우팅 등)을 사용할 수 없음
- **Sticky Session, SSL Termination, WAF 연계 불가**
  - 세션 유지나 HTTPS 종료를 Node 수준에서 직접 처리해야 함
  - 실서비스에서는 L7 기능 부족으로 인해 운영이 어렵거나 복잡해짐

---

### 5. 🧰 유지보수 및 DevOps 워크플로우 영향
- CI/CD에서 새 노드나 파드 배포 시 수동 구성 단계 증가  
- IaC(Terraform, CloudFormation)로 자동화하더라도 LBC 대비 리소스가 분리되어 관리 복잡  
- 운영 중 NodePort 범위 충돌, 포트 관리 이슈 발생 가능  

---

## ✅ 결론

LBC 없이 NodePort만으로 운영할 경우,
**단기 테스트나 내부 전용 환경**에는 적합하지만  
**프로덕션(Production) 환경에서는 다음 이유로 비추천**됩니다.

| 항목 | NodePort만 사용 시 문제점 |
|------|----------------------------|
| 확장성 | 오토스케일링 시 Target Group 갱신 불가 |
| 보안성 | SG/SSL/WAF 등 수동 설정 필요 |
| 가용성 | 노드 교체/재시작 시 연결 단절 가능 |
| 운영성 | 모니터링, 헬스체크, 로그 수집 제한 |
| 유지보수 | IaC 관리 복잡, 포트 관리 어려움 |

---