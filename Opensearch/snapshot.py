from opensearchpy import OpenSearch
import urllib3

urllib3.disable_warnings()

# --- 사용자 환경 설정 ---
OPENSEARCH_HOST = "search-newtest-dgiheqvqtxkbaolzzdh2gdwja4.ap-northeast-2.es.amazonaws.com"
PORT = 443

# 인증 정보 (sigv4 쓰는 환경이면 boto3 signer로 변경 필요)
USERNAME = "admin"
PASSWORD = "Megazone00!!!"   # 실제 비밀번호로 변경!

# --- Snapshot Repository 설정 ---
REPO_NAME = "test-opensearch-koo"

REPO_BODY = {
    "type": "s3",
    "settings": {
        "bucket": "test-opensearch-koo",
        "region": "ap-northeast-2",
        "role_arn": "arn:aws:iam::064711168361:role/TheSnapshotRole"
    }
}

def main():
    client = OpenSearch(
        hosts=[{"host": OPENSEARCH_HOST, "port": PORT}],
        http_auth=(USERNAME, PASSWORD),
        use_ssl=True,
        verify_certs=False
    )

    print(f"Registering snapshot repository: {REPO_NAME}")
    response = client.snapshot.create_repository(
        repository=REPO_NAME,
        body=REPO_BODY
    )

    print("Response:")
    print(response)


if __name__ == "__main__":
    main()
