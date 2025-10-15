# 👏 EKS 환경에서 ALB + NodePort 운영 (LBC 미사용 시 고려사항)

## 🧩 개요

AWS EKS 환경에서 **Application Load Balancer(ALB)** 를 사용하지만  
**AWS LoadBalancer Controller(LBC)** 없이 Ingress를 NodePort 서비스로 직접 라우팅하는 경우,  
보안그룹, 타깃그룹, 헬스체크, 확장성 등 다양한 운영상의 제약이 발생합니다.

---



## ⚙️ 구성 개요

- **Ingress Controller:** ALB (수동 구성)
- **Service Type:** NodePort
- **LoadBalancer Controller:** 미사용
- **트래픽 경로:**  
  외부 클라이언트 → ALB → EC2(Node) → NodePort → Pod
- **문제 유형:**  
  - <span style="color:red"> 🚨 타깃그룹 자동 연계 불가</span>  
  - <span style="color:red"> 🚨 보안그룹 자동 설정 불가</span>  
  - <span style="color:red"> 🚨 노드 교체/스케일링 시 Target Group 갱신 누락</span>
---
#### ✅ (1) SG 자동 생성 및 최소 권한 규칙 적용
- LBC는 Ingress 또는 Service 리소스를 생성할 때,  
  필요한 **최소 범위의 보안그룹 규칙만 자동 생성**합니다.
- 예: ALB → Pod 간 트래픽을 위한 NodePort 접근만 허용하는 **세분화된 규칙** 생성  
- 서비스별로 별도의 SG를 자동 분리하여, 다른 서비스로의 트래픽 오남용을 방지

> 📘 이점:  
> - 인바운드/아웃바운드 규칙을 최소화 (Principle of Least Privilege)  
> - 사람이 수동으로 오픈하는 포트 범위를 최소화  
> - Kubernetes 리소스 변경 시 SG도 자동으로 폐기/업데이트됨

---

#### ✅ (2) SG 및 TargetGroup 자동 정리(Garbage Collection)
- Service 또는 Ingress 삭제 시, LBC는 자동으로 해당 **SG와 Target Group을 삭제**합니다.
- 이로써 **“남아 있는 보안그룹/열린 포트” 문제**를 원천 차단합니다.

> ⚠️ NodePort 수동 운영 시에는 서비스 삭제 후에도 포트 및 SG 설정이 그대로 남아있음 → 보안 리스크

---

#### ✅ (3) L7 기반 접근 제어 (ALB Security Integration)
- LBC는 **ALB의 L7 보안 기능**과 연동됩니다.
  - HTTPS/TLS Termination  
  - AWS WAF (Web Application Firewall)  
  - AWS Shield (DDoS Protection)  
  - ALB Listener Rules 기반 IP 제한, Header 기반 차단
- 이로 인해 IP·Header·Path 기반의 **세밀한 접근 통제 정책**을 인그레스 단위로 구성 가능

