# Slurm-web API 參考

## 概述

Slurm-web 提供兩層 REST API：
1. **Gateway API** - 面向前端的統一入口
2. **Agent API** - 部署於各叢集的本地服務

所有 API 回應均為 JSON 格式。

---

## 認證

### JWT Token

大部分 API 端點需要 JWT 認證。Token 透過 `Authorization` header 傳遞：

```
Authorization: Bearer <token>
```

### 取得 Token

#### 登入（啟用認證時）

```http
POST /api/login
Content-Type: application/json

{
  "user": "username",
  "password": "password"
}
```

**回應**:
```json
{
  "result": "Authentication successful",
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "fullname": "User Full Name",
  "groups": ["group1", "group2"]
}
```

#### 匿名存取（關閉認證時）

```http
GET /api/anonymous
```

**回應**:
```json
{
  "result": "Successful anonymous access",
  "token": "eyJhbGciOiJIUzI1NiIs..."
}
```

---

## Gateway API

Base URL: `http://<gateway-host>:<port>/api`

### 通用端點

#### 版本資訊

```http
GET /api/version
```

**回應**:
```
Slurm-web gateway v6.0.0
```

#### 登入訊息

```http
GET /api/messages/login
```

**回應**: HTML 格式的登入訊息

---

### 叢集管理

#### 取得叢集列表

```http
GET /api/clusters
Authorization: Bearer <token>
```

**回應**:
```json
[
  {
    "name": "cluster1",
    "racksdb": true,
    "infrastructure": "cluster1",
    "metrics": true,
    "cache": true,
    "permissions": {
      "roles": ["user"],
      "actions": ["view-stats", "view-jobs", "view-nodes"]
    }
  }
]
```

#### 取得使用者列表

```http
GET /api/users
Authorization: Bearer <token>
```

**回應**:
```json
[
  {"login": "user1", "fullname": "User One"},
  {"login": "user2", "fullname": "User Two"}
]
```

---

### 叢集代理端點

所有叢集相關的請求都透過 Gateway 代理到對應的 Agent。

#### Ping 叢集

```http
GET /api/agents/{cluster}/ping
Authorization: Bearer <token>
```

**回應**:
```json
{
  "versions": {
    "slurm": "24.11.0",
    "api": "0.0.43"
  }
}
```

#### 取得統計資料

```http
GET /api/agents/{cluster}/stats
Authorization: Bearer <token>
```

**回應**:
```json
{
  "resources": {
    "nodes": 100,
    "cores": 4000,
    "memory": 8000000,
    "gpus": 200
  },
  "jobs": {
    "running": 50,
    "total": 150
  }
}
```

---

### 工作管理

#### 取得工作列表

```http
GET /api/agents/{cluster}/jobs
Authorization: Bearer <token>
```

**Query Parameters**:
- `node` (optional): 過濾指定節點的工作

**回應**:
```json
[
  {
    "account": "default",
    "cpus": {"infinite": false, "number": 4, "set": true},
    "gres_detail": ["gpu:1"],
    "job_id": 12345,
    "job_state": ["RUNNING"],
    "node_count": {"infinite": false, "number": 1, "set": true},
    "nodes": "node001",
    "partition": "gpu",
    "priority": {"infinite": false, "number": 1000, "set": true},
    "qos": "normal",
    "state_reason": "None",
    "user_name": "user1"
  }
]
```

#### 取得單一工作

```http
GET /api/agents/{cluster}/job/{job_id}
Authorization: Bearer <token>
```

**回應**:
```json
{
  "association": {
    "account": "default",
    "cluster": "cluster1",
    "id": 1,
    "partition": "",
    "user": "user1"
  },
  "comment": {
    "administrator": "",
    "job": "",
    "system": ""
  },
  "derived_exit_code": {
    "return_code": {"infinite": false, "number": 0, "set": true},
    "signal": {"id": {"infinite": false, "number": 0, "set": false}, "name": ""},
    "status": ["SUCCESS"]
  },
  "exit_code": {...},
  "group": "users",
  "name": "job_name",
  "nodes": "node001",
  "partition": "gpu",
  "script": "#!/bin/bash\n...",
  "state": {
    "current": ["COMPLETED"],
    "reason": "None"
  },
  "steps": [...],
  "time": {
    "elapsed": 3600,
    "eligible": 1702900000,
    "end": 1702903600,
    "start": 1702900000,
    "submission": 1702899900
  },
  "user": "user1"
}
```

---

### 節點管理

#### 取得節點列表

```http
GET /api/agents/{cluster}/nodes
Authorization: Bearer <token>
```

**回應**:
```json
[
  {
    "name": "node001",
    "cpus": 64,
    "sockets": 2,
    "cores": 32,
    "gres": "gpu:4",
    "gres_used": "gpu:2",
    "real_memory": 256000,
    "state": ["MIXED"],
    "reason": "",
    "partitions": ["gpu", "all"],
    "alloc_cpus": 32,
    "alloc_idle_cpus": 32
  }
]
```

#### 取得單一節點

```http
GET /api/agents/{cluster}/node/{node_name}
Authorization: Bearer <token>
```

**回應**:
```json
{
  "name": "node001",
  "architecture": "x86_64",
  "operating_system": "Linux 5.15.0",
  "boot_time": {"infinite": false, "number": 1702800000, "set": true},
  "last_busy": {"infinite": false, "number": 1702900000, "set": true},
  "cpus": 64,
  "sockets": 2,
  "cores": 32,
  "threads": 1,
  "real_memory": 256000,
  "gres": "gpu:4",
  "gres_used": "gpu:2",
  "state": ["MIXED"],
  "reason": "",
  "partitions": ["gpu", "all"],
  "alloc_cpus": 32,
  "alloc_idle_cpus": 32,
  "alloc_memory": 128000
}
```

