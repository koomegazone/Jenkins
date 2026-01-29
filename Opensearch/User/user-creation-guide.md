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


## 4. Index Pattern 생성 (DevTools)

### 4.1 devpm 인덱스 패턴 생성

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



