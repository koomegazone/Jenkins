![Kubernetes](https://img.shields.io/badge/-Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/-Terraform-7B42BC?style=flat-square&logo=terraform&logoColor=white)
![Helm](https://img.shields.io/badge/-Helm-0F1689?style=flat-square&logo=helm&logoColor=white)
![ArgoCD](https://img.shields.io/badge/-ArgoCD-EF7B4D?style=flat-square&logo=argo&logoColor=white)
![Flux](https://img.shields.io/badge/-Flux-5468FF?style=flat-square&logo=flux&logoColor=white)




![header](https://capsule-render.vercel.app/api?type=transparent&fontColor=00bfff&text=🚀%20EKS%20GitOps%20%26%20Platform%20Engineering&height=150&fontSize=38&desc=DevOps%20→%20GitOps%20→%20플랫폼%20엔지니어링%20완전%20정복&descAlignY=75&descAlign=50)

---
title: "Amazon EKS에서 GitOps와 플랫폼 엔지니어링 완전 정복"
date: 2026-04-24
tags: [EKS, GitOps, ArgoCD, Flux, Platform Engineering, SaaS, Kubernetes, DevOps]
---

> GitOps 도구는 많은데 뭘 써야 하지? ArgoCD vs Flux는 또 뭐가 다르지? 플랫폼 엔지니어링은 GitOps랑 무슨 관계야?  
> 이 글에서 그 질문들을 한 번에 정리해봤다.

---

## 들어가며

AWS re:Invent 2025에서 **EKS Managed ArgoCD**가 발표되면서 GitOps 생태계가 다시 뜨거워졌다.  
ArgoCD를 직접 운영하던 팀들은 "이거 써야 하나 말아야 하나" 고민이 시작됐을 것이다.

이 글은 단순히 도구 비교에서 끝나지 않는다. GitOps가 왜 **플랫폼 엔지니어링의 핵심 방법론**인지, SaaS 멀티테넌트 환경에서 어떻게 활용하는지까지 큰 그림으로 정리했다.

참고 자료: [AWS Prescriptive Guidance - EKS GitOps Tools](https://docs.aws.amazon.com/prescriptive-guidance/latest/eks-gitops-tools/introduction.html)

---

## 1. EKS에서 쓸 수 있는 GitOps 도구들

도구가 많아서 처음엔 어디서부터 봐야 할지 막막하다. 일단 전체를 한눈에 보자.

| 도구 | Kubernetes 특화도 | 관리 방식 | 한 줄 요약 |
|---|:-:|---|---|
| **Argo CD** | ⭐⭐⭐ | 자체 설치 or EKS Managed | Web UI 강점, 멀티 클러스터 운영의 표준 |
| **Flux v2** | ⭐⭐⭐ | 자체 설치 | CLI 중심, Terraform 통합 최강 (Tofu Controller) |
| **Weave GitOps** | ⭐⭐ | 자체 설치 (상용 존재) | Flux 위에 Web UI 얹은 버전 |
| **Rancher Fleet** | ⭐⭐ | 자체 설치 (Rancher 생태계) | 수천 개 클러스터 대규모 관리 특화 |
| **Jenkins X** | ⭐ | 자체 설치 (복잡) | 기존 Jenkins 생태계를 Kubernetes로 이전할 때 |
| **GitLab CI/CD** | ⭐ | SaaS or 자체 설치 | 코드 저장소 ~ 배포까지 단일 플랫폼 |
| **Codefresh** | ⭐ | SaaS (유료) | ArgoCD 기반 엔터프라이즈 관리형 서비스 |
| **Spinnaker** | ⭐ | 자체 설치 (무거움) | Netflix 개발, 멀티 클라우드 복잡한 배포 전략 |

> 💡 **Tip**
>
> EKS 환경에서 처음 GitOps를 도입한다면 **ArgoCD** 또는 **Flux v2** 중 하나를 선택하는 게 정답에 가깝다.
> 나머지 도구들은 특수한 요구사항이 있을 때 검토하면 된다.

---

## 2. ArgoCD vs Flux v2 — 진짜 차이는 뭔가

둘 다 CNCF 프로젝트고, 둘 다 GitOps를 잘 지원한다. 그런데 왜 자꾸 비교를 하냐면... **철학이 다르기 때문이다.**

| 영역 | Argo CD | Flux v2 |
|---|---|---|
| **아키텍처** | 엔드투엔드 GitOps 애플리케이션 | GitOps를 위한 CRD + 컨트롤러 조합 |
| **UI** | 완전한 Web UI 내장 | CLI 중심, 경량 UI 선택적 |
| **설정 난이도** | 상대적으로 간편 | 상대적으로 복잡 |
| **RBAC** | 자체 RBAC 시스템 내장 | Kubernetes 네이티브 RBAC 활용 |
| **멀티클러스터** | ✅ 탁월한 지원 | 🔶 가능하지만 멀티테넌시에 더 강점 |
| **멀티테넌시** | 🔶 가능 | ✅ 탁월한 지원 |
| **Helm/Kustomize** | ✅ 둘 다 지원 | ✅ 둘 다 지원 |
| **IaC 통합** | 제한적 | ✅ Tofu Controller로 Terraform 통합 |
| **부분 동기화** | ✅ 지원 | ❌ 미지원 |
| **확장성** | 커스텀 플러그인 (제한적) | 커스텀 컨트롤러 (높은 확장성) |
| **커뮤니티** | 크고 활발함 | 성장 중 |

### 어떤 걸 선택해야 할까?

```
ArgoCD를 선택해야 할 때:
  ✅ Web UI로 배포 현황을 시각화하고 싶을 때
  ✅ 여러 EKS 클러스터를 하나의 컨트롤 플레인으로 관리할 때
  ✅ 팀원 중 Kubernetes 초보자가 있어서 UI가 필요할 때
  ✅ EKS Managed ArgoCD를 활용해 운영 부담을 줄이고 싶을 때

Flux v2를 선택해야 할 때:
  ✅ GitOps + Terraform(IaC)을 하나로 통합하고 싶을 때
  ✅ 멀티테넌트 SaaS 환경에서 테넌트별 격리가 중요할 때
  ✅ 높은 확장성과 서드파티 통합이 필요할 때
  ✅ CLI 기반 자동화 파이프라인 중심으로 운영할 때
```

> 📌 **핵심 요약**
>
> - ArgoCD = 시각화와 멀티클러스터 관리에 강점
> - Flux v2 = 멀티테넌시와 IaC 통합에 강점
> - 둘 다 수만 개 앱을 지원하는 엔터프라이즈급 확장성을 갖춤

---

## 3. Self-Managed ArgoCD vs EKS Managed ArgoCD

re:Invent 2025에서 **EKS Managed ArgoCD**가 출시됐다. 핵심 엔진을 AWS가 관리해주는 방식인데, 기존 자체 설치 방식과 어떤 차이가 있는지 정리했다.

| 구분 | Self-Managed | EKS Managed |
|---|---|---|
| **설치** | Helm/kubectl로 직접 설치 | AWS 콘솔, CDK, Terraform으로 활성화 |
| **컴포넌트 위치** | 사용자 클러스터 내부 전부 | 핵심 엔진은 AWS 관리 계정에 위치 |
| **운영 책임** | 설치/확장/가용성/보안 모두 사용자 | AWS가 모니터링, 패치, 상태 관리 담당 |
| **확장** | CPU/메모리 직접 관리 | 부하에 따라 AWS가 자동 확장 |
| **HA 구성** | 직접 설계 필요 | AWS가 자동 관리 |
| **버전 업그레이드** | 수동 (다운타임 계획 필요) | AWS가 자동 관리 |
| **인증** | Dex / OIDC 직접 구성 | AWS Identity Center 통합 |
| **CLI 제한** | 제한 없음 | `argocd admin`, `argocd login` 미지원 |
| **클러스터 지원** | 모든 Kubernetes | Amazon EKS만 지원 (ARN 기반) |
| **Pod 직접 접근** | 가능 | 불가 (AWS 관리 영역) |

> ⚠️ **Warning**
>
> EKS Managed ArgoCD는 **EKS 클러스터 전용**이다.
> 온프레미스나 타 클라우드 Kubernetes 클러스터를 함께 관리해야 한다면 Self-Managed를 유지해야 한다.
> `argocd admin`, `argocd login` 명령어가 지원되지 않으므로, 이에 의존하는 자동화 스크립트가 있다면 사전에 검토가 필요하다.

### 언제 Managed로 전환해야 할까?

```
전환을 고려할 때:
  ✅ ArgoCD 운영 오버헤드(업그레이드, HA 구성, 모니터링)에 지쳐있을 때
  ✅ EKS 전용으로만 사용하고 있을 때
  ✅ AWS Identity Center를 이미 쓰고 있을 때

전환을 보류할 때:
  ❌ EKS 외 클러스터도 ArgoCD로 관리할 때
  ❌ argocd admin / argocd login CLI에 의존하는 자동화가 있을 때
  ❌ ArgoCD Pod에 직접 접근이 필요한 커스터마이징을 쓸 때
```

---

## 4. SaaS 멀티테넌트 환경에서 GitOps가 필요한 이유

GitOps가 왜 SaaS에 잘 맞는지, 먼저 SaaS의 핵심 과제부터 보자.

### SaaS의 3가지 핵심 과제

```
1. 잦은 릴리스  → 빠른 피드백과 기능 제공
2. 운영 효율성  → 모든 테넌트를 동일한 프로세스로 일관 관리
3. 자동 온보딩  → 신규 테넌트 생성을 빠르고 일관되게
```

이 세 가지를 동시에 만족시키는 방법이 바로 **GitOps**다.

### 테넌트 격리 모델 선택

| 모델 | 격리 수준 | 비용 | 대표 활용 |
|---|:-:|:-:|---|
| **사일로 (Silo)** | 높음 | 높음 | Premium 티어 — 테넌트 전용 인프라 |
| **풀 (Pool)** | 낮음 | 낮음 | Basic 티어 — 인프라 공유 |
| **하이브리드** | 중간 | 중간 | 실제 SaaS의 대부분 — 티어별 혼합 운영 |

> 💡 **Tip**
>
> 실제 SaaS 서비스는 대부분 **하이브리드** 모델을 쓴다.
> 고가 티어 고객에겐 사일로 모델로 강한 격리를 제공하고,
> 일반 고객에겐 풀 모델로 비용 효율성을 확보하는 방식이다.

### GitOps가 SaaS에 적합한 이유

| SaaS 요구사항 | GitOps가 제공하는 것 |
|---|---|
| 일관된 환경 보장 | Git = 단일 정보 소스 (Single Source of Truth) |
| 자동화된 테넌트 프로비저닝 | 선언적 구성 + 자동 Reconciliation |
| 변경 이력 관리 | PR 기반 변경 관리 + 감사 로그 |
| 셀프 서비스 배포 | Git Push → 자동 배포 |
| 멀티테넌트 관리 | Flux v2 멀티테넌시 지원 |

---

## 5. GitOps 기반 EKS SaaS 레퍼런스 아키텍처

AWS Prescriptive Guidance에서 제시하는 레퍼런스 아키텍처의 핵심을 정리했다.

### 기술 스택

| 구분 | 기술 | 역할 |
|---|---|---|
| GitOps 엔진 | **Flux v2** | Git ↔ 클러스터 자동 동기화 |
| 워크플로우 | **Argo Workflows** | 복잡한 온보딩 워크플로우 자동화 |
| 패키지 관리 | **Helm** | Kubernetes 리소스 패키징 |
| IaC | **Terraform + Tofu Controller** | 인프라 패키징 및 GitOps 통합 |
| 오케스트레이션 | **Amazon EKS** | 멀티테넌트 SaaS 운영 환경 |
| 메시지 큐 | **Amazon SQS** | Producer → Consumer 비동기 처리 |
| 데이터베이스 | **Amazon DynamoDB** | 테넌트별 데이터 저장 |

### 아키텍처 핵심 원칙

**1. 애플리케이션 + 인프라를 함께 패키징한다**

```
Helm Chart     → Kubernetes 리소스 (Deployment, Service, Ingress 등)
Terraform 모듈 → AWS 인프라 (DynamoDB, SQS, IAM 등)

⬇️

Flux Tofu Controller가 두 가지를 모두 Git으로 관리
기존 Terraform 모듈 수정 없이 재사용 가능
```

**2. 새 테넌트 온보딩 흐름**

```
신규 테넌트 요청
  → Argo Workflows가 온보딩 워크플로우 실행
  → Git에 테넌트 전용 Helm values + Terraform 변수 파일 생성
  → Flux v2가 변경 감지 → 자동 Reconciliation
  → EKS Namespace 생성 + AWS 인프라(DynamoDB, SQS) 프로비저닝
  → 테넌트 앱 배포 완료
```

**3. 샘플 테넌트 앱 구조**

```
클라이언트 API 호출
  → Producer (메시지 생성)
  → Amazon SQS Queue
  → Consumer (메시지 처리)
  → Amazon DynamoDB (테넌트 전용 테이블)
```

> 📌 **핵심 요약**
>
> - Flux v2는 **immutable 방화벽**처럼 동작 — Git에 없는 변경은 클러스터에 반영 안 됨
> - 모든 테넌트가 동일한 Helm Chart + Terraform 모듈로 배포됨 → 패키지 무결성 보장
> - Tofu Controller 덕분에 기존 Terraform 코드를 그대로 GitOps에 통합 가능

---

## 6. DevOps → GitOps → 플랫폼 엔지니어링 진화 흐름

왜 이 세 가지가 항상 같이 언급되는지, 진화의 흐름을 보면 이해가 쉽다.

### 단계별 핵심 개념

| 단계 | 핵심 개념 | 개발자가 경험하는 것 |
|---|---|---|
| **DevOps** | 개발 + 운영 협업, CI/CD 자동화 | "배포 자동화됐다!" |
| **GitOps** | Git = 단일 정보 소스, 선언적 인프라, 자동 동기화 | "Git에 Push하면 클러스터에 반영된다!" |
| **플랫폼 엔지니어링** | IDP를 통한 셀프 서비스, 추상화 레이어 | "인프라 몰라도 앱 배포 된다!" |

### 플랫폼 엔지니어링이란?

쉽게 말하면 **"개발자가 인프라를 몰라도 되는 세상을 만드는 것"** 이다.

**Before (추상화 없음):**
```
개발자가 직접 조립해야 하는 것들:
  VPC → Subnet → IGW → NAT
  IAM Role → Security Group
  EKS → Node Group → ECR
  ALB → Target Group
  RDS → ElastiCache → SQS → DynamoDB
  ... (끝이 없다)
```

**After (플랫폼 추상화):**
```bash
# 개발자가 하는 일의 전부
git push origin main
# → CI 빌드 → 이미지 빌드 → GitOps Sync → EKS 배포
# (보안/거버넌스/확장성은 플랫폼이 자동으로 보장)
```

### 플랫폼 엔지니어링의 3대 이점

| 이점 | 설명 | 효과 |
|---|---|---|
| 🚀 **속도 (Velocity)** | 셀프 서비스 배포 제공 | 아이디어 → 프로덕션 시간 단축 |
| 🛡️ **거버넌스 (Governance)** | 보안/신뢰성/확장성을 플랫폼에서 자동화 | 일관된 정책 강제, 컴플라이언스 확보 |
| 💰 **효율성 (Efficiency)** | 멀티테넌시 + 전문성 중앙 집중화 | 인프라 비용 절감, 인력 최적화 |

### Internal Developer Platform (IDP) 계층 구조

```
[ 개발자 ]
    ↓ Git Push / 셀프 서비스 요청
[ Internal Developer Platform (IDP) ]
  ├── Self-Service API   (인프라 요청/프로비저닝)
  ├── CI/CD Pipeline     (빌드 → 배포 자동화)
  ├── Observability      (모니터링/로깅/알림)
  └── Knowledge Portal   (Docs, Runbooks)
    ↓ GitOps Sync (Flux v2 / ArgoCD)
[ Amazon EKS ]
  ├── Namespace: Tenant-A
  ├── Namespace: Tenant-B
  └── Namespace: Tenant-C
    ↓
[ AWS Cloud Infrastructure ]
  └── VPC / IAM / RDS / SQS / DynamoDB / S3 / ...

[ Platform Engineering Team ]  ← IDP 구축 및 운영 담당
```

### AWS 관점의 추상화 모델 선택

| 모델 | 제공 단위 | 자유도 | 적합한 조직 |
|---|---|:-:|---|
| **Account as a Service** | AWS 계정 | 매우 높음 | 팀별 완전 격리가 필요한 경우 |
| **Template as a Service** | 표준화된 IaC 템플릿 | 높음 | 표준 패턴 + 커스터마이징 |
| **Cluster as a Service** | EKS 클러스터 | 중간 | 팀별 독립 Kubernetes 환경 |
| **Namespace as a Service** | Kubernetes Namespace | 낮음 | 비용 효율적 멀티테넌트 운영 |
| **Platform as a Service** | 완전한 앱 실행 환경 | 매우 낮음 | 인프라 신경 쓰기 싫을 때 |

> ℹ️ **Info**
>
> Salesforce는 **Namespace as a Service** 모델을 활용한다.
> 수천 개 테넌트를 공유 클러스터에서 Namespace 단위로 격리하는 방식이다.
> 비용 효율성이 최우선이고 테넌트 간 강한 격리가 필요하지 않을 때 적합하다.

### 국내 플랫폼 엔지니어링 사례

| 회사 | 참고 자료 |
|---|---|
| **당근** | [당근 개발자 플랫폼은 어떤 문제를 해결하고 있는가](https://speakerdeck.com/outsider/danggeun-gaebalja-peulraespomeun-eoddeon-munjereul-haegyeolhago-issneunga) |
| **무신사** | [무신사 플랫폼 발표 영상](https://youtu.be/9FKbQRu6lVs) |

---

## 7. 전체 흐름 한눈에 보기

```
SaaS 요구사항
  (멀티테넌트, 잦은 릴리스, 자동화된 온보딩)
           ↓
    GitOps (Flux v2)
  ├── Helm Chart        → Kubernetes 리소스 패키징
  ├── Tofu Controller   → Terraform 인프라 패키징
  └── Argo Workflows    → 복잡한 온보딩 워크플로우 자동화
           ↓
    Amazon EKS
  ├── Namespace: Tenant-A (사일로 or 풀 모델)
  ├── Namespace: Tenant-B
  └── Namespace: Tenant-C ...
           ↓
    AWS 인프라
  └── DynamoDB / SQS / S3 / RDS / ...
```

> 📌 **핵심 요약**
>
> - **DevOps**: 개발과 운영의 협업 문화를 만든다
> - **GitOps**: Git을 단일 진실의 원천으로 삼아 자동 동기화를 구현한다
> - **플랫폼 엔지니어링**: IDP로 개발자에게 셀프 서비스를 제공하고, GitOps가 그 기반이 된다
> - **Flux v2**: 멀티테넌트 SaaS에서 Terraform 통합과 Kubernetes 네이티브 RBAC으로 가장 적합

---

## 마무리

GitOps는 단순히 "Git으로 배포 관리하는 것"이 아니다.  
**플랫폼 엔지니어링이라는 큰 그림 안에서 자동화된 거버넌스를 실현하는 핵심 방법론**이다.

도구 선택은 결국 팀의 상황에 따라 다르다:
- Web UI와 멀티클러스터 관리가 중요하다 → **ArgoCD**
- Terraform 통합과 멀티테넌시가 중요하다 → **Flux v2**
- ArgoCD 운영 부담을 줄이고 싶다 → **EKS Managed ArgoCD** 검토

다음엔 Flux v2의 Tofu Controller를 활용한 실제 멀티테넌트 SaaS 구성 예시를 코드 레벨로 다뤄볼 예정이다.

---

## 참고 링크

- [AWS Prescriptive Guidance - EKS GitOps Tools](https://docs.aws.amazon.com/prescriptive-guidance/latest/eks-gitops-tools/introduction.html)
- [AWS - EKS GitOps Use Cases](https://docs.aws.amazon.com/prescriptive-guidance/latest/eks-gitops-tools/use-cases.html)
- [당근 개발자 플랫폼 발표](https://speakerdeck.com/outsider/danggeun-gaebalja-peulraespomeun-eoddeon-munjereul-haegyeolhago-issneunga)
- [무신사 플랫폼 엔지니어링](https://youtu.be/9FKbQRu6lVs)
