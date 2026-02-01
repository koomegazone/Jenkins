# Cross-Zone 네트워크 비용 최적화 가이드

## 질문: TopologySpreadConstraints로 Cross-Zone 통신 비용이 절감되나요?

**답변: 아니요, TopologySpreadConstraints만으로는 Cross-Zone 통신이 자동으로 없어지지 않습니다.**

TopologySpreadConstraints는 **파드를 어디에 배치할지**만 결정하고, **트래픽이 어떻게 라우팅되는지**는 제어하지 않습니다.

## Cross-Zone 통신이 발생하는 시나리오

### 시나리오 1: Service의 기본 동작

```yaml
apiVersion: v1
kind: Service
metadata:
  name: msu-control
spec:
  type: ClusterIP
  selector:
    app: msu-control
  ports:
  - port: 80
```

**문제점**: 
- A존의 파드가 Service를 호출하면 → B존이나 C존의 파드로 라우팅될 수 있음
- Kubernetes Service는 기본적으로 **모든 존의 엔드포인트로 랜덤 로드밸런싱**
- Cross-Zone 트래픽 발생 → **데이터 전송 비용 발생** (AWS의 경우 GB당 $0.01~0.02)

### 시나리오 2: Ingress/LoadBalancer

```yaml
apiVersion: v1
kind: Service
metadata:
  name: msu-control
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
spec:
  type: LoadBalancer
```

**문제점**:
- NLB/ALB가 모든 존의 타겟으로 트래픽 분산
- 클라이언트가 A존에 있어도 C존의 파드로 라우팅 가능

## Cross-Zone 통신 비용 절감 방법

### 방법 1: Topology Aware Hints (권장) ⭐

Kubernetes 1.21+에서 사용 가능한 기능으로, **같은 존 내에서 트래픽을 우선 라우팅**합니다.

#### Service 설정

```yaml
apiVersion: v1
kind: Service
metadata:
  name: msu-control
  annotations:
    service.kubernetes.io/topology-mode: "Auto"  # 또는 "auto"
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: msu-control
  ports:
  - port: 80
    targetPort: 80
```

#### 동작 방식

1. A존의 클라이언트 → A존의 파드로 우선 라우팅
2. A존에 파드가 없거나 unhealthy하면 → 다른 존으로 라우팅
3. **자동으로 존 인식 라우팅** (kube-proxy가 처리)

#### 제약 사항

- 각 존에 최소 1개 이상의 파드가 있어야 함
- 파드가 균등하게 분산되어야 효과적 (TopologySpreadConstraints와 함께 사용!)
- CPU/메모리 사용률이 고르게 분산되어야 함

### 방법 2: Service Internal Traffic Policy

Kubernetes 1.22+에서 사용 가능하며, **무조건 같은 노드 내에서만** 트래픽을 라우팅합니다.

#### Service 설정

```yaml
apiVersion: v1
kind: Service
metadata:
  name: msu-control
spec:
  type: ClusterIP
  internalTrafficPolicy: Local  # 같은 노드의 파드로만 라우팅
  selector:
    app.kubernetes.io/name: msu-control
  ports:
  - port: 80
    targetPort: 80
```

#### 동작 방식

- 클라이언트와 **같은 노드**에 있는 파드로만 라우팅
- 같은 노드에 파드가 없으면 → **트래픽 실패** (주의!)

#### 장단점

**장점**:
- Cross-Zone 통신 완전 차단
- 네트워크 레이턴시 최소화

**단점**:
- 모든 노드에 파드가 있어야 함 (DaemonSet 스타일)
- 로드밸런싱이 불균등할 수 있음

### 방법 3: AWS Load Balancer Controller - Cross-Zone 비활성화

AWS NLB/ALB를 사용하는 경우 Cross-Zone Load Balancing을 비활성화할 수 있습니다.

#### Service 설정 (NLB)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: msu-control
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "false"
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: msu-control
  ports:
  - port: 80
    targetPort: 80
```

#### Ingress 설정 (ALB)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: msu-control
  annotations:
    alb.ingress.kubernetes.io/load-balancer-attributes: load_balancing.cross_zone.enabled=false
spec:
  ingressClassName: alb
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: msu-control
            port:
              number: 80
```

#### 주의사항

- Cross-Zone LB를 끄면 **가용성이 낮아질 수 있음**
- 한 존에 장애가 발생하면 해당 존의 트래픽이 실패
- 존별 파드 개수가 불균등하면 로드밸런싱 불균형

## 최적의 조합: TopologySpreadConstraints + Topology Aware Hints

