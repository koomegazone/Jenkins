#!/bin/bash

# EKS 네트워크 통신 검증 스크립트
# 기존 리소스가 있으면 삭제하고 새로 생성

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 검증 결과 저장
declare -a FAILED_TESTS
declare -a PASSED_TESTS

# 함수: 리소스 정리
cleanup_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-default}
    
    if kubectl get $resource_type $resource_name -n $namespace &>/dev/null; then
        echo -e "${YELLOW}기존 $resource_type/$resource_name 삭제 중...${NC}"
        kubectl delete $resource_type $resource_name -n $namespace --force --grace-period=0 &>/dev/null || true
        sleep 2
    fi
}

# 함수: Pod가 Ready 될 때까지 대기
wait_for_pod() {
    local pod_name=$1
    local namespace=${2:-default}
    local timeout=30
    local elapsed=0
    
    echo -e "${YELLOW}Pod $pod_name이 Ready 될 때까지 대기 중...${NC}"
    while [ $elapsed -lt $timeout ]; do
        if kubectl get pod $pod_name -n $namespace &>/dev/null; then
            local status=$(kubectl get pod $pod_name -n $namespace -o jsonpath='{.status.phase}')
            if [ "$status" == "Running" ]; then
                echo -e "${GREEN}✓ Pod Ready${NC}"
                return 0
            fi
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo -e "${RED}✗ Pod Ready 실패 (timeout)${NC}"
    return 1
}

echo "=========================================="
echo "  EKS 네트워크 통신 검증 시작"
echo "=========================================="
echo ""

# ==========================================
# 1. Node → Cluster (443) 검증
# ==========================================
echo -e "${GREEN}[1/6] Node → Cluster (443) 검증${NC}"
echo "----------------------------------------"
kubectl get nodes
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Node → Cluster (443) 통신 정상${NC}"
    PASSED_TESTS+=("Node → Cluster (443)")
else
    echo -e "${RED}✗ Node → Cluster (443) 통신 실패${NC}"
    FAILED_TESTS+=("Node → Cluster (443)")
fi
echo ""

# ==========================================
# 2. Cluster → Node (10250) 검증
# ==========================================
echo -e "${GREEN}[2/6] Cluster → Node (10250) 검증${NC}"
echo "----------------------------------------"

# 기존 리소스 정리
cleanup_resource pod test

# Pod 생성
echo "테스트 Pod 생성 중..."
kubectl run test --image=nginx --restart=Never

# Pod Ready 대기
if wait_for_pod test; then
    # exec 테스트
    echo "kubectl exec 테스트..."
    if kubectl exec test -- echo "OK" &>/dev/null; then
        echo -e "${GREEN}✓ Cluster → Node (10250) 통신 정상${NC}"
        PASSED_TESTS+=("Cluster → Node (10250)")
    else
        echo -e "${RED}✗ kubectl exec 실패 (10250 포트 차단 가능성)${NC}"
        FAILED_TESTS+=("Cluster → Node (10250)")
    fi
    
    # logs 테스트
    echo "kubectl logs 테스트..."
    kubectl logs test &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ kubectl logs 정상${NC}"
    else
        echo -e "${RED}✗ kubectl logs 실패${NC}"
    fi
else
    echo -e "${RED}✗ Pod 생성 실패${NC}"
    FAILED_TESTS+=("Cluster → Node (10250)")
fi

# 정리
cleanup_resource pod test
echo ""

# ==========================================
# 3. DNS (CoreDNS) 검증
# ==========================================
echo -e "${GREEN}[3/6] Node ↔ Node DNS (53) 검증${NC}"
echo "----------------------------------------"

# 기존 리소스 정리
cleanup_resource pod dns-test

echo "DNS 조회 테스트..."
kubectl run dns-test --image=busybox --restart=Never -- sleep 3600

