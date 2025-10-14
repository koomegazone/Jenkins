```https://zigispace.net/1174```

ALB를 사용하는 경우 인스턴스모드와 ip모드가 있는데 
인스턴스 모드는 노드의 nodePort로 NAT되어 통신되고
ip 모드는 pod의 pod ip로 직접 통신을 함 
따라서 직접적인 성능 차이를 보일수 있음.


kubectl exec -it netshoot-pod-744bd84b46-n8jgz -- zsh -c "for i in {1..100};   do curl -s $N1:30082 | grep Hostname; sleep 1; done"

