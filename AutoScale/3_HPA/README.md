sed -i -e "s|<YOUR CLUSTER NAME>|$CLUSTER_NAME|g" cluster-autoscaler-autodiscover.yaml
kubectl apply -f cluster-autoscaler-autodiscover.yaml
