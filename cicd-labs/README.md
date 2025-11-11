# build
docker build -t koomzc/php:pp ./
# 푸시
docker login
docker push koomzc/php:pp


kubectl create secret generic regcred \
    --from-file=.dockerconfigjson=/root/.docker/config.json \
    --type=kubernetes.io/dockerconfigjson
