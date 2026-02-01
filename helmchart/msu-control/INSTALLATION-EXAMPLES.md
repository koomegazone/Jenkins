# msu-control 설치 예시

## 기본 설치 (Topology Aware Hints 활성화)

```bash
# 기본 설치 - Topology Aware Hints가 자동으로 활성화됨
helm install msu-control . \
  --set autoscaling.minReplicas=4

# 설치 확인
kubectl get pods -o wide -l app.kubernetes.io/name=msu-control
kubectl describe svc msu-control | grep topology-mode
```

## Production 환경 설치

```bash
# Production values 파일 사용
helm install msu-control . -f values-production.yaml

# 또는 명령줄로 설정
helm install msu-control . \
  --set topologySpreadConstraints.enabled=true \
  --set service.topologyAwareHints.enabled=true \
  --set autoscaling.minReplicas=4 \
  --set autoscaling.maxReplicas=10 \
  --set autoscaling.targetCPUUtilizationPercentage=50 \
  --set persistence.enabled=true \
  --set persistence.storageClass=gp3 \
  --set persistence.size=20Gi
```

## A, C존에만 배포 (Cross-Zone 트래픽 최소화)

```bash
# TopologySpreadConstraints + Topology Aware Hints
helm install msu-control . \
  --set topologySpreadConstraints.enabled=true \
  --set service.topologyAwareHints.enabled=true \
  --set autoscaling.minReplicas=4 \
  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=topology.kubernetes.io/zone \
  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=In \
  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values={ap-northeast-2a,ap-northeast-2c}
```

또는 custom values 파일 생성:

```yaml
# custom-values.yaml
topologySpreadConstraints:
  enabled: true
  maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule

service:
  topologyAwareHints:
    enabled: true

autoscaling:
  enabled: true
  minReplicas: 4
  maxReplicas: 10

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

```bash
helm install msu-control . -f custom-values.yaml
```

## Topology Aware Hints 비활성화

```bash
# Topology Aware Hints를 사용하지 않으려면
helm install msu-control . \
  --set service.topologyAwareHints.enabled=false
```

## Internal Traffic Policy 사용 (더 강력한 제약)

```bash
# 같은 노드 내에서만 트래픽 라우팅
helm install msu-control . \
  --set service.internalTrafficPolicy=Local \
  --set service.topologyAwareHints.enabled=false
```

**주의**: `internalTrafficPolicy: Local`을 사용하면:
- 모든 노드에 파드가 있어야 함
- 같은 노드에 파드가 없으면 트래픽 실패
- DaemonSet 스타일 배포에 적합

## 검증 방법

### 1. Topology Aware Hints 적용 확인

```bash
# Service annotation 확인
kubectl describe svc msu-control | grep -i topology

# 출력 예시:
# Annotations: service.kubernetes.io/topology-mode: Auto
```

### 2. EndpointSlice Hints 확인

```bash
# EndpointSlice에 hints가 있는지 확인
kubectl get endpointslices -l kubernetes.io/service-name=msu-control -o yaml

# hints가 있으면 성공:
# hints:
#   forZones:
#   - name: ap-northeast-2a
```

### 3. 파드 분산 확인

```bash
# 존별 파드 개수 확인
kubectl get pods -l app.kubernetes.io/name=msu-control -o json | \
  jq -r '.items[] | .spec.nodeName' | \
  xargs -I {} kubectl get node {} -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}' | \
  sort | uniq -c

# 출력 예시:
#   2 ap-northeast-2a
#   2 ap-northeast-2c
```

### 4. iptables 룰 확인 (고급)

```bash
# A존 노드에 접속
kubectl get nodes -l topology.kubernetes.io/zone=ap-northeast-2a -o name | head -1

# 노드에서 iptables 확인
sudo iptables-save | grep KUBE-SVC | grep msu-control