if wait_for_pod dns-test; then
    # Kubernetes Service DNS 조회
    echo "kubernetes.default DNS 조회..."
    if kubectl exec dns-test -- nslookup kubernetes.default.svc.cluster.local &>/dev/null; then
        echo -e "${GREEN}✓ DNS 조회 정상${NC}"
        PASSED_TESTS+=("DNS (CoreDNS)")
    else
        echo -e "${RED}✗ DNS 조회 실패 (53 포트 차단 가능성)${NC}"
        FAILED_TESTS+=("DNS (CoreDNS)")
    fi
    
    # 외부 도메인 조회
    echo "외부 도메인 DNS 조회..."
    if kubectl exec dns-test -- nslookup google.com &>/dev/null; then
        echo -e "${GREEN}✓ 외부 DNS 조회 정상${NC}"
    else
        echo -e "${RED}✗ 외부 DNS 조회 실패${NC}"
    fi
else
    echo -e "${RED}✗ DNS 테스트 Pod 생성 실패${NC}"
    FAILED_TESTS+=("DNS (CoreDNS)")
fi

# 정리
cleanup_resource pod dns-test
echo ""

# ==========================================
# 4. Pod 간 통신 검증
# ==========================================
echo -e "${GREEN}[4/6] Node ↔ Node Pod 통신 검증${NC}"
echo "----------------------------------------"

# 기존 리소스 정리
cleanup_resource svc backend
cleanup_resource pod backend
cleanup_resource pod frontend

# Backend Pod 생성
echo "Backend Pod 생성 중..."
kubectl run backend --image=nginx --port=80

if wait_for_pod backend; then
    # Service 생성
    echo "Service 생성 중..."
    kubectl expose pod backend --port=80
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Service 생성 정상 (Webhook 통신 정상)${NC}"
        PASSED_TESTS+=("Webhook (Cluster → Node 443)")
        sleep 3
        
        # Frontend Pod에서 접근 테스트
        echo "Frontend → Backend 통신 테스트..."
        kubectl run frontend --image=busybox --restart=Never -- wget -qO- http://backend --timeout=5
        
        if wait_for_pod frontend; then
            kubectl logs frontend &>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Pod 간 통신 정상${NC}"
                PASSED_TESTS+=("Pod 간 통신 (Node ↔ Node)")
            else
                echo -e "${RED}✗ Pod 간 통신 실패 (Node 간 통신 차단 가능성)${NC}"
                FAILED_TESTS+=("Pod 간 통신 (Node ↔ Node)")
            fi
        fi
        
        # 정리
        cleanup_resource pod frontend
    else
        echo -e "${RED}✗ Service 생성 실패 (Webhook 443 포트 차단 가능성)${NC}"
        FAILED_TESTS+=("Webhook (Cluster → Node 443)")
    fi
else
    echo -e "${RED}✗ Backend Pod 생성 실패${NC}"
    FAILED_TESTS+=("Pod 간 통신 (Node ↔ Node)")
fi

# 정리
cleanup_resource svc backend
cleanup_resource pod backend
echo ""

# ==========================================
# 5. Metrics Server 검증
# ==========================================
echo -e "${GREEN}[5/6] Metrics Server 검증${NC}"
echo "----------------------------------------"

echo "Node 메트릭 조회..."
if kubectl top nodes &>/dev/null; then
    echo -e "${GREEN}✓ Metrics Server 정상${NC}"
    PASSED_TESTS+=("Metrics Server")
    kubectl top nodes
else
    echo -e "${YELLOW}⚠ Metrics Server 미설치 또는 통신 실패${NC}"
    FAILED_TESTS+=("Metrics Server")
    echo "설치: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi
echo ""

# ==========================================
# 6. Internet 접근 검증
# ==========================================
echo -e "${GREEN}[6/6] Internet 접근 검증${NC}"
echo "----------------------------------------"

# 기존 리소스 정리
cleanup_resource pod internet-test

echo "Internet 접근 테스트 (5초 timeout)..."
kubectl run internet-test --image=curlimages/curl --restart=Never -- curl -I https://google.com --max-time 5

