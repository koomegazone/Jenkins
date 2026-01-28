# OpenSearch 인덱스 패턴 생성 가이드

## 개요
Fluentbit에서 `ai-app-d-devpm-%Y-%m-%d` 형태로 일단위 인덱스를 생성하여 로그 데이터를 전송합니다.
이 가이드는 해당 인덱스 패턴을 OpenSearch에서 설정하는 방법을 안내합니다.

## 인덱스 설정 정보
- **인덱스 패턴**: `ai-app-d-devpm-*`
- **인덱스 생성 주기**: 일단위 (Daily)
- **인덱스 형식**: `ai-app-d-devpm-YYYY-MM-DD`
- **Shard 정책**:
  - Primary Shards: 1
  - Replica Shards: 1

## 1. 인덱스 템플릿 생성

인덱스가 자동으로 생성될 때 Shard 설정을 적용하기 위해 인덱스 템플릿을 먼저 생성합니다.

### OpenSearch Dashboards에서 생성

1. OpenSearch Dashboards 접속
2. 좌측 메뉴에서 **Dev Tools** 선택
3. 다음 명령어 실행:

```json
PUT _index_template/ai-app-d-devpm-template
{
  "index_patterns": ["ai-app-d-devpm-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.refresh_interval": "5s"
    }
  },
  "priority": 100
}
```

### curl 명령어로 생성

```bash
curl -X PUT "https://your-opensearch-domain.ap-northeast-2.es.amazonaws.com/_index_template/ai-app-d-devpm-template" \
  -H 'Content-Type: application/json' \
  -u admin:!Admin$00 \
  -d '{
  "index_patterns": ["ai-app-d-devpm-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.refresh_interval": "5s"
    }
  },
  "priority": 100
}'
```

## 2. Fluentbit Output 설정

Fluentbit의 `values.yaml` 파일에서 Output 설정을 다음과 같이 구성합니다:

```yaml
outputs: |
  [OUTPUT]
      Name opensearch
      Match *
      Host vpc-prism-q-an2-osr-5lpujbhxra64taa7srhc6fi3jm.ap-northeast-2.es.amazonaws.com
      Port 443
      Index ai-app-d-devpm-%Y-%m-%d
      Type _doc
      tls On
      tls.verify Off
      Suppress_Type_Name On
      AWS_Auth Off
      AWS_Region ap-northeast-2
      Http_User admin
      Http_Passwd !Admin$00
      Retry_Limit 2
```

**주요 설정 항목**:
- `Index ai-app-d-devpm-%Y-%m-%d`: 일단위로 인덱스 생성
  - `%Y`: 4자리 연도 (예: 2026)
  - `%m`: 2자리 월 (예: 01)
  - `%d`: 2자리 일 (예: 28)

## 3. 인덱스 패턴 생성 (OpenSearch Dashboards)

### 3.1 사용자별 Index Pattern 생성 가이드

#### devpm 사용자로 Index Pattern 생성

**Step 1: OpenSearch Dashboards 로그인**
1. OpenSearch Dashboards 접속
2. Username: `devpm`
3. Password: 사용자 비밀번호 입력
4. **Log in** 클릭

**Step 2: Tenant 선택**
1. 로그인 후 Tenant 선택 화면이 나타남
2. **Global** 선택 (또는 Private tenant)
3. **Confirm** 클릭

**Step 3: Index Pattern 생성**
1. 좌측 메뉴에서 **Management** 클릭
2. **Dashboard Management** 섹션에서 **Index Patterns** 선택
3. **Create index pattern** 버튼 클릭
4. **Index pattern name** 입력: `ai-app-d-devpm-*`
5. 매칭되는 인덱스 목록이 표시되는지 확인
   - 예: `ai-app-d-devpm-2026-01-28`
   - "No matching indices found" 메시지가 나오면 인덱스가 아직 생성되지 않은 것
6. **Next step** 버튼 클릭
7. **Time field** 선택: `@timestamp`
8. **Create index pattern** 버튼 클릭

**Step 4: 로그 확인 (Discover)**
1. 좌측 메뉴에서 **Discover** 클릭
2. 상단 Index pattern 드롭다운에서 `ai-app-d-devpm-*` 선택
3. 시간 범위 설정 (우측 상단 시계 아이콘)
   - Last 15 minutes
   - Last 1 hour
   - Last 24 hours
   - 또는 Custom time range
4. 로그 데이터 확인

**Step 5: 필드 확인 및 필터링**
1. 좌측 **Available fields** 패널에서 주요 필드 확인:
   - `kubernetes.namespace_name`
   - `kubernetes.pod_name`
   - `kubernetes.container_name`
   - `log` (실제 로그 메시지)
2. 필드 클릭 → **Add** 버튼으로 컬럼 추가
3. 검색창에서 KQL 쿼리로 필터링:
   ```
   kubernetes.namespace_name: "default"
   kubernetes.pod_name: "my-app-*"
   log: "error"
   ```

### 3.2 Admin 사용자로 Index Pattern 생성 (전체 인덱스 접근)

1. OpenSearch Dashboards 접속 (admin 계정)
2. 좌측 메뉴에서 **Management** → **Dashboard Management** → **Index Patterns** 선택
3. **Create index pattern** 버튼 클릭
4. 인덱스 패턴 입력: `ai-app-d-devpm-*`
5. **Next step** 클릭
6. Time field 선택: `@timestamp`
7. **Create index pattern** 클릭

