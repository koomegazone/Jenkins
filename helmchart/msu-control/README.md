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
