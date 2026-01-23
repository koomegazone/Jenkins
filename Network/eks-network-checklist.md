# EKS 네트워크 통신 검증 체크리스트

## 검증 체크리스트

| # | 규칙 | 검증 명령어 | 성공 시 | 실패 시 |
|---|------|-------------|---------|---------|
| 1 | Node → Cluster (443) | `kubectl get nodes` | Ready | NotReady |
| 2 | Cluster → Node (10250) | `kubectl exec -it pod -- sh` | 쉘 접속 | timeout |
| 3 | Cluster → Node (443) | Webhook 설치 후 Pod 생성 | 정상 생성 | webhook error |
| 4 | Node ↔ Node (DNS) | `kubectl run test --image=busybox -it --rm -- nslookup kubernetes.default` | IP 응답, coredns 재기동 필요 | timeout |
| 5 | Node ↔ Node (Pod) | Service 생성 후 `wget http://service` | webhook 사용, Node-Node all port, Cluster->Node webhook 9443 | timeout |
| 6 | Node ↔ Node (Metrics) | `kubectl top nodes` | 메트릭 표시,  | ServiceUnavailable |
| 7 | Node → AWS (ECR) | ECR 이미지로 Pod 생성 | 정상 실행 | ImagePullBackOff |
| 8 | Node → Internet | `kubectl run test --image=busybox -it --rm -- wget -O- https://google.com` | HTML 응답 | timeout |

## 상세 검증 방법

### 1. Node → Cluster (443)
```bash
kubectl get nodes
```

### 2. Cluster → Node (10250)
```bash
kubectl run test-pod --image=nginx
kubectl exec -it test-pod -- sh
kubectl logs test-pod
kubectl top nodes
```

### 3. Node ↔ Node (DNS)
```bash
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default
```

### 4. Node ↔ Node (Pod 통신)
```bash
kubectl run backend --image=nginx --port=80
kubectl expose pod backend --port=80
kubectl run frontend --image=busybox --rm -it --restart=Never -- wget -O- http://backend
kubectl delete pod backend && kubectl delete svc backend
```

### 5. Metrics Server
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl top nodes
kubectl top pods -A
```

### 6. ECR 이미지
```bash
kubectl run ecr-test --image=<account-id>.dkr.ecr.<region>.amazonaws.com/my-app:latest
kubectl get pod ecr-test
```

### 7. Internet 접근
```bash
kubectl run internet-test --image=curlimages/curl --rm -it --restart=Never -- curl -I https://google.com
```

## 빠른 검증 스크립트

```bash
#!/bin/bash
echo "=== EKS 네트워크 검증 ==="

echo "1. Node → Cluster (443)..."
kubectl get nodes

echo "2. Cluster → Node (10250)..."
kubectl run test --image=nginx --restart=Never
sleep 5
kubectl exec test -- echo "OK"
kubectl delete pod test

echo "3. DNS..."
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default

echo "4. Pod 통신..."
kubectl run backend --image=nginx --port=80
kubectl expose pod backend --port=80
sleep 5
kubectl run frontend --image=busybox --rm -it --restart=Never -- wget -qO- http://backend
kubectl delete pod backend && kubectl delete svc backend

echo "5. Metrics..."
kubectl top nodes

echo "6. Internet..."
kubectl run test --image=curlimages/curl --rm -it --restart=Never -- curl -I https://google.com

echo "=== 완료 ==="
```

## 필수 Security Group 규칙

| 규칙 | 포트 | 방향 | 필수 |
|------|------|------|------|
| Node → Cluster | 443 | Outbound | ✅ |
| Cluster → Node | 10250 | Inbound | ✅ |
| Node ↔ Node | All | Both | ✅ |
| Node → Internet | 443 | Outbound | ✅ |
| Node → VPC DNS | 53 | Outbound | ✅ |
