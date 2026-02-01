# msu-control Helm Chart

A Helm chart for deploying PHP application on Kubernetes with autoscaling and persistent storage.

## Chart Information

- **Chart Version**: 0.1.0
- **App Version**: pp
- **Image**: koomzc/php

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner support in the underlying infrastructure (for persistence)

## Installation

### Basic Installation

```bash
# 차트 디렉토리로 이동
cd ~/gasida/Jenkins/helmchart/msu-control

# 1. 헬름 차트 설치 (기본값 사용)
helm install msu-control .

# 2. 릴리즈 이름 지정하여 설치
helm install my-msu-control .

# 3. 특정 네임스페이스에 설치
helm install msu-control . -n my-namespace --create-namespace
```

### Custom Values Installation

```bash
# 4. 커스텀 values 파일 사용
helm install msu-control . -f custom-values.yaml

# 5. 명령줄에서 값 오버라이드
helm install msu-control . \
  --set replicaCount=3 \
  --set image.tag=latest \
  --set service.type=LoadBalancer
```

## Pre-Installation Validation

```bash
# 6. 차트 문법 검증
helm lint .

# 7. 렌더링될 매니페스트 미리보기 (dry-run)
helm install msu-control . --dry-run --debug

# 8. 템플릿 렌더링 결과만 확인
helm template msu-control .
```

## Upgrade and Management

```bash
# 9. 차트 업그레이드
helm upgrade msu-control .

# 10. 설치 또는 업그레이드 (없으면 설치, 있으면 업그레이드)
helm upgrade --install msu-control .

# 11. 릴리즈 상태 확인
helm status msu-control

# 12. 설치된 값 확인
helm get values msu-control

# 13. 롤백
helm rollback msu-control 1

# 14. 삭제
helm uninstall msu-control
```

## Recommended Production Installation

```bash
# persistence와 autoscaling이 활성화된 상태로 설치
helm install msu-control . \
  --set persistence.storageClass=gp3 \
  --set autoscaling.minReplicas=2 \
  --set autoscaling.maxReplicas=5 \
  --set autoscaling.targetCPUUtilizationPercentage=50
```

## Configuration

The following table lists the configurable parameters of the msu-control chart and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Image repository | `koomzc/php` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `image.tag` | Image tag | `""` (uses appVersion) |
| `service.type` | Service type | `ClusterIP` |
| `service.port` | Service port | `80` |
| `service.topologyAwareHints.enabled` | Enable topology aware hints | `true` |
| `service.annotations` | Service annotations | `{}` |
| `service.internalTrafficPolicy` | Internal traffic policy | `""` |
| `topologySpreadConstraints.enabled` | Enable topology spread | `true` |
| `topologySpreadConstraints.maxSkew` | Max skew between zones | `1` |
| `topologySpreadConstraints.topologyKey` | Topology key | `topology.kubernetes.io/zone` |
| `topologySpreadConstraints.whenUnsatisfiable` | When unsatisfiable | `DoNotSchedule` |
| `autoscaling.enabled` | Enable HPA | `true` |
| `autoscaling.minReplicas` | Minimum replicas | `3` |
| `autoscaling.maxReplicas` | Maximum replicas | `3` |
| `autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization | `30` |
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | PVC size | `10Gi` |
| `persistence.accessMode` | PVC access mode | `ReadWriteOnce` |
| `resources.requests.cpu` | CPU request | `0.5` |

## Features

- ✅ Horizontal Pod Autoscaling (HPA) enabled by default
- ✅ Persistent Volume Claim (PVC) support
- ✅ Service Account creation
- ✅ Liveness and Readiness probes
- ✅ Ingress support (disabled by default)
- ✅ Pod Anti-Affinity support

## Examples

### Deploy Pods Only in A and C Zones (Zone Distribution)

```bash
# topologySpreadConstraints를 사용하여 A, C존에 파드 분산 배포
helm install msu-control . \
  --set topologySpreadConstraints.enabled=true \
  --set topologySpreadConstraints.maxSkew=1 \
  --set topologySpreadConstraints.whenUnsatisfiable=DoNotSchedule \
  --set-string nodeSelector."topology\.kubernetes\.io/zone"="ap-northeast-2a\,ap-northeast-2c"
```

또는 values.yaml 파일을 수정:

```yaml
topologySpreadConstraints:
  enabled: true
  maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule

# A, C존의 노드에만 스케줄링하려면 nodeAffinity 사용
nodeSelector: {}

# 또는 affinity를 직접 설정 (더 유연함)
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: topology.kubernetes.io/zone
          operator: In
          values:
          - ap-northeast-2a
          - ap-northeast-2c
```

### Reduce Cross-Zone Network Costs

**중요**: TopologySpreadConstraints만으로는 Cross-Zone 통신 비용이 절감되지 않습니다!

트래픽을 같은 존 내에서 라우팅하려면 **Topology Aware Hints**를 함께 사용하세요 (기본 활성화):

```bash
# 기본 설치 (Topology Aware Hints 자동 활성화)
helm install msu-control . \
  --set topologySpreadConstraints.enabled=true \
  --set autoscaling.minReplicas=4

# Topology Aware Hints 비활성화하려면
helm install msu-control . \
  --set service.topologyAwareHints.enabled=false
```

또는 같은 노드 내에서만 트래픽 라우팅 (더 강력한 제약):

```bash
helm install msu-control . \
  --set topologySpreadConstraints.enabled=true \
  --set service.internalTrafficPolicy="Local"
```

**검증 방법**:

```bash
# 1. Service annotation 확인
kubectl describe svc msu-control | grep topology-mode

# 2. EndpointSlice hints 확인
kubectl get endpointslices -l kubernetes.io/service-name=msu-control -o yaml | grep -A 3 hints

# 3. iptables 룰 확인 (각 존의 노드에서 다른 룰이 생성됨)
sudo iptables-save | grep KUBE-SVC
```

자세한 내용은 [CROSS-ZONE-COST-OPTIMIZATION.md](./CROSS-ZONE-COST-OPTIMIZATION.md)와 [KUBE-PROXY-IPTABLES-ANALYSIS.md](./KUBE-PROXY-IPTABLES-ANALYSIS.md)를 참고하세요.

### Enable Ingress

```bash
helm install msu-control . \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=myapp.example.com \
  --set ingress.hosts[0].paths[0].path=/ \
  --set ingress.hosts[0].paths[0].pathType=Prefix
```

### Disable Autoscaling

```bash
helm install msu-control . \
  --set autoscaling.enabled=false \
  --set replicaCount=2
```

### Use Existing PVC

```bash
helm install msu-control . \
  --set persistence.enabled=true \
  --set persistence.existingClaim=my-existing-pvc
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -l app.kubernetes.io/name=msu-control
```

### View Logs

```bash
kubectl logs -l app.kubernetes.io/name=msu-control
```

### Describe Resources

```bash
kubectl describe deployment msu-control
kubectl describe hpa msu-control
kubectl describe pvc msu-control
```

## Uninstallation

```bash
# 차트 삭제
helm uninstall msu-control

# PVC도 함께 삭제하려면
kubectl delete pvc -l app.kubernetes.io/name=msu-control
```
