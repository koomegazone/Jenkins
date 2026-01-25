# IRSA 만들기 스크립트

```
# Phase 1 - 권한 부여
chmod +x helmchart/create-irsa.sh


# Phase 2 - Front 클러스터 (prismfo)
./helmchart/create-irsa.sh prism-q-an2-eks-cluster-front prismfo

# Phase 3 - Back 클러스터 (prismbo, prismopenapi, prismbatch)
./helmchart/create-irsa.sh prism-q-an2-eks-cluster-back prismbo
./helmchart/create-irsa.sh prism-q-an2-eks-cluster-back prismopenapi
./helmchart/create-irsa.sh prism-q-an2-eks-cluster-back prismbatch

```

# Helm Chart 작성 R&R 가이드

## 배경

현재 Helm Chart 작성 과정에서 불필요한 핑퐁으로 인한 업무 지연이 지속적으로 발생하고 있습니다.

### 주요 문제점
- **암호화 불가**: 메가존은 SDS 보유 사이트 접근 불가로 암호화 작업 불가
- **정보 부족**: IDP client secret 등 SDS 솔루션 관련 값을 메가존이 알 수 없음
- **반복적인 확인 사항**: 서비스명, 이미지, Ingress 구성, EFS 사용 여부 등 매번 확인 필요
- **트러블슈팅 한계**: 최근 MPP 배포 시 503 장애처럼 애플리케이션 호출 방법, Redis URL, 이미지 존재 여부 등을 메가존이 파악할 수 없어 장애 대응 지연

---

## R&R 정의

### 영주님 담당 영역

#### 1. application.yml 작성
- 애플리케이션 설정 파일 전체 작성
- 암호화 가능한 사이트를 메가존에 제공함

#### 2. Helm Chart 기본 정보 작성
AWS 지식 없이 작성 가능한 부분:



#### 3. 애플리케이션 상세 정보
- Redis , DB 연결 정보
- 외부 API (IDP)
- S3 버킷정보
- KMS 정보
- Secret Manager 정보 

---

### EKS 담당 영역

#### 1. AWS 리소스 관련 설정
```yaml
# values.yaml 예시

# 서비스명 (필수)
fullnameOverride: "prism-cm"  # prism-cm, amto-en, air-ms 등

# 이미지 정보 (필수)
image:
  repository: "your-registry/prism-cm"
  tag: "v1.0.0"
  pullPolicy: IfNotPresent

```


#### 2. 네트워크 및 보안 설정
- Security Group ID 입력
- Subnet ID 입력
- 도메인 정보 입력

```
# Ingress 사용 여부 (필수 - 주석으로라도 명시)
ingress:
  enabled: true
  # INT: 내부망 사용
  # EXT: 외부망 사용
  type: "INT"  # 또는 "EXT"
  hosts:
    - host: prismq.one.secc.co.kr
      paths:
        - path: /
          pathType: Prefix

# EFS 사용 여부 (필수 - 주석으로라도 명시)
persistence:
  enabled: false  # EFS 사용 시 true
  # storageClass: "efs-sc"
  # size: 10Gi

```

---

## 사전 제공 필수 정보 체크리스트

개발사는 Helm Chart 작성 요청 시 아래 정보를 **반드시 사전에 제공**해야 합니다:

### ✅ 필수 정보

| 항목 | 예시 | 비고 |
|------|------|------|
| **서비스명** | `prism-cm`, `amto-en`, `air-ms` | fullnameOverride에 사용 |
| **이미지 정보** | `registry.example.com/prism-cm:v1.0.0` | repository + tag |
| **도메인 정보** | INT: `prismq.one.secc.co.kr`<br>EXT: `prism.secc.co.kr` | 도메인은 미리 확인 하여 줄것 |
| **환경 변수** | Redis URL, DB 정보 등 | application.yml 작성은 영주님이 진행 |

### 📋 추가 정보 (해당 시)

- **Redis 사용 여부** 및 연결 정보
- **외부 API 의존성** (IDP, 결제 시스템 등)
- **특이사항** (특정 헤더 필요, 세션 고정 등)

---

## DevOps 파이프라인 협업 프로세스

### 1단계: Repository 준비
```
SDS: Git Repository 생성 및 메가존 권한 부여
```

### 2단계: 병렬 작업
```
메가존: overwrite-values.yaml 작성 (AWS 리소스)
개발사: values.yaml + application.yml 작성 (앱 설정)
```

### 3단계: 통합 및 배포
```
메가존: Helm Chart 통합 및 배포 테스트
개발사: 애플리케이션 동작 검증
```

---

## 트러블슈팅 책임 범위

### 메가존 책임
- AWS 리소스 관련 이슈 (LB, EFS, IAM 등)
- Kubernetes 리소스 이슈 (Pod 스케줄링, 네트워크 등)
- 인프라 레벨 모니터링

### 개발사 책임
- 애플리케이션 로직 오류
- 이미지 빌드 및 레지스트리 이슈
- 애플리케이션 설정 오류 (application.yml)
- 외부 의존성 연결 문제 (Redis, DB, API 등)

### 공동 책임
- 배포 프로세스 개선
- 장애 발생 시 협업 대응

---

## 체크리스트 템플릿

배포 요청 시 아래 템플릿을 작성하여 제출:

```markdown
## Helm Chart 배포 요청

### 기본 정보
- [ ] 서비스명: `prism-cm`
- [ ] 이미지: `registry.example.com/prism-cm:v1.0.0`

### 네트워크
- [ ] Ingress 사용: INT / EXT / 미사용
- [ ] 도메인: `prismq.one.secc.co.kr`

### 스토리지
- [ ] EFS 사용: 예 / 아니오
- [ ] 필요 용량: `10Gi` (사용 시)

### Application.yaml
- [ ] Redis Host,Port 접속 정보 체크
- [ ] RDS(postgres RDB) 접속 정보 체크 
- [ ] 외부 API: IDP 및 SDS 보안 솔루션 
- [ ] AWS 리소스 : KMS, Secret Manager ,S3 bucket+ URL , api-gateway  


```

---

## 기대 효과

1. **업무 지연 최소화**: 사전 정보 제공으로 핑퐁 감소
2. **명확한 책임 범위**: R&R 정의로 트러블슈팅 효율화
3. **배포 속도 향상**: 병렬 작업으로 리드타임 단축
4. **장애 대응 개선**: 각자 전문 영역에 집중
