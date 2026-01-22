# https://gasidaseo.notion.site/AWS-NLB-Client-IP-Proxy-protocol-57827e2c83fc474992b37e65db81f669


# build 
mkdir apache && cd apache

# httpd.conf 추출
docker run --rm httpd:2.4.48 cat /usr/local/apache2/conf/httpd.conf > my-httpd.conf

# PPv2 설정
sed -i "s/\#LoadModule remoteip_module/LoadModule remoteip_module/g" my-httpd.conf
echo 'RemoteIPProxyProtocol On' >> my-httpd.conf

# 빌드
cat <<EOT> Dockerfile
FROM httpd:2.4.48
COPY ./my-httpd.conf /usr/local/apache2/conf/httpd.conf
EOT
docker build -t koomzc/httpd2:pp ./

# 푸시
docker login
docker push koomzc/httpd2:pp