### 3.3 Index Pattern이 보이지 않는 경우

**문제**: "No matching indices found" 메시지가 표시됨

**해결 방법**:

1. **인덱스가 실제로 존재하는지 확인** (admin 계정으로 Dev Tools에서):
```bash
GET _cat/indices/ai-app-d-devpm-*?v
```

2. **Fluent Bit에서 데이터가 전송되고 있는지 확인**:
```bash
kubectl logs -n logging -l app.kubernetes.io/name=fluent-bit --tail=50
```

3. **권한 확인** (devpm 사용자로 Dev Tools에서):
```bash
GET ai-app-d-devpm-*/_search
{
  "size": 1
}
```

4. **Fluent Bit Output Match 설정 확인**:
   - `Match opensearch` → `Match kube.*` 또는 `Match *`로 변경 필요
   - Input Tag와 Output Match가 일치해야 함

5. **브라우저 캐시 삭제 후 재로그인**

### 3.4 Dashboard 및 Visualization 생성 (선택사항)

#### Dashboard 생성
1. 좌측 메뉴에서 **Dashboard** 클릭
2. **Create dashboard** 버튼 클릭
3. **Add** 버튼으로 Visualization 추가
4. 우측 상단 **Save** 버튼으로 저장
   - Title: "DevPM Application Logs"
   - Description: "ai-app-d-devpm 로그 모니터링"

#### Visualization 생성 예시
1. 좌측 메뉴에서 **Visualize** 클릭
2. **Create visualization** 버튼 클릭
3. Visualization 타입 선택:
   - **Line chart**: 시간별 로그 추이
   - **Pie chart**: 네임스페이스별 로그 분포
   - **Data table**: 로그 상세 테이블
   - **Metric**: 총 로그 카운트
4. Index pattern 선택: `ai-app-d-devpm-*`
5. 메트릭 및 버킷 설정
6. **Save** 버튼으로 저장

## 4. 인덱스 확인

### 생성된 인덱스 목록 확인

```bash
# Dev Tools에서 실행
GET _cat/indices/ai-app-d-devpm-*?v
```

예상 결과:
```
health status index                      pri rep docs.count docs.deleted store.size pri.store.size
green  open   ai-app-d-devpm-2026-01-28   1   1      12345            0     10.5mb          5.2mb
green  open   ai-app-d-devpm-2026-01-27   1   1      45678            0     25.3mb         12.6mb
```

### 특정 인덱스 설정 확인

```bash
GET ai-app-d-devpm-2026-01-28/_settings
```

## 5. 인덱스 관리 정책 (ISM Policy) - 선택사항

로그 데이터의 라이프사이클 관리를 위해 ISM 정책을 설정할 수 있습니다.

### 예시: 30일 후 삭제 정책

```json
PUT _plugins/_ism/policies/ai-app-d-devpm-policy
{
  "policy": {
    "description": "Delete indices older than 30 days",
    "default_state": "hot",
    "states": [
      {
        "name": "hot",
        "actions": [],
        "transitions": [
          {
            "state_name": "delete",
            "conditions": {
              "min_index_age": "30d"
            }
          }
        ]
      },
      {
        "name": "delete",
        "actions": [
          {
            "delete": {}
          }
        ]
      }
    ],
    "ism_template": [
      {
        "index_patterns": ["ai-app-d-devpm-*"],
        "priority": 100
      }
    ]
  }
}
```

## 6. 검색 및 시각화

### Discover에서 로그 확인

1. 좌측 메뉴에서 **Discover** 선택
2. 인덱스 패턴 선택: `ai-app-d-devpm-*`
3. 시간 범위 설정 후 로그 확인

### 주요 필드

Fluentbit Kubernetes 필터가 추가하는 주요 필드:
- `kubernetes.namespace_name`: 네임스페이스
- `kubernetes.pod_name`: 파드 이름
- `kubernetes.container_name`: 컨테이너 이름
- `kubernetes.labels.*`: 쿠버네티스 레이블
- `log`: 실제 로그 메시지
- `@timestamp`: 로그 타임스탬프

## 7. 트러블슈팅

### 인덱스가 생성되지 않는 경우

1. Fluentbit 로그 확인:
```bash
kubectl logs -n logging -l app=fluent-bit
```

2. OpenSearch 연결 확인:
```bash
curl -u admin:!Admin$00 https://your-opensearch-domain/_cluster/health
```

### Shard 설정이 적용되지 않는 경우

- 인덱스 템플릿이 인덱스 생성 전에 만들어져야 합니다
- 기존 인덱스는 템플릿 영향을 받지 않으므로 재생성 필요

```bash
# 기존 인덱스 삭제 (주의: 데이터 손실)
DELETE ai-app-d-devpm-2026-01-28
```

## 참고사항

- 인덱스는 Fluentbit이 첫 로그를 전송할 때 자동으로 생성됩니다
- Primary Shard 1, Replica 1 설정은 소규모 환경에 적합합니다
- 대용량 로그의 경우 Shard 수를 늘리는 것을 고려하세요
- 일단위 인덱스는 관리와 삭제가 용이합니다
