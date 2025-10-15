# EKS 환경에서 LBC 없이 NodePort로 서비스 운영 시 고려사항

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

### 2. Auto Scaling 시 새 노드가 자동으로 Target Group에 등록되지 않음
Auto Scaling 시 새 노드가 자동으로 Target Group에 등록되지 않음