if wait_for_pod internet-test; then
    # 5초 timeout으로 로그 확인
    echo "응답 대기 중 (최대 5초)..."
    timeout 5 bash -c 'while ! kubectl logs internet-test 2>/dev/null | grep -q "HTTP"; do sleep 0.5; done' &>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Internet 접근 정상${NC}"
        PASSED_TESTS+=("Internet 접근")
    else
        echo -e "${RED}✗ Internet 접근 실패 (5초 timeout - Outbound 443 차단 가능성)${NC}"
        FAILED_TESTS+=("Internet 접근")
    fi
else
    echo -e "${RED}✗ Internet 테스트 Pod 생성 실패${NC}"
    FAILED_TESTS+=("Internet 접근")
fi

# 정리
cleanup_resource pod internet-test
echo ""

# ==========================================
# 최종 정리
# ==========================================
echo "=========================================="
echo "  최종 리소스 정리"
echo "=========================================="

cleanup_resource pod test
cleanup_resource pod dns-test
cleanup_resource pod backend
cleanup_resource pod frontend
cleanup_resource pod internet-test
cleanup_resource svc backend

echo ""
echo "=========================================="
echo "  검증 완료"
echo "=========================================="
echo ""

# 결과 요약
echo -e "${BLUE}=========================================="
echo "  검증 결과 요약"
echo -e "==========================================${NC}"
echo ""