# A존 노드에서는 A존 파드 IP만 보여야 함
# C존 노드에서는 C존 파드 IP만 보여야 함
```

### 5. 실제 트래픽 테스트

```bash
# A존 파드에서 Service 호출 (100번)
POD_NAME=$(kubectl get pods -l app.kubernetes.io/name=msu-control -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $POD_NAME -- sh -c '
for i in $(seq 1 100); do
  curl -s http://msu-control.default.svc.cluster.local
done
' | grep -o "Pod IP: [0-9.]*" | sort | uniq -c

# Topology Aware Hints가 작동하면:
# - A존 파드에서 호출 시 A존 파드로만 트래픽 전송
# - C존 파드 IP는 나타나지 않음
```

## 업그레이드

```bash
# 설정 변경 후 업그레이드
helm upgrade msu-control . \
  --set service.topologyAwareHints.enabled=true \
  --set autoscaling.minReplicas=6

# 또는 values 파일로
helm upgrade msu-control . -f values-production.yaml

# 변경사항 확인
helm diff upgrade msu-control . -f values-production.yaml
```

## 롤백

```bash
# 이전 버전으로 롤백
helm rollback msu-control

# 특정 리비전으로 롤백
helm rollback msu-control 1

# 히스토리 확인
helm history msu-control
```

## 삭제

```bash
# 차트 삭제
helm uninstall msu-control

# PVC도 함께 삭제
kubectl delete pvc -l app.kubernetes.io/name=msu-control
```

## 트러블슈팅

### Topology Aware Hints가 적용되지 않는 경우

```bash
# 1. 파드 분산 확인 (불균등하면 적용 안 됨)
kubectl get pods -o wide -l app.kubernetes.io/name=msu-control

# 2. 노드 존 레이블 확인
kubectl get nodes -L topology.kubernetes.io/zone

# 3. EndpointSlice 이벤트 확인
kubectl describe endpointslices -l kubernetes.io/service-name=msu-control

# 4. kube-proxy 로그 확인
kubectl logs -n kube-system -l k8s-app=kube-proxy | grep -i topology
```

### 파드가 Pending 상태인 경우

```bash
# 파드 상태 확인
kubectl describe pod <pod-name>

# TopologySpreadConstraints 조건 완화
helm upgrade msu-control . \
  --set topologySpreadConstraints.whenUnsatisfiable=ScheduleAnyway
```

### Cross-Zone 트래픽이 여전히 발생하는 경우

```bash
# 1. Service annotation 확인
kubectl get svc msu-control -o yaml | grep topology-mode

# 2. EndpointSlice hints 확인
kubectl get endpointslices -l kubernetes.io/service-name=msu-control -o yaml | grep -A 5 hints

# 3. 파드 수 증가 (최소 4개 이상 권장)
helm upgrade msu-control . --set autoscaling.minReplicas=4

# 4. 더 강력한 제약 사용
helm upgrade msu-control . --set service.internalTrafficPolicy=Local
```

## 모니터링

### Prometheus 메트릭

```bash
# Service 메트릭 확인
kubectl port-forward svc/msu-control 8080:80

# 브라우저에서 http://localhost:8080/metrics 접속
```

### 네트워크 트래픽 모니터링

```bash
# VPC Flow Logs 확인 (AWS)
aws ec2 describe-flow-logs

# CloudWatch 메트릭 확인
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name NetworkOut \
  --dimensions Name=InstanceId,Value=<instance-id> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

## 참고 자료

- [README.md](./README.md) - 기본 사용법
- [ZONE-DEPLOYMENT-GUIDE.md](./ZONE-DEPLOYMENT-GUIDE.md) - 존 분산 배포 가이드
- [CROSS-ZONE-COST-OPTIMIZATION.md](./CROSS-ZONE-COST-OPTIMIZATION.md) - 비용 최적화 가이드
- [KUBE-PROXY-IPTABLES-ANALYSIS.md](./KUBE-PROXY-IPTABLES-ANALYSIS.md) - iptables 분석
