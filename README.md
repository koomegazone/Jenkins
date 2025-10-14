LBC 없이 운영하는 경우
nodeport로 서비스를 만든 후 해당 포트에 대해서 remoteacess sg에 아웃바운드 오픈이 필요함
파드 -> 노드로의 통신을 위해서 

그리고 LB에서 타겟그룹에 인스턴스 추가될때마다 자동으로 연결이 되는지 확인필요.


```
kubectl exec -it netshoot-pod-744bd84b46-n8jgz -- zsh -c "for i in {1..100};   do curl -s $N1:30082 | grep Hostname; sleep 1; done"
```