---

### 其他資源

#### 取得分區列表

```http
GET /api/agents/{cluster}/partitions
Authorization: Bearer <token>
```

**回應**:
```json
[
  {
    "name": "gpu",
    "node_sets": "node[001-010]"
  }
]
```

#### 取得 QoS 列表

```http
GET /api/agents/{cluster}/qos
Authorization: Bearer <token>
```

#### 取得預約列表

```http
GET /api/agents/{cluster}/reservations
Authorization: Bearer <token>
```

#### 取得帳戶列表

```http
GET /api/agents/{cluster}/accounts
Authorization: Bearer <token>
```

#### 取得關聯列表

```http
GET /api/agents/{cluster}/associations
Authorization: Bearer <token>
```

---

### 快取管理

#### 取得快取統計

```http
GET /api/agents/{cluster}/cache/stats
Authorization: Bearer <token>
```

**回應**:
```json
{
  "hit": {
    "keys": {"jobs": 100, "nodes": 50},
    "total": 150
  },
  "miss": {
    "keys": {"jobs": 10, "nodes": 5},
    "total": 15
  }
}
```

#### 重設快取

```http
POST /api/agents/{cluster}/cache/reset
Authorization: Bearer <token>
```

---

### 指標

#### 取得節點指標

```http
GET /api/agents/{cluster}/metrics/nodes?range={range}
Authorization: Bearer <token>
```

**Query Parameters**:
- `range`: `hour` | `day` | `week`

**回應**:
```json
{
  "idle": [[1702900000, 50], [1702900060, 48]],
  "mixed": [[1702900000, 30], [1702900060, 32]],
  "allocated": [[1702900000, 20], [1702900060, 20]],
  "down": [[1702900000, 0], [1702900060, 0]]
}
```

#### 取得 CPU 指標

```http
GET /api/agents/{cluster}/metrics/cores?range={range}
Authorization: Bearer <token>
```

#### 取得 GPU 指標

```http
GET /api/agents/{cluster}/metrics/gpus?range={range}
Authorization: Bearer <token>
```

#### 取得工作指標

```http
GET /api/agents/{cluster}/metrics/jobs?range={range}
Authorization: Bearer <token>
```

#### 取得快取指標

```http
GET /api/agents/{cluster}/metrics/cache?range={range}
Authorization: Bearer <token>
```

---

### RacksDB 整合

#### 取得基礎設施圖片

```http
POST /api/agents/{cluster}/racksdb/draw/infrastructure/{infrastructure}.png?coordinates
Authorization: Bearer <token>
Content-Type: application/json

{
  "general": {"pixel_perfect": true},
  "dimensions": {"width": 800, "height": 600},
  "infrastructure": {"equipment_labels": false, "ghost_unselected": true}
}
```

**回應**: Multipart 回應，包含：
- `image`: PNG 圖片
- `coordinates`: 設備座標 JSON

---

## Agent API

Agent API 通常不直接暴露給前端，而是透過 Gateway 代理存取。

Base URL: `http://<agent-host>:<port>`

### 端點

| 端點 | 方法 | RBAC Action | 說明 |
|------|------|-------------|------|
| `/version` | GET | - | 版本資訊 |
| `/info` | GET | - | Agent 資訊 |
| `/v{version}/permissions` | GET | - | 使用者權限 |
| `/v{version}/ping` | GET | - | Slurm 連線測試 |
| `/v{version}/stats` | GET | view-stats | 統計摘要 |
| `/v{version}/jobs` | GET | view-jobs | 工作列表 |
| `/v{version}/job/{id}` | GET | view-jobs | 工作詳情 |
| `/v{version}/nodes` | GET | view-nodes | 節點列表 |
| `/v{version}/node/{name}` | GET | view-nodes | 節點詳情 |
| `/v{version}/partitions` | GET | view-partitions | 分區列表 |
| `/v{version}/qos` | GET | view-qos | QoS 列表 |
| `/v{version}/reservations` | GET | view-reservations | 預約列表 |
| `/v{version}/accounts` | GET | view-accounts | 帳戶列表 |
| `/v{version}/associations` | GET | associations-view | 關聯列表 |
| `/v{version}/cache/stats` | GET | cache-view | 快取統計 |
| `/v{version}/cache/reset` | POST | cache-reset | 重設快取 |
| `/v{version}/metrics/{metric}` | GET | view-* | Prometheus 指標 |
| `/metrics` | GET | - | Prometheus 端點 |

---

## 錯誤回應

所有 API 錯誤以 JSON 格式回傳：

```json
{
  "code": 404,
  "name": "Not Found",
  "description": "Job 12345 not found"
}
```

### HTTP 狀態碼

| 狀態碼 | 說明 |
|--------|------|
| 200 | 成功 |
| 401 | 未認證 |
| 403 | 權限不足 |
| 404 | 資源不存在 |
| 500 | 伺服器錯誤 |
| 501 | 功能未啟用 |

---

## RBAC Actions

| Action | 說明 |
|--------|------|
| `view-stats` | 檢視統計資料 |
| `view-jobs` | 檢視工作 |
| `view-nodes` | 檢視節點 |
| `view-partitions` | 檢視分區 |
| `view-qos` | 檢視 QoS |
| `view-reservations` | 檢視預約 |
| `view-accounts` | 檢視帳戶 |
| `associations-view` | 檢視關聯 |
| `cache-view` | 檢視快取統計 |
| `cache-reset` | 重設快取 |

---

*此文件由 BMAD Document Project Workflow 自動生成*
