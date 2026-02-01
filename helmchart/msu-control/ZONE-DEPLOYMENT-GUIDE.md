# A, C존 파드 분산 배포 가이드

이 가이드는 Kubernetes에서 파드를 특정 가용 영역(A, C존)에만 배포하고 균등하게 분산시키는 방법을 설명합니다.

## 목표

- 파드를 A존(ap-northeast-2a)과 C존(ap-northeast-2c)에만 배포
- 각 존에 파드를 균등하게 분산
- Anti-Affinity 대신 TopologySpreadConstraints 사용

## 방법 1: TopologySpreadConstraints (권장)

### 설정 방법

`values.yaml` 파일 수정:

```yaml
topologySpreadConstraints:
  enabled: true
  maxSkew: 1  # 존 간 파드 개수 차이를 최대 1개로 제한
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule  # 조건을 만족하지 못하면 스케줄링 안 함
```

### Helm 설치 명령어

```bash
helm install msu-control . \
  --set topologySpreadConstraints.enabled=true \
  --set topologySpreadConstraints.maxSkew=1 \
  --set topologySpreadConstraints.whenUnsatisfiable=DoNotSchedule
```

### 동작 방식

- `maxSkew: 1`: 존 간 파드 개수 차이가 최대 1개
  - 예: A존 2개, C존 2개 (OK)
  - 예: A존 3개, C존 2개 (OK)
  - 예: A존 4개, C존 2개 (NG - maxSkew 초과)

- `whenUnsatisfiable: DoNotSchedule`: 조건을 만족할 수 없으면 파드를 스케줄링하지 않음

## 방법 2: NodeAffinity로 A, C존만 선택

A, C존의 노드에만 파드를 배포하려면 NodeAffinity를 추가합니다.

### values.yaml 수정

```yaml
# deployment.yaml에 직접 추가하거나 values.yaml에서 관리
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

### Helm 설치 명령어

```bash
helm install msu-control . \
  --set topologySpreadConstraints.enabled=true \
  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=topology.kubernetes.io/zone \
  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=In \
  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values={ap-northeast-2a,ap-northeast-2c}
```

## 방법 3: 완전한 조합 (TopologySpreadConstraints + NodeAffinity)

A, C존에만 배포하면서 균등 분산까지 보장하려면 두 가지를 함께 사용합니다.

### custom-values.yaml 생성

```yaml
# custom-values.yaml
replicaCount: 4

topologySpreadConstraints:
  enabled: true
  maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule

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
  podAntiAffinity:
    enabled: false

autoscaling:
  enabled: true
  minReplicas: 4
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
```

### 설치

```bash
helm install msu-control . -f custom-values.yaml
```

## 검증 방법

### 1. 파드가 어느 존에 배포되었는지 확인

```bash
kubectl get pods -o wide -l app.kubernetes.io/name=msu-control
```

### 2. 존별 파드 개수 확인

```bash
kubectl get pods -l app.kubernetes.io/name=msu-control -o json | \
  jq -r '.items[] | .spec.nodeName' | \
  xargs -I {} kubectl get node {} -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}' | \
  sort | uniq -c
```

### 3. 노드의 존 레이블 확인

```bash
kubectl get nodes -L topology.kubernetes.io/zone
```

### 4. TopologySpreadConstraints 적용 확인

```bash
kubectl get deployment msu-control -o yaml | grep -A 10 topologySpreadConstraints
```

## 예상 결과

### 4개 파드 배포 시

```
NAME                           READY   STATUS    NODE                                              ZONE
msu-control-xxx-aaa           1/1     Running   ip-10-0-1-100.ap-northeast-2.compute.internal    ap-northeast-2a
msu-control-xxx-bbb           1/1     Running   ip-10-0-1-101.ap-northeast-2.compute.internal    ap-northeast-2a
msu-control-xxx-ccc           1/1     Running   ip-10-0-3-100.ap-northeast-2.compute.internal    ap-northeast-2c
msu-control-xxx-ddd           1/1     Running   ip-10-0-3-101.ap-northeast-2.compute.internal    ap-northeast-2c
```

- A존: 2개
- C존: 2개
- 균등 분산 ✅

### 5개 파드 배포 시

```
- A존: 3개
- C존: 2개
- maxSkew=1 조건 만족 ✅
```

## 트러블슈팅

### 파드가 Pending 상태로 남아있는 경우

```bash
kubectl describe pod <pod-name>
```

**원인 1**: A, C존에 사용 가능한 노드가 없음
- 해결: 노드 확인 및 추가

**원인 2**: maxSkew 조건을 만족할 수 없음
- 해결: `whenUnsatisfiable: ScheduleAnyway`로 변경 (soft constraint)

**원인 3**: 리소스 부족
- 해결: 노드 스케일 아웃 또는 리소스 요청량 조정

### B존에도 파드가 배포되는 경우

NodeAffinity가 제대로 설정되지 않았을 가능성이 높습니다.

```bash
# Deployment의 affinity 설정 확인
kubectl get deployment msu-control -o yaml | grep -A 20 affinity
```

## 참고 자료

- [Kubernetes Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)
- [Kubernetes Node Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity)
- [AWS EKS Best Practices - High Availability](https://aws.github.io/aws-eks-best-practices/reliability/docs/dataplane/)
