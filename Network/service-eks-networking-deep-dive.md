![](https://capsule-render.vercel.app/api?type=transparent&fontColor=ff69b4&text=🔗%20Service와%20IPTables%20Deep%20Dive&height=150&fontSize=40&desc=EKS%20네트워크의%20핵심%20-%20svc.cluster.local에%20대해서%20알아보자&descAlignY=75&descAlign=50)

---

## 1. Kubernetes Service란?

Kubernetes에서 Pod는 생성과 삭제를 반복하며 IP가 수시로 바뀝니다. **Service**는 이런 Pod 집합에 대해 안정적인 네트워크 엔드포인트를 제공하는 추상화 계층입니다.

```
클라이언트 → Service (ClusterIP) → Pod A / Pod B / Pod C
              10.100.50.10         10.0.1.15  10.0.1.16  10.0.2.20
```

Service는 고정된 **ClusterIP**와 **DNS 이름**을 가지며, 뒤에 있는 Pod가 바뀌어도 클라이언트는 동일한 주소로 접근할 수 있습니다.

### Service의 종류

| 타입 | 설명 | 접근 범위 |
|------|------|----------|
| ClusterIP | 클러스터 내부 전용 가상 IP | 클러스터 내부만 |
| NodePort | 모든 노드의 특정 포트로 노출 | 클러스터 외부 |
| LoadBalancer | 클라우드 LB 자동 생성 (EKS → NLB/ALB) | 인터넷/VPC |
| ExternalName | 외부 DNS를 CNAME으로 매핑 | DNS 레벨 |

---

## 2. svc.cluster.local: Service DNS의 구조

### 2.1 CoreDNS와 Service Discovery

EKS 클러스터에는 **CoreDNS**가 배포되어 있으며, 모든 Service는 자동으로 DNS 레코드가 생성됩니다.

### 2.2 DNS 이름 규칙

```
<service-name>.<namespace>.svc.cluster.local
```

예시:

| Service | Namespace | FQDN |
|---------|-----------|------|
| nginx | default | nginx.default.svc.cluster.local |
| api-server | backend | api-server.backend.svc.cluster.local |
| redis | cache | redis.cache.svc.cluster.local |

### 2.3 DNS 조회 흐름

```
┌─ Pod A ──────────────────────────────────────────────────────┐
│                                                               │
│  curl http://nginx.default.svc.cluster.local                 │
│                                                               │
│  1. /etc/resolv.conf 확인                                     │
│     nameserver 10.100.0.10  ← CoreDNS ClusterIP              │
│     search default.svc.cluster.local svc.cluster.local ...   │
│                                                               │
│  2. "nginx" 만 입력해도 search 도메인이 자동 추가됨             │
│     nginx → nginx.default.svc.cluster.local 으로 확장          │
│                                                               │
└───────────────────────┬───────────────────────────────────────┘
                        │ DNS Query
                        ▼
┌─ CoreDNS (10.100.0.10) ─────────────────────────────────────┐
│                                                               │
│  3. kubernetes 플러그인이 API Server에서 Service 정보 조회     │
│  4. nginx.default.svc.cluster.local → 10.100.50.10 응답      │
│     (ClusterIP 반환)                                          │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

### 2.4 resolv.conf의 ndots와 search 도메인

```bash
# Pod 내부의 /etc/resolv.conf
nameserver 10.100.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

- `ndots:5` → 이름에 점(.)이 5개 미만이면 search 도메인을 먼저 시도
- `nginx` (점 0개) → `nginx.default.svc.cluster.local` 먼저 조회
- `google.com` (점 1개) → search 도메인 순서대로 시도 후 마지막에 절대 이름으로 조회
- 외부 도메인 조회 시 불필요한 DNS 쿼리가 발생할 수 있음 → FQDN 끝에 `.` 붙이면 해결

```bash
# 비효율적 (search 도메인 4번 시도 후 최종 조회)
curl http://google.com

# 효율적 (바로 절대 이름으로 조회)
curl http://google.com.
```

---

## 3. ClusterIP의 정체: 가상 IP

ClusterIP는 **어떤 네트워크 인터페이스에도 바인딩되지 않는 가상 IP**입니다. ping이 되지 않으며, 오직 **iptables(또는 IPVS) 규칙**에 의해서만 의미를 가집니다.

```bash
# ClusterIP로 ping → 응답 없음 (정상)
$ ping 10.100.50.10
PING 10.100.50.10: 56 data bytes
^C  # 응답 없음

# ClusterIP로 curl → 정상 동작
$ curl http://10.100.50.10:80
<!DOCTYPE html>...
```

이것이 가능한 이유는 **kube-proxy가 iptables 규칙을 설정**하여, ClusterIP:Port로 향하는 TCP/UDP 패킷을 실제 Pod IP로 DNAT(Destination NAT) 하기 때문입니다.

---

## 4. kube-proxy와 iptables: Service의 실체

### 4.1 kube-proxy의 역할

kube-proxy는 모든 노드에서 DaemonSet으로 실행되며, API Server를 watch하여 Service/Endpoints 변경을 감지하고 **iptables 규칙을 동적으로 갱신**합니다.

```
┌─────────────────────────────────────────────────────────┐
│                    API Server                            │
│                                                          │
│  Service: nginx-svc (10.100.50.10:80)                   │
│  Endpoints: [10.0.1.15:80, 10.0.1.16:80, 10.0.2.20:80] │
│                                                          │
└──────────────────────┬──────────────────────────────────┘
                       │ Watch
          ┌────────────┼────────────┐
          ▼            ▼            ▼
     ┌─────────┐ ┌─────────┐ ┌─────────┐
     │kube-proxy│ │kube-proxy│ │kube-proxy│
     │ Node 1   │ │ Node 2   │ │ Node 3   │
     └────┬─────┘ └────┬─────┘ └────┬─────┘
          │            │            │
          ▼            ▼            ▼
     iptables 규칙  iptables 규칙  iptables 규칙
     갱신           갱신           갱신
```

### 4.2 iptables 규칙 상세 분석

nginx-svc (ClusterIP: 10.100.50.10, Port: 80)에 3개의 Pod가 연결된 경우의 iptables 체인 구조:

```
패킷 흐름: PREROUTING → KUBE-SERVICES → KUBE-SVC-xxx → KUBE-SEP-xxx → Pod

┌─────────────────────────────────────────────────────────────────────┐
│                        iptables NAT 테이블                          │
│                                                                      │
│  Chain PREROUTING                                                    │
│  └→ -j KUBE-SERVICES    (모든 패킷을 KUBE-SERVICES로)               │
│                                                                      │
│  Chain KUBE-SERVICES                                                 │
│  └→ -d 10.100.50.10/32 -p tcp --dport 80 -j KUBE-SVC-NGINX         │
│     (ClusterIP:Port 매칭 시 해당 Service 체인으로)                    │
│                                                                      │
│  Chain KUBE-SVC-NGINX  ← Service 체인 (로드밸런싱)                   │
│  ├→ -m statistic --mode random --probability 0.33333                │
│  │  -j KUBE-SEP-AAA     (33.3% 확률로 Pod A)                        │
│  ├→ -m statistic --mode random --probability 0.50000                │
│  │  -j KUBE-SEP-BBB     (나머지의 50% = 33.3% 확률로 Pod B)         │
│  └→ -j KUBE-SEP-CCC     (나머지 전부 = 33.3% 확률로 Pod C)          │
│                                                                      │
│  Chain KUBE-SEP-AAA  ← Endpoint 체인 (DNAT)                         │
│  └→ -p tcp -j DNAT --to-destination 10.0.1.15:80                    │
│                                                                      │
│  Chain KUBE-SEP-BBB                                                  │
│  └→ -p tcp -j DNAT --to-destination 10.0.1.16:80                    │
│                                                                      │
│  Chain KUBE-SEP-CCC                                                  │
│  └→ -p tcp -j DNAT --to-destination 10.0.2.20:80                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.3 확률 기반 로드밸런싱의 수학

iptables는 순차적으로 규칙을 평가하므로, 균등 분배를 위해 확률을 조정합니다:

```
Pod 3개인 경우:
  규칙 1: probability = 1/3 = 0.33333  → Pod A 선택 확률 33.3%
  규칙 2: probability = 1/2 = 0.50000  → 나머지(66.7%)의 50% = 33.3%
  규칙 3: (기본)                        → 나머지 전부 = 33.3%

Pod 4개인 경우:
  규칙 1: probability = 1/4 = 0.25000  → 25%
  규칙 2: probability = 1/3 = 0.33333  → 75% × 33.3% = 25%
  규칙 3: probability = 1/2 = 0.50000  → 50% × 50% = 25%
  규칙 4: (기본)                        → 나머지 = 25%
```

### 4.4 DNAT 이후의 패킷 흐름

```
┌─ 클라이언트 Pod ─────────────────────────────────────────────────┐
│                                                                   │
│  curl http://10.100.50.10:80                                     │
│  패킷: src=10.0.1.15 dst=10.100.50.10 dport=80                  │
│                                                                   │
└───────────────────────┬───────────────────────────────────────────┘
                        │
                        ▼ iptables DNAT 적용
┌─ iptables ────────────────────────────────────────────────────────┐
│                                                                    │
│  DNAT: dst 10.100.50.10:80 → 10.0.2.20:80                        │
│  변환된 패킷: src=10.0.1.15 dst=10.0.2.20 dport=80               │
│                                                                    │
│  conntrack 테이블에 기록:                                          │
│  10.0.1.15:54321 → 10.100.50.10:80 → 10.0.2.20:80               │
│                                                                    │
└───────────────────────┬───────────────────────────────────────────┘
                        │
                        ▼ VPC 라우팅으로 실제 Pod에 전달
┌─ 대상 Pod (10.0.2.20) ──────────────────────────────────────────┐
│                                                                   │
│  수신 패킷: src=10.0.1.15 dst=10.0.2.20 dport=80                │
│  응답 패킷: src=10.0.2.20 dst=10.0.1.15                         │
│                                                                   │
└───────────────────────┬───────────────────────────────────────────┘
                        │
                        ▼ conntrack이 역변환 (Reverse DNAT)
┌─ 클라이언트 Pod ─────────────────────────────────────────────────┐
│                                                                   │
│  수신 패킷: src=10.100.50.10 dst=10.0.1.15                      │
│  (conntrack이 src를 ClusterIP로 복원 → 클라이언트는 ClusterIP와   │
│   통신한 것으로 인식)                                              │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## 5. 실습: iptables 규칙 직접 확인하기

### 5.1 Service 생성

```yaml
# nginx-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-svc
  namespace: default
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
```

### 5.2 iptables 규칙 확인

```bash
# 노드에 SSH 접속 후

# Service 관련 KUBE-SERVICES 체인 확인
$ sudo iptables -t nat -L KUBE-SERVICES -n | grep nginx

KUBE-SVC-V2OKYYMBY3REGZOG  tcp  --  0.0.0.0/0  10.100.50.10  tcp dpt:80

# Service 체인의 로드밸런싱 규칙 확인
$ sudo iptables -t nat -L KUBE-SVC-V2OKYYMBY3REGZOG -n
Chain KUBE-SVC-V2OKYYMBY3REGZOG (1 references)
target                     prot  source    destination
KUBE-SEP-AAA               all   0.0.0.0/0  0.0.0.0/0  statistic mode random probability 0.33333
KUBE-SEP-BBB               all   0.0.0.0/0  0.0.0.0/0  statistic mode random probability 0.50000
KUBE-SEP-CCC               all   0.0.0.0/0  0.0.0.0/0

# Endpoint 체인의 DNAT 규칙 확인
$ sudo iptables -t nat -L KUBE-SEP-AAA -n
Chain KUBE-SEP-AAA (1 references)
target  prot  source       destination
DNAT    tcp   0.0.0.0/0    0.0.0.0/0  tcp to:10.0.1.15:80
```

### 5.3 conntrack 테이블 확인

```bash
# 현재 연결 추적 상태 확인
$ sudo conntrack -L -d 10.100.50.10
tcp  6 117 TIME_WAIT src=10.0.1.15 dst=10.100.50.10 sport=54321 dport=80 \
  src=10.0.2.20 dst=10.0.1.15 sport=80 dport=54321 [ASSURED] mark=0 use=1

# → 원본: 10.0.1.15 → 10.100.50.10:80
# → 변환: 10.0.1.15 → 10.0.2.20:80 (DNAT 결과)
```

---

## 6. NodePort Service의 iptables

NodePort는 ClusterIP 위에 추가 규칙을 쌓는 구조입니다.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-nodeport
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

```
iptables 체인 흐름:

Chain KUBE-NODEPORTS
└→ -p tcp --dport 30080 -j KUBE-SVC-NGINX
   (노드의 30080 포트로 들어온 트래픽 → Service 체인으로)

이후는 ClusterIP와 동일:
KUBE-SVC-NGINX → KUBE-SEP-xxx → DNAT → 실제 Pod
```

### externalTrafficPolicy 차이

```
┌─ externalTrafficPolicy: Cluster (기본값) ────────────────────┐
│                                                               │
│  외부 → Node A:30080 → iptables DNAT → Pod (어떤 노드든)     │
│  - 추가 hop 발생 가능 (Node A → Node B의 Pod)                │
│  - SNAT 적용 (클라이언트 IP 보존 안됨)                        │
│  - 균등한 로드밸런싱                                          │
│                                                               │
└───────────────────────────────────────────────────────────────┘

┌─ externalTrafficPolicy: Local ────────────────────────────────┐
│                                                                │
│  외부 → Node A:30080 → 해당 노드의 Pod만 선택                 │
│  - 추가 hop 없음                                               │
│  - SNAT 없음 (클라이언트 IP 보존)                              │
│  - 해당 노드에 Pod 없으면 트래픽 드롭                          │
│  - Health Check로 Pod 있는 노드만 LB 타겟에 유지               │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 7. EKS에서의 LoadBalancer Service

### 7.1 NLB (Network Load Balancer) 연동

EKS에서 `type: LoadBalancer` Service를 생성하면 AWS Load Balancer Controller가 NLB를 프로비저닝합니다.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-nlb
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
```

### 7.2 Target Type 비교

```
┌─ target-type: instance ──────────────────────────────────────┐
│                                                               │
│  NLB → NodePort(30080) → iptables → Pod                     │
│  - 기존 NodePort 방식과 동일                                  │
│  - 추가 hop 발생 가능                                         │
│                                                               │
└───────────────────────────────────────────────────────────────┘

┌─ target-type: ip ────────────────────────────────────────────┐
│                                                               │
│  NLB → Pod IP 직접 (VPC CNI 덕분에 가능)                     │
│  - iptables 우회, Pod에 직접 도달                             │
│  - 낮은 레이턴시, 클라이언트 IP 보존                          │
│  - VPC CNI의 네이티브 IP 할당이 핵심                          │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

---

## 8. Headless Service: ClusterIP 없는 Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-headless
spec:
  clusterIP: None    # Headless
  selector:
    app: nginx
  ports:
    - port: 80
```

Headless Service는 ClusterIP를 할당하지 않으며, DNS 조회 시 **Pod IP 목록을 직접 반환**합니다.

```bash
# 일반 Service DNS 조회 → ClusterIP 1개 반환
$ nslookup nginx-svc.default.svc.cluster.local
Address: 10.100.50.10

# Headless Service DNS 조회 → Pod IP 전부 반환
$ nslookup nginx-headless.default.svc.cluster.local
Address: 10.0.1.15
Address: 10.0.1.16
Address: 10.0.2.20
```

StatefulSet과 함께 사용하면 개별 Pod에 고유 DNS가 부여됩니다:

```
<pod-name>.<headless-svc>.<namespace>.svc.cluster.local
예: nginx-0.nginx-headless.default.svc.cluster.local → 10.0.1.15
```

---

## 9. IPVS 모드: iptables의 대안

대규모 클러스터(Service 1000개 이상)에서는 iptables 규칙이 수만 개로 늘어나 성능 저하가 발생합니다. IPVS 모드는 이를 해결합니다.

| 비교 항목 | iptables | IPVS |
|-----------|----------|------|
| 규칙 탐색 | O(n) 순차 탐색 | O(1) 해시 테이블 |
| 로드밸런싱 | 확률 기반 (random) | rr, wrr, lc, sh 등 다양 |
| 대규모 성능 | Service 증가 시 느려짐 | 일정한 성능 유지 |
| 연결 추적 | conntrack | 자체 연결 테이블 |

```bash
# EKS에서 IPVS 모드 활성화 (kube-proxy ConfigMap)
kubectl edit configmap kube-proxy-config -n kube-system
# mode: "ipvs" 로 변경
```

---

## 10. 전체 패킷 흐름 정리

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Service 통신 전체 흐름                            │
│                                                                      │
│  1. Pod A: curl nginx-svc                                           │
│     │                                                                │
│     ▼                                                                │
│  2. DNS 조회 (CoreDNS)                                              │
│     nginx-svc.default.svc.cluster.local → 10.100.50.10              │
│     │                                                                │
│     ▼                                                                │
│  3. 패킷 생성: dst=10.100.50.10:80                                  │
│     │                                                                │
│     ▼                                                                │
│  4. iptables PREROUTING → KUBE-SERVICES                             │
│     ClusterIP 매칭 → KUBE-SVC-xxx 체인                              │
│     │                                                                │
│     ▼                                                                │
│  5. 확률 기반 로드밸런싱 → KUBE-SEP-xxx 선택                        │
│     │                                                                │
│     ▼                                                                │
│  6. DNAT: dst 10.100.50.10:80 → 10.0.2.20:80                       │
│     conntrack에 매핑 기록                                            │
│     │                                                                │
│     ▼                                                                │
│  7. VPC CNI 네이티브 라우팅으로 실제 Pod에 전달                      │
│     (veth pair → Host 라우팅 → VPC 라우팅)                          │
│     │                                                                │
│     ▼                                                                │
│  8. Pod B 응답 → conntrack 역변환 → Pod A 수신                      │
│     (src가 ClusterIP로 복원되어 투명하게 동작)                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 핵심 요약

1. **Service**는 Pod 집합에 안정적인 ClusterIP와 DNS(`svc.cluster.local`)를 제공합니다.
2. **CoreDNS**가 Service 이름을 ClusterIP로 변환하며, `ndots:5`와 search 도메인으로 짧은 이름도 해석합니다.
3. **ClusterIP는 가상 IP**로, iptables DNAT 규칙에 의해서만 실제 Pod IP로 변환됩니다.
4. **kube-proxy**가 iptables 규칙을 동적으로 관리하며, 확률 기반으로 균등한 로드밸런싱을 수행합니다.
5. **conntrack**이 연결 상태를 추적하여 응답 패킷의 역변환(Reverse DNAT)을 처리합니다.
6. **VPC CNI**의 네이티브 IP 덕분에 NLB가 Pod IP를 직접 타겟으로 사용할 수 있습니다.

---

> 참고 자료
> - [Kubernetes Service 공식 문서](https://kubernetes.io/docs/concepts/services-networking/service/)
> - [CoreDNS for Kubernetes](https://coredns.io/plugins/kubernetes/)
> - [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
> - [iptables 튜토리얼](https://www.frozentux.net/iptables-tutorial/iptables-tutorial.html)
