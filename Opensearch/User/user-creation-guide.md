# OpenSearch 사용자 분리 및 권한 설정 가이드 (DevTools)

## 개요
OpenSearch DevTools를 사용하여 인덱스 패턴별로 접근 권한을 분리하여 사용자를 생성하는 가이드입니다.

### 사용자 및 권한 요구사항
- **devpm 사용자**: `ai-app-d-devpm-*` 인덱스만 접근 가능
- **prism 사용자**: `ai-app-d-prism-*` 인덱스만 접근 가능

## 1. Role 생성

각 인덱스 패턴에 대한 Role을 먼저 생성합니다.

### 1.1 devpm Role 생성

```json
PUT _plugins/_security/api/roles/devpm_role
{
  "cluster_permissions": [
    "cluster_composite_ops_ro",
    "cluster:monitor/main",
    "cluster:monitor/health"
  ],
  "index_permissions": [
    {
      "index_patterns": [
        "ai-app-d-devpm-*"
      ],
      "allowed_actions": [
        "read",
        "search",
        "get",
        "indices:data/read/*",
        "indices:admin/mappings/get",
        "indices:admin/mappings/fields/get",
        "indices:admin/get",
        "indices:admin/exists",
        "indices:admin/types/exists",
        "indices:admin/validate/query",
        "indices:monitor/stats"
      ]
    },
    {
      "index_patterns": [
        ".kibana*",
        ".opensearch_dashboards*"
      ],
      "allowed_actions": [
        "read",
        "write",
        "delete",
        "indices:data/read/*",
        "indices:data/write/*",
        "indices:admin/create",
        "indices:admin/exists",
        "indices:admin/mapping/put",
        "indices:admin/mappings/get"
      ]
    }
  ],
  "tenant_permissions": [
    {
      "tenant_patterns": [
        "global_tenant"
      ],
      "allowed_actions": [
        "kibana_all_write"
      ]
    }
  ]
}
```

### 1.2 prism Role 생성

```json
PUT _plugins/_security/api/roles/prism_role
{
  "cluster_permissions": [
    "cluster_composite_ops_ro",
    "cluster:monitor/main",
    "cluster:monitor/health"
  ],
  "index_permissions": [
    {
      "index_patterns": [
        "ai-app-d-prism-*"
      ],
      "allowed_actions": [
        "read",
        "search",
        "get",
        "indices:data/read/*",
        "indices:admin/mappings/get",
        "indices:admin/mappings/fields/get",
        "indices:admin/get",
        "indices:admin/exists",
        "indices:admin/types/exists",
        "indices:admin/validate/query",
        "indices:monitor/stats"
      ]
    },
    {
      "index_patterns": [
        ".kibana*",
        ".opensearch_dashboards*"
      ],
      "allowed_actions": [
        "read",
        "write",
        "delete",
        "indices:data/read/*",
        "indices:data/write/*",
        "indices:admin/create",
        "indices:admin/exists",
        "indices:admin/mapping/put",
        "indices:admin/mappings/get"
      ]
    }
  ],
  "tenant_permissions": [
    {
      "tenant_patterns": [
        "global_tenant"
      ],
      "allowed_actions": [
        "kibana_all_write"
      ]
    }
  ]
}
```

## 2. Internal User 생성

### 2.1 devpm 사용자 생성

```json
PUT _plugins/_security/api/internalusers/devpm
{
  "password": "Secc1111!!!!",
  "backend_roles": [],
  "attributes": {
    "description": "DevPM team user with access to ai-app-d-devpm-* indices"
  }
}
```

### 2.2 prism 사용자 생성

```json
PUT _plugins/_security/api/internalusers/prism
{
  "password": "Secc1111!!!!",
  "backend_roles": [],
  "attributes": {
    "description": "Prism team user with access to ai-app-d-prism-* indices"
  }
}
```

## 3. Role Mapping (사용자와 Role 연결)

### 3.1 devpm 사용자에게 devpm_role 할당

```json
PUT _plugins/_security/api/rolesmapping/devpm_role
{
  "backend_roles": [],
  "hosts": [],
  "users": [
    "devpm"
  ]
}
```

### 3.2 prism 사용자에게 prism_role 할당

```json
PUT _plugins/_security/api/rolesmapping/prism_role
{
  "backend_roles": [],
  "hosts": [],
  "users": [
    "prism"
  ]
}
```

## 4. 권한 확인

### 4.1 devpm 사용자로 로그인 테스트

```bash
# devpm 사용자로 인덱스 조회
curl -u devpm:DevPm@2026! \
  "https://your-opensearch-domain/_cat/indices/ai-app-d-devpm-*?v"

# 접근 가능 (200 OK)
```

```bash
# prism 인덱스 조회 시도 (접근 불가)
curl -u devpm:DevPm@2026! \
  "https://your-opensearch-domain/_cat/indices/ai-app-d-prism-*?v"

# 접근 거부 (403 Forbidden)
```

### 4.2 prism 사용자로 로그인 테스트

