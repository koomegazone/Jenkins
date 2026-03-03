# Install kubectl & helm
cd /root
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.31.2/2024-11-15/bin/linux/amd64/kubectl
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Install Kubecolor
wget https://github.com/kubecolor/kubecolor/releases/download/v0.5.0/kubecolor_0.5.0_linux_amd64.tar.gz
tar -zxvf kubecolor_0.5.0_linux_amd64.tar.gz
mv kubecolor /usr/local/bin/
echo 'alias kubectl="kubecolor"' >> ~/.bashrc 

            # 최신 버전 다운로드
curl -sL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz | tar xz -C /tmp

# 실행 파일 이동
sudo mv /tmp/k9s /usr/local/bin/

# 권한 설정
sudo chmod +x /usr/local/bin/k9s

# 확인
k9s version

echo 'Scrit End!'