TOTAL_TESTS=$((${#PASSED_TESTS[@]} + ${#FAILED_TESTS[@]}))
echo -e "${GREEN}✓ 성공: ${#PASSED_TESTS[@]}/${TOTAL_TESTS}${NC}"
echo -e "${RED}✗ 실패: ${#FAILED_TESTS[@]}/${TOTAL_TESTS}${NC}"
echo ""

# 실패한 테스트가 있으면 상세 가이드 출력
if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "${RED}=========================================="
    echo "  실패한 항목 및 조치 방법"
    echo -e "==========================================${NC}"
    echo ""
    
    for test in "${FAILED_TESTS[@]}"; do
        case "$test" in
            "Node → Cluster (443)")
                echo -e "${RED}✗ Node → Cluster (443) 통신 실패${NC}"
                echo "  증상: kubectl get nodes가 NotReady 상태"
                echo "  원인: Node에서 EKS API Server로 통신 차단"
                echo ""
                echo "  조치 방법:"
                echo "  1. Security Group 확인"
                echo "     aws ec2 describe-security-groups --group-ids <node-sg-id>"
                echo ""
                echo "  2. Node → Cluster (443) Outbound 규칙 추가"
                echo "     aws ec2 authorize-security-group-egress \\"
                echo "       --group-id <node-sg-id> \\"
                echo "       --protocol tcp --port 443 \\"
                echo "       --destination-group <cluster-sg-id>"
                echo ""
                echo "  3. Cluster Inbound 규칙 추가"
                echo "     aws ec2 authorize-security-group-ingress \\"
                echo "       --group-id <cluster-sg-id> \\"
                echo "       --protocol tcp --port 443 \\"
                echo "       --source-group <node-sg-id>"
                echo ""
                ;;
                
            "Cluster → Node (10250)")
                echo -e "${RED}✗ Cluster → Node (10250) 통신 실패${NC}"
                echo "  증상: kubectl exec, kubectl logs 실패"
                echo "  원인: EKS Control Plane에서 Kubelet으로 통신 차단"
                echo ""
                echo "  조치 방법:"
                echo "  1. Node Inbound 규칙 추가"
                echo "     aws ec2 authorize-security-group-ingress \\"
                echo "       --group-id <node-sg-id> \\"
                echo "       --protocol tcp --port 10250 \\"
                echo "       --source-group <cluster-sg-id>"
                echo ""
                echo "  2. Cluster Outbound 규칙 추가"
                echo "     aws ec2 authorize-security-group-egress \\"
                echo "       --group-id <cluster-sg-id> \\"
                echo "       --protocol tcp --port 10250 \\"
                echo "       --destination-group <node-sg-id>"
                echo ""
                ;;
                
            "DNS (CoreDNS)")
                echo -e "${RED}✗ DNS (CoreDNS) 통신 실패${NC}"
                echo "  증상: nslookup 실패, Pod 간 Service 이름으로 통신 불가"
                echo "  원인: Node 간 53 포트 통신 차단"
                echo ""
                echo "  조치 방법:"
                echo "  1. CoreDNS Pod 상태 확인"
                echo "     kubectl get pods -n kube-system -l k8s-app=kube-dns"
                echo ""
                echo "  2. Node 간 53 포트 허용 (TCP/UDP)"
                echo "     aws ec2 authorize-security-group-ingress \\"
                echo "       --group-id <node-sg-id> \\"
                echo "       --protocol tcp --port 53 \\"
                echo "       --source-group <node-sg-id>"
                echo ""
                echo "     aws ec2 authorize-security-group-ingress \\"
                echo "       --group-id <node-sg-id> \\"
                echo "       --protocol udp --port 53 \\"
                echo "       --source-group <node-sg-id>"
                echo ""
                echo "  3. CoreDNS 재시작"
                echo "     kubectl rollout restart deployment coredns -n kube-system"
                echo ""
                ;;
                
            "Webhook (Cluster → Node 443)")
                echo -e "${RED}✗ Webhook (Cluster → Node 443) 통신 실패${NC}"
                echo "  증상: kubectl expose 실패, Service 생성 시 webhook timeout"
                echo "  원인: EKS Control Plane에서 Webhook Pod로 통신 차단"
                echo ""
                echo "  조치 방법:"
                echo "  1. Node Inbound 443 규칙 추가"
                echo "     aws ec2 authorize-security-group-ingress \\"
                echo "       --group-id <node-sg-id> \\"
                echo "       --protocol tcp --port 443 \\"
                echo "       --source-group <cluster-sg-id>"
                echo ""
                echo "  2. Cluster Outbound 443 규칙 추가"
                echo "     aws ec2 authorize-security-group-egress \\"
                echo "       --group-id <cluster-sg-id> \\"
                echo "       --protocol tcp --port 443 \\"
                echo "       --destination-group <node-sg-id>"
                echo ""
                echo "  3. AWS Load Balancer Controller 재시작"
                echo "     kubectl rollout restart deployment aws-load-balancer-controller -n kube-system"
                echo ""
                ;;
                
            "Pod 간 통신 (Node ↔ Node)")
                echo -e "${RED}✗ Pod 간 통신 (Node ↔ Node) 실패${NC}"
                echo "  증상: Pod에서 다른 Pod로 HTTP 통신 실패"
                echo "  원인: Node 간 애플리케이션 포트 통신 차단"
                echo ""
                echo "  조치 방법:"
                echo "  1. Node 간 All 포트 허용 (권장)"
                echo "     aws ec2 authorize-security-group-ingress \\"
                echo "       --group-id <node-sg-id> \\"
                echo "       --protocol -1 \\"
                echo "       --source-group <node-sg-id>"
                echo ""
                echo "  2. 또는 최소 포트만 허용"
                echo "     aws ec2 authorize-security-group-ingress \\"
                echo "       --group-id <node-sg-id> \\"
                echo "       --protocol tcp --port 1025-65535 \\"
                echo "       --source-group <node-sg-id>"
                echo ""
                ;;
                
            "Metrics Server")
                echo -e "${RED}✗ Metrics Server 실패${NC}"
                echo "  증상: kubectl top nodes/pods 실패"
                echo "  원인: Metrics Server 미설치 또는 Node 간 10250 포트 차단"
                echo ""
                echo "  조치 방법:"
                echo "  1. Metrics Server 설치"
                echo "     kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
                echo ""
                echo "  2. Node 간 10250 포트 허용"
                echo "     aws ec2 authorize-security-group-ingress \\"
                echo "       --group-id <node-sg-id> \\"
                echo "       --protocol tcp --port 10250 \\"
                echo "       --source-group <node-sg-id>"
                echo ""
                echo "  3. Metrics Server Pod 확인"
                echo "     kubectl get pods -n kube-system -l k8s-app=metrics-server"
                echo ""
                ;;
                
            "Internet 접근")
                echo -e "${RED}✗ Internet 접근 실패${NC}"
                echo "  증상: Pod에서 외부 인터넷 접속 불가"
                echo "  원인: Node Outbound 통신 차단 또는 NAT Gateway 문제"
                echo ""
                echo "  조치 방법:"
                echo "  1. Node Outbound All 허용 (권장)"
                echo "     aws ec2 authorize-security-group-egress \\"
                echo "       --group-id <node-sg-id> \\"
                echo "       --protocol -1 \\"
                echo "       --cidr 0.0.0.0/0"
                echo ""
                echo "  2. NAT Gateway 확인 (Private Subnet인 경우)"
                echo "     aws ec2 describe-nat-gateways"
                echo ""
                echo "  3. Route Table 확인"
                echo "     aws ec2 describe-route-tables --filters \"Name=vpc-id,Values=<vpc-id>\""
                echo ""
                ;;
        esac
        echo ""
    done
    
    echo -e "${BLUE}=========================================="
    echo "  빠른 해결 (모든 규칙 한번에 추가)"
    echo -e "==========================================${NC}"
    echo ""
    echo "# Cluster와 Node Security Group ID 확인"
    echo "CLUSTER_SG=\$(aws eks describe-cluster --name <cluster-name> \\"
    echo "  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)"
    echo "NODE_SG=\$(aws ec2 describe-instances \\"
    echo "  --filters \"Name=tag:eks:cluster-name,Values=<cluster-name>\" \\"
    echo "  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)"
    echo ""
    echo "# 1. Node → Cluster (443)"
    echo "aws ec2 authorize-security-group-egress --group-id \$NODE_SG --protocol tcp --port 443 --destination-group \$CLUSTER_SG"
    echo "aws ec2 authorize-security-group-ingress --group-id \$CLUSTER_SG --protocol tcp --port 443 --source-group \$NODE_SG"
    echo ""
    echo "# 2. Cluster → Node (10250)"
    echo "aws ec2 authorize-security-group-ingress --group-id \$NODE_SG --protocol tcp --port 10250 --source-group \$CLUSTER_SG"
    echo "aws ec2 authorize-security-group-egress --group-id \$CLUSTER_SG --protocol tcp --port 10250 --destination-group \$NODE_SG"
    echo ""
    echo "# 3. Cluster → Node (443) - Webhook"
    echo "aws ec2 authorize-security-group-ingress --group-id \$NODE_SG --protocol tcp --port 443 --source-group \$CLUSTER_SG"
    echo "aws ec2 authorize-security-group-egress --group-id \$CLUSTER_SG --protocol tcp --port 443 --destination-group \$NODE_SG"
    echo ""
    echo "# 4. Node ↔ Node (All)"
    echo "aws ec2 authorize-security-group-ingress --group-id \$NODE_SG --protocol -1 --source-group \$NODE_SG"
    echo ""
    echo "# 5. Node → Internet (All)"
    echo "aws ec2 authorize-security-group-egress --group-id \$NODE_SG --protocol -1 --cidr 0.0.0.0/0"
    echo ""
else
    echo -e "${GREEN}=========================================="
    echo "  모든 테스트 통과! 🎉"
    echo -e "==========================================${NC}"
    echo ""
    echo "EKS 클러스터 네트워크가 정상적으로 구성되어 있습니다."
fi

echo ""
echo "상세 문서: Network/eks-network-checklist.md"
echo ""
