curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64

# 2. 실행 권한 부여 및 경로 이동
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd

# 3. 임시 파일 삭제
rm argocd-linux-amd64