### Helm Chart 설정

#### values.yaml

```yaml
# 파드를 A, C존에 균등 분산
topologySpreadConstraints:
  enabled: true
  maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule

# Service에 Topology Aware Hints 활성화
service:
  type: ClusterIP
  port: 80
  annotations:
    service.kubernetes.io/topology-mode: "Auto"

# 최소 4개 이상의 파드 (각 존에 2개씩)
autoscaling:
  enabled: true
  minReplicas: 4
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
```

#### templates/service.yaml 수정

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "msu-control.fullname" . }}
  labels:
    {{- include "msu-control.labels" . | nindent 4 }}
  {{- with .Values.service.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ .Values.service.type }}
  {{- if .Values.service.internalTrafficPolicy }}
  internalTrafficPolicy: {{ .Values.service.internalTrafficPolicy }}
  {{- end }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "msu-control.selectorLabels" . | nindent 4 }}
```

### 설치 명령어

```bash
helm install msu-control . \
  --set topologySpreadConstraints.enabled=true \
  --set service.annotations."service\.kubernetes\.io/topology-mode"="Auto" \
  --set autoscaling.minReplicas=4
```

## 비용 절감 효과 측정

### 1. EndpointSlice 확인

```bash
# Topology Hints가 적용되었는지 확인
kubectl get endpointslices -l kubernetes.io/service-name=msu-control -o yaml
```

**확인 포인트**:
```yaml
endpoints:
- addresses:
  - "10.0.1.100"
  zone: ap-northeast-2a
  hints:
    forZones:
    - name: ap-northeast-2a  # A존 클라이언트는 A존 엔드포인트 사용
```

### 2. 네트워크 트래픽 모니터링

```bash
# VPC Flow Logs 또는 CloudWatch 메트릭 확인
# Cross-AZ 데이터 전송량 확인
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name NetworkOut \
  --dimensions Name=InstanceId,Value=i-xxxxx \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

### 3. 비용 계산 예시

**시나리오**: 
- 일일 트래픽: 100GB
- Cross-Zone 비율: 50% → 25% (최적화 후)
- AWS Cross-AZ 비용: $0.01/GB

**절감액**:
```
Before: 100GB × 50% × $0.01 = $0.50/day = $15/month
After:  100GB × 25% × $0.01 = $0.25/day = $7.5/month
절감:   $7.5/month (50% 절감)
```

## 검증 방법

### 1. Topology Hints 적용 확인

```bash
kubectl describe service msu-control | grep -A 5 "Topology Aware Hints"
```

### 2. 실제 트래픽 흐름 테스트

```bash
# A존의 파드에서 서비스 호출
kubectl exec -it <pod-in-zone-a> -- sh
curl http://msu-control.default.svc.cluster.local

# 응답한 파드의 IP 확인
# A존의 파드 IP인지 확인
kubectl get pods -o wide | grep <response-ip>
```

### 3. 네트워크 정책으로 강제 검증

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-zone
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: msu-control
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
      namespaceSelector:
        matchLabels:
          topology.kubernetes.io/zone: ap-northeast-2a  # 같은 존만 허용
```

## 권장 사항

### 프로덕션 환경

1. **TopologySpreadConstraints** (파드 분산)
2. **Topology Aware Hints** (트래픽 라우팅)
3. **최소 4개 이상의 파드** (각 존에 2개씩)
4. **모니터링 설정** (Cross-AZ 트래픽 추적)

### 개발/테스트 환경

1. **TopologySpreadConstraints** (선택)
2. **InternalTrafficPolicy: Local** (비용 최소화)
3. **최소 파드 수** (리소스 절약)

## 결론

**TopologySpreadConstraints만으로는 Cross-Zone 통신 비용이 절감되지 않습니다.**

비용 절감을 위해서는:
1. ✅ TopologySpreadConstraints로 파드를 존별로 분산 배치
2. ✅ Topology Aware Hints로 같은 존 내 트래픽 라우팅
3. ✅ 모니터링으로 효과 측정

이 세 가지를 함께 사용해야 실제 비용 절감 효과를 볼 수 있습니다!

## 참고 자료

- [Kubernetes Topology Aware Hints](https://kubernetes.io/docs/concepts/services-networking/topology-aware-hints/)
- [AWS Data Transfer Pricing](https://aws.amazon.com/ec2/pricing/on-demand/#Data_Transfer)
- [EKS Best Practices - Cost Optimization](https://aws.github.io/aws-eks-best-practices/cost_optimization/cost_opt_networking/)