```bash
# prism 사용자로 인덱스 조회
curl -u prism:Prism@2026! \
  "https://your-opensearch-domain/_cat/indices/ai-app-d-prism-*?v"

# 접근 가능 (200 OK)
```

```bash
# devpm 인덱스 조회 시도 (접근 불가)
curl -u prism:Prism@2026! \
  "https://your-opensearch-domain/_cat/indices/ai-app-d-devpm-*?v"

# 접근 거부 (403 Forbidden)
```

## 5. Index Pattern 생성 (DevTools)

### 5.1 devpm 인덱스 패턴 생성

DevTools에서 실행 (devpm 사용자로 로그인 후):

```json
POST .kibana/_doc/index-pattern:ai-app-d-devpm-*
{
  "type": "index-pattern",
  "index-pattern": {
    "title": "ai-app-d-devpm-*",
    "timeFieldName": "@timestamp"
  }
}
```

### 5.2 prism 인덱스 패턴 생성

DevTools에서 실행 (prism 사용자로 로그인 후):

```json
POST .kibana/_doc/index-pattern:ai-app-d-prism-*
{
  "type": "index-pattern",
  "index-pattern": {
    "title": "ai-app-d-prism-*",
    "timeFieldName": "@timestamp"
  }
}
```

## 6. 추가 권한 설정 (선택사항)

### 6.1 Dashboard 생성 권한 추가

사용자가 자신의 Dashboard를 생성하고 저장할 수 있도록 하려면:

```json
PUT _plugins/_security/api/roles/devpm_role
{
  "cluster_permissions": [
    "cluster_composite_ops_ro"
  ],
  "index_permissions": [
    {
      "index_patterns": [
        "ai-app-d-devpm-*"
      ],
      "allowed_actions": [
        "read",
        "search",
        "get",
        "indices:data/read/*",
        "indices:admin/mappings/get",
        "indices:admin/get"
      ]
    },
    {
      "index_patterns": [
        ".kibana*"
      ],
      "allowed_actions": [
        "read",
        "write",
        "delete",
        "indices:data/read/*",
        "indices:data/write/*"
      ]
    }
  ],
  "tenant_permissions": [
    {
      "tenant_patterns": [
        "global_tenant"
      ],
      "allowed_actions": [
        "kibana_all_write"
      ]
    }
  ]
}
```

### 6.2 Private Tenant 사용

각 사용자가 독립적인 작업 공간을 가지도록 설정:

```json
"tenant_permissions": [
  {
    "tenant_patterns": [
      "devpm_private"
    ],
    "allowed_actions": [
      "kibana_all_write"
    ]
  }
]
```

## 7. 비밀번호 변경

### 사용자 스스로 비밀번호 변경

```bash
curl -X PUT "https://your-opensearch-domain/_plugins/_security/api/account" \
  -H 'Content-Type: application/json' \
  -u devpm:DevPm@2026! \
  -d '{
  "current_password": "DevPm@2026!",
  "password": "NewPassword@2026!"
}'
```

### Admin이 사용자 비밀번호 변경

```json
PUT _plugins/_security/api/internalusers/devpm
{
  "password": "NewPassword@2026!"
}
```

## 8. 트러블슈팅

### 권한 오류 발생 시

1. Role이 올바르게 생성되었는지 확인:
```bash
GET _plugins/_security/api/roles/devpm_role
```

2. Role Mapping 확인:
```bash
GET _plugins/_security/api/rolesmapping/devpm_role
```

3. 사용자 정보 확인:
```bash
GET _plugins/_security/api/internalusers/devpm
```

### 인덱스가 보이지 않는 경우

- 인덱스가 실제로 존재하는지 확인 (admin 계정으로)
- Index Pattern이 올바르게 생성되었는지 확인
- 브라우저 캐시 삭제 후 재로그인

### 403 Forbidden 오류

- Role의 index_patterns이 정확한지 확인
- allowed_actions에 필요한 권한이 모두 포함되어 있는지 확인
- Role Mapping이 올바르게 설정되었는지 확인

## 9. 보안 권장사항

1. **강력한 비밀번호 사용**
   - 최소 12자 이상
   - 대소문자, 숫자, 특수문자 조합

2. **정기적인 비밀번호 변경**
   - 3개월마다 비밀번호 변경 권장

3. **최소 권한 원칙**
   - 필요한 인덱스에만 접근 권한 부여
   - 읽기 전용 권한으로 시작

4. **감사 로그 활성화**
   - 사용자 활동 모니터링
   - 비정상적인 접근 시도 감지

5. **IP 화이트리스트 설정** (선택사항)
```json
{
  "hosts": [
    "10.0.0.0/8"
  ]
}
```

## 참고사항

- OpenSearch Security Plugin이 활성화되어 있어야 합니다
- Fine-grained access control이 활성화되어 있어야 합니다
- 사용자는 자신에게 할당된 인덱스 패턴만 볼 수 있습니다
- Admin 계정으로 모든 설정을 수행해야 합니다
