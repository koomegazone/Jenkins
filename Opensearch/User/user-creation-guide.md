# OpenSearch 사용자 분리 및 권한 설정 가이드

## 개요
OpenSearch에서 인덱스 패턴별로 접근 권한을 분리하여 사용자를 생성하는 가이드입니다.

### 사용자 및 권한 요구사항
- **devpm 사용자**: `ai-app-d-devpm-*` 인덱스만 접근 가능
- **prism 사용자**: `ai-app-d-prism-*` 인덱스만 접근 가능

## 1. Role 생성

각 인덱스 패턴에 대한 Role을 먼저 생성합니다.

### 1.1 devpm Role 생성

OpenSearch Dashboards → Security → Roles → Create role

**Dev Tools에서 생성:**

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
        "indices:data/read/search",
        "indices:data/read/get",
        "indices:admin/mappings/get",
        "indices:admin/get"
      ]
    }
  ],
  "tenant_permissions": [
    {
      "tenant_patterns": [
        "global_tenant"
      ],
      "allowed_actions": [
        "kibana_all_read"
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
    "cluster_composite_ops_ro"
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
        "indices:data/read/search",
        "indices:data/read/get",
        "indices:admin/mappings/get",
        "indices:admin/get"
      ]
    }
  ],
  "tenant_permissions": [
    {
      "tenant_patterns": [
        "global_tenant"
      ],
      "allowed_actions": [
        "kibana_all_read"
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
  "password": "DevPm@2026!",
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
  "password": "Prism@2026!",
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

## 4. OpenSearch Dashboards UI에서 생성하기

### 4.1 Role 생성

1. OpenSearch Dashboards 접속 (admin 계정)
2. 좌측 메뉴 → **Security** → **Roles**
3. **Create role** 클릭

#### devpm_role 설정:

**Role name**: `devpm_role`

**Cluster permissions**:
- `cluster_composite_ops_ro`

**Index permissions**:
- Index patterns: `ai-app-d-devpm-*`
- Permissions:
  - `read`
  - `search`
  - `get`
  - `indices:data/read/*`
  - `indices:admin/mappings/get`
  - `indices:admin/get`

**Tenant permissions**:
- Tenant pattern: `global_tenant`
- Permissions: `kibana_all_read`

4. **Create** 클릭

#### prism_role 설정:

동일한 방법으로 `prism_role` 생성하되, Index patterns를 `ai-app-d-prism-*`로 설정

### 4.2 Internal User 생성

1. 좌측 메뉴 → **Security** → **Internal Users**
2. **Create internal user** 클릭

#### devpm 사용자:
- Username: `devpm`
- Password: `DevPm@2026!`
- Confirm password: `DevPm@2026!`
- Backend roles: (비워둠)
- Attributes: `description: DevPM team user`

3. **Create** 클릭

#### prism 사용자:
동일한 방법으로 `prism` 사용자 생성

### 4.3 Role Mapping

1. 좌측 메뉴 → **Security** → **Roles**
2. `devpm_role` 클릭
3. **Mapped users** 탭 선택
4. **Map users** 클릭
5. Users 필드에 `devpm` 입력
6. **Map** 클릭

동일한 방법으로 `prism_role`에 `prism` 사용자 매핑

## 5. 권한 확인

### 5.1 devpm 사용자로 로그인 테스트

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

### 5.2 prism 사용자로 로그인 테스트

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

## 6. Index Pattern 생성 (각 사용자별)

### 6.1 devpm 사용자로 로그인

1. OpenSearch Dashboards에 `devpm` 계정으로 로그인
2. **Management** → **Index Patterns** → **Create index pattern**
3. Index pattern: `ai-app-d-devpm-*`
4. Time field: `@timestamp`
5. **Create index pattern**

### 6.2 prism 사용자로 로그인

1. OpenSearch Dashboards에 `prism` 계정으로 로그인
2. **Management** → **Index Patterns** → **Create index pattern**
3. Index pattern: `ai-app-d-prism-*`
4. Time field: `@timestamp`
5. **Create index pattern**

## 7. 추가 권한 설정 (선택사항)

### 7.1 Dashboard 생성 권한 추가

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

### 7.2 Private Tenant 사용

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

## 8. 비밀번호 변경

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

## 9. 트러블슈팅

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

## 10. 보안 권장사항

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
