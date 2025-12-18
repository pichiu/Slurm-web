# Slurm-web 與 Slurm 通訊機制深入探討

## 概述

Slurm-web 透過 **slurmrestd** (Slurm REST API Daemon) 與 Slurm 叢集進行通訊。slurmrestd 是 Slurm 官方提供的 REST API 服務，將 Slurm 的內部資料以 JSON 格式透過 HTTP 協定暴露出來。

本文件深入探討 Slurm-web 如何實作這個通訊層，包括：
- 通訊架構與資料流
- Gateway 代理機制
- Agent 核心模組分析
- 認證機制
- 版本適配策略
- 快取機制
- 範例程式碼
- 最佳實踐與常見問題

---

## 架構總覽

```
┌─────────────────────────────────────────────────────────────────┐
│                        Frontend (Vue 3)                          │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Gateway (Flask)                               │
│  - 使用者認證 (LDAP + JWT)                                        │
│  - 代理請求到 Agent                                               │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Agent (Flask)                                │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              SlurmrestdFilteredCached                     │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │                SlurmrestdFiltered                   │  │   │
│  │  │  ┌──────────────────────────────────────────────┐  │  │   │
│  │  │  │              SlurmrestdAdapter                │  │  │   │
│  │  │  │  ┌────────────────────────────────────────┐  │  │  │   │
│  │  │  │  │              Slurmrestd                 │  │  │  │   │
│  │  │  │  │  - HTTP/Unix Socket 通訊               │  │  │  │   │
│  │  │  │  │  - 認證處理                            │  │  │  │   │
│  │  │  │  └────────────────────────────────────────┘  │  │  │   │
│  │  │  │  - 版本適配                                  │  │  │   │
│  │  │  └──────────────────────────────────────────────┘  │  │   │
│  │  │  - 欄位過濾                                        │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  - Redis 快取                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      slurmrestd                                  │
│  - Slurm 官方 REST API                                          │
│  - 支援 Unix Socket 或 TCP/HTTP                                  │
│  - JWT 認證                                                      │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Slurm Controller (slurmctld)                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Gateway 代理機制

Gateway 作為中央入口點，負責將 Frontend 的請求代理轉發到對應的 Agent。這使得 Frontend 只需連接單一端點，即可存取多個 Slurm 叢集。

### 代理架構概覽

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│   Frontend  │ ──────> │   Gateway   │ ──────> │   Agent 1   │
│             │         │             │ ──────> │   Agent 2   │
│             │         │             │ ──────> │   Agent N   │
└─────────────┘         └─────────────┘         └─────────────┘
     HTTP                   aiohttp                  HTTP
   (同步)                  (非同步)                (同步)
```

### 相關檔案

| 檔案 | 說明 |
|------|------|
| `slurmweb/apps/gateway.py` | Gateway 應用程式與 Agent 管理 |
| `slurmweb/views/gateway.py` | Gateway 視圖函數與代理邏輯 |

### Agent 資訊管理

**檔案**: `slurmweb/apps/gateway.py:45-77`

Gateway 維護一個 Agent 資訊字典，記錄每個叢集的連線資訊：

```python
class SlurmwebAgent:
    """代表一個遠端 Agent 的連線資訊"""
    def __init__(self, version, cluster, racksdb, metrics, cache, url):
        self.version = version      # Agent API 版本
        self.cluster = cluster      # 叢集名稱（唯一識別碼）
        self.metrics = metrics      # 是否啟用 Prometheus metrics
        self.cache = cache          # 是否啟用 Redis 快取
        self.racksdb = racksdb      # RacksDB 設定
        self.url = url              # Agent URL（如 https://agent1:5012）

    @classmethod
    def from_json(cls, url, data):
        """從 Agent /info 端點的 JSON 回應建立實例"""
        return cls(
            data["version"],
            data["cluster"],
            SlurmwebAgentRacksDBSettings(**data["racksdb"]),
            data["metrics"],
            data["cache"],
            url,
        )
```

### Agent 探索機制

**檔案**: `slurmweb/apps/gateway.py:156-239`

Gateway 使用 **aiohttp** 非同步並行查詢所有配置的 Agent：

```python
async def _get_agent_info(self, url) -> SlurmwebAgent:
    """從單一 Agent 取得資訊"""
    async with aiohttp.ClientSession(
        connector=self.get_agent_connector()
    ) as session:
        async with session.get(f"{url}/info") as response:
            if response.status != 200:
                raise SlurmwebAgentError(f"unexpected status code {response.status}")
            agent = SlurmwebAgent.from_json(url, await response.json())

    # 檢查 Agent 版本是否符合最低要求
    if not version_greater_or_equal(self.settings.agents.version, agent.version):
        logger.error("Unsupported agent version %s", agent.version)
        return None

    return agent

async def _get_agents_info(self):
    """並行取得所有 Agent 資訊"""
    return {
        agent.cluster: agent
        for agent in await asyncio.gather(
            *[self._get_agent_info(url.geturl()) for url in self.settings.agents.url]
        )
        if agent is not None
    }

@property
def agents(self):
    """取得 Agent 資訊（5 分鐘快取）"""
    if int(time.time()) < self._agents_timeout:
        return self._agents

    self._agents = asyncio_run(self._get_agents_info())
    self._agents_timeout = int(time.time()) + 300  # 5 分鐘後過期
    return self._agents
```

### 路由定義

**檔案**: `slurmweb/apps/gateway.py:112-140`

所有代理端點都以 `/api/agents/<cluster>/` 開頭：

```python
VIEWS = {
    # 直接 Gateway 端點
    SlurmwebAppRoute("/api/version", views.version),
    SlurmwebAppRoute("/api/login", views.login, methods=["POST"]),
    SlurmwebAppRoute("/api/clusters", views.clusters),

    # 代理到 Agent 的端點
    SlurmwebAppRoute("/api/agents/<cluster>/ping", views.ping),
    SlurmwebAppRoute("/api/agents/<cluster>/stats", views.stats),
    SlurmwebAppRoute("/api/agents/<cluster>/jobs", views.jobs),
    SlurmwebAppRoute("/api/agents/<cluster>/job/<int:job>", views.job),
    SlurmwebAppRoute("/api/agents/<cluster>/nodes", views.nodes),
    SlurmwebAppRoute("/api/agents/<cluster>/node/<name>", views.node),
    SlurmwebAppRoute("/api/agents/<cluster>/partitions", views.partitions),
    SlurmwebAppRoute("/api/agents/<cluster>/qos", views.qos),
    SlurmwebAppRoute("/api/agents/<cluster>/reservations", views.reservations),
    SlurmwebAppRoute("/api/agents/<cluster>/accounts", views.accounts),
    SlurmwebAppRoute("/api/agents/<cluster>/associations", views.associations),
    SlurmwebAppRoute("/api/agents/<cluster>/racksdb/<path:query>", views.racksdb, methods=["GET", "POST"]),
}
```

### 驗證裝飾器

**檔案**: `slurmweb/views/gateway.py:27-41`

每個代理視圖使用兩個裝飾器確保安全性：

```python
def validate_cluster(view):
    """驗證 cluster 參數是否對應到有效的 Agent"""
    @wraps(view)
    def wrapped(*args, **kwargs):
        cluster = kwargs["cluster"]
        if cluster not in current_app.agents.keys():
            abort(404, f"cluster {cluster} not found")
        return view(*args, **kwargs)
    return wrapped

# 使用範例
@check_jwt           # 1. 驗證使用者 JWT Token
@validate_cluster    # 2. 驗證叢集存在
def jobs(cluster: str):
    return proxy_agent(cluster, "jobs", request.token)
```

### 核心代理函式

**檔案**: `slurmweb/views/gateway.py:192-264`

#### request_agent - 建立 Agent 請求

```python
def request_agent(
    session: aiohttp.ClientSession,
    cluster: str,
    query: str,
    token: str = None,
    with_version: bool = True,
):
    """建立對 Agent 的 aiohttp 請求"""
    # 1. 設定認證 Header（轉發使用者 Token）
    headers = {}
    if token is not None:
        headers = {"Authorization": f"Bearer {token}"}

    # 2. 組裝目標 URL
    if with_version:
        url = f"{current_app.agents[cluster].url}/v{current_app.agents[cluster].version}/{query}"
    else:
        url = f"{current_app.agents[cluster].url}/{query}"

    # 3. 轉發 Query String
    if len(request.query_string):
        url += f"?{request.query_string.decode()}"

    # 4. 根據 HTTP 方法發送請求
    if request.method == "GET":
        return session.get(url, headers=headers)
    elif request.method == "POST":
        return session.post(url, headers=headers, json=request.json)
```

#### async_proxy_agent - 非同步代理執行

```python
async def async_proxy_agent(
    cluster: str,
    query: str,
    token: str = None,
    json: bool = True,
    with_version: bool = True,
):
    """非同步代理請求到 Agent 並回傳 Flask Response"""
    async with aiohttp.ClientSession(
        connector=current_app.get_agent_connector()
    ) as session:
        async with request_agent(session, cluster, query, token, with_version) as response:
            if json:
                # JSON 回應：解析並重新包裝
                return jsonify(await response.json()), response.status
            else:
                # 二進位回應（如 RacksDB 圖片）：直接轉發
                return Response(
                    await response.read(),
                    status=response.status,
                    mimetype=response.headers.get("content-type"),
                )

def proxy_agent(*args, **kwargs):
    """同步包裝器 - 在 Flask 同步環境中執行非同步代理"""
    return asyncio_run(async_proxy_agent(*args, **kwargs))
```

### 代理請求完整流程

```
Frontend                    Gateway                         Agent
   │                          │                               │
   │  GET /api/agents/        │                               │
   │  cluster1/jobs           │                               │
   │  Authorization: Bearer   │                               │
   │  {user_token}            │                               │
   │─────────────────────────>│                               │
   │                          │                               │
   │                     1. @check_jwt                        │
   │                        驗證 user_token                   │
   │                          │                               │
   │                     2. @validate_cluster                 │
   │                        檢查 "cluster1" ∈ agents          │
   │                          │                               │
   │                     3. proxy_agent("cluster1", "jobs")   │
   │                        └─> async_proxy_agent()           │
   │                            └─> request_agent()           │
   │                          │                               │
   │                          │  GET /v6/jobs                 │
   │                          │  Authorization: Bearer        │
   │                          │  {user_token}                 │
   │                          │──────────────────────────────>│
   │                          │                               │
   │                          │                          @check_jwt
   │                          │                          @rbac_action("view-jobs")
   │                          │                          slurmrestd.jobs()
   │                          │                               │
   │                          │<──────────────────────────────│
   │                          │  [jobs data]                  │
   │                          │                               │
   │<─────────────────────────│                               │
   │  [jobs data]             │                               │
```

### SSL/TLS 支援

**檔案**: `slurmweb/apps/gateway.py:142-154`

Gateway 支援自訂 CA 憑證，用於連接使用自簽憑證的 Agent：

```python
def get_agent_connector(self):
    """取得帶 SSL 設定的 aiohttp 連接器"""
    if not self.settings.agents.cacert:
        return None

    if not self.settings.agents.cacert.is_file():
        raise SlurmwebConfigurationError(
            f"Agent CA certificate file {self.settings.agents.cacert} not found"
        )
    return aiohttp.TCPConnector(
        ssl=ssl.create_default_context(cafile=str(self.settings.agents.cacert))
    )
```

### Gateway 代理機制特性總結

| 特性 | 說明 |
|------|------|
| **非同步 I/O** | 使用 aiohttp 進行非阻塞請求，提高並發效能 |
| **Token 轉發** | 將使用者 JWT Token 原封不動轉發給 Agent |
| **SSL/TLS 支援** | 可配置自訂 CA 憑證連接自簽 Agent |
| **Query String 轉發** | 保留原始請求參數（如 `?node=xxx`） |
| **多方法支援** | 支援 GET 和 POST 方法 |
| **Agent 資訊快取** | Agent 資訊快取 5 分鐘，減少探測開銷 |
| **版本化 URL** | 自動根據 Agent 版本組裝正確的 API 路徑 |
| **叢集驗證** | 請求前驗證目標叢集是否可用 |

### Gateway 配置

```ini
# /etc/slurm-web/gateway.ini

[agents]
# 定義所有 Agent URL
url =
  https://cluster1.example.com:5012
  https://cluster2.example.com:5012
  https://cluster3.example.com:5012

# 自訂 CA 憑證（用於自簽憑證）
cacert = /etc/slurm-web/agents-ca.crt

# 最低 Agent 版本要求
version = 6.0.0

# 最低 RacksDB 版本要求
racksdb_version = 0.5.0
```

---

## Agent 核心模組

### 檔案結構

```
slurmweb/slurmrestd/
├── __init__.py          # 核心客戶端類別
├── auth.py              # 認證處理
├── errors.py            # 例外定義
├── unix.py              # Unix Socket 適配器
└── adapters/
    ├── __init__.py      # 適配器註冊表
    ├── base.py          # 基礎適配器
    ├── v0_0_41.py       # v0.0.41 適配器
    ├── v0_0_42.py       # v0.0.42 適配器
    ├── v0_0_43.py       # v0.0.43 適配器
    └── v0_0_44.py       # v0.0.44 適配器
```

---

## Agent 類別階層

Slurm-web 使用裝飾者模式 (Decorator Pattern) 來逐層增加功能：

### 1. Slurmrestd (基礎類別)

**檔案**: `slurmweb/slurmrestd/__init__.py:37-158`

負責最底層的 HTTP 通訊：

```python
class Slurmrestd:
    """基礎 slurmrestd 客戶端"""

    def __init__(
        self,
        uri: urllib.parse.ParseResult,
        auth: SlurmrestdAuthentifier
    ):
        self.uri = uri
        self.auth = auth
        self.session = requests.Session()

        # 如果是 Unix Socket，安裝自訂適配器
        if self.uri.scheme == "unix":
            self.session.mount("http://", SlurmrestdUnixAdapter())
```

**核心方法**:

```python
def _execute_request(self, query: str) -> requests.models.Response:
    """執行 HTTP 請求"""
    url = f"{self._request_url()}/{query}"
    response = self.session.get(url, headers=self.auth.headers)
    return response

def request(self, query: str) -> dict:
    """發送請求並解析 JSON 回應"""
    response = self._execute_request(query)
    # 處理錯誤回應
    if response.status_code != 200:
        # 根據狀態碼拋出對應例外
        ...
    return response.json()

def discover(self) -> tuple[str, str, str]:
    """探索 slurmrestd 的 API 版本"""
    data = self.request("openapi/v3")
    # 解析版本資訊
    return (api_path, slurm_version, api_version)
```

### 2. SlurmrestdAdapter (版本適配)

**檔案**: `slurmweb/slurmrestd/__init__.py:161-275`

繼承 `Slurmrestd`，增加 API 版本適配功能：

```python
class SlurmrestdAdapter(Slurmrestd):
    """帶版本適配的 slurmrestd 客戶端"""

    def __init__(self, uri, auth, supported_versions):
        super().__init__(uri, auth)
        self.supported_versions = supported_versions
        self.adaptation_chain = None
        self.api_path = None

    def select_version(self):
        """選擇 API 版本並建立適配鏈"""
        self.api_path, slurm_version, api_version = self.discover()
        self.adaptation_chain = build_adaptation_chain(
            api_version,
            self.supported_versions
        )
```

### 3. SlurmrestdFiltered (欄位過濾)

**檔案**: `slurmweb/slurmrestd/__init__.py:278-433`

增加回應欄位過濾功能：

```python
class SlurmrestdFiltered(SlurmrestdAdapter):
    """帶欄位過濾的 slurmrestd 客戶端"""

    def __init__(self, uri, auth, versions, filters):
        super().__init__(uri, auth, versions)
        self.filters = filters

    def jobs(self) -> list:
        """取得工作列表（過濾後）"""
        data = self.request(f"{self.api_path}/jobs")
        jobs = []
        for job in data["jobs"]:
            filtered_job = self._apply_filters(job, "jobs")
            jobs.append(filtered_job)
        return jobs
```

### 4. SlurmrestdFilteredCached (快取)

**檔案**: `slurmweb/slurmrestd/__init__.py:436-610`

最上層類別，增加 Redis 快取：

```python
class SlurmrestdFilteredCached(SlurmrestdFiltered):
    """帶快取的 slurmrestd 客戶端"""

    def __init__(self, uri, auth, versions, filters, cache_settings, cache_service):
        super().__init__(uri, auth, versions, filters)
        self.cache_settings = cache_settings
        self.cache = cache_service

    def jobs(self) -> list:
        """取得工作列表（快取版）"""
        cache_key = CacheKey("jobs")

        # 嘗試從快取取得
        cached = self.cache.get(cache_key)
        if cached is not None:
            self.cache.count_hit(cache_key)
            return cached

        # 快取未命中，從 slurmrestd 取得
        self.cache.count_miss(cache_key)
        result = super().jobs()

        # 存入快取
        ttl = self.cache_settings.jobs
        self.cache.put(cache_key, result, ttl)

        return result
```

---

## 認證機制

### SlurmrestdAuthentifier 類別

**檔案**: `slurmweb/slurmrestd/auth.py`

支援兩種認證方式：

#### 1. JWT 認證（推薦）

```python
class SlurmrestdAuthentifier:
    def __init__(
        self,
        method: str,      # "jwt" 或 "local"
        jwt_mode: str,    # "auto" 或 "static"
        jwt_user: str,    # JWT 使用者名稱
        jwt_key: Path,    # JWT 金鑰檔案路徑
        jwt_lifespan: int,# Token 有效期（秒）
        jwt_token: str    # 靜態 Token（jwt_mode="static" 時使用）
    ):
        ...

    def _generate_token(self) -> str:
        """動態產生 JWT Token"""
        payload = {
            "exp": int(time.time()) + self.jwt_lifespan,
            "iat": int(time.time()),
            "sun": self.jwt_user,  # Slurm User Name
        }
        return jwt.encode(payload, self.jwt_key, algorithm="HS256")

    @property
    def headers(self) -> dict:
        """產生認證 HTTP Headers"""
        if self.method == "jwt":
            return {
                "X-SLURM-USER-NAME": self.jwt_user,
                "X-SLURM-USER-TOKEN": self._get_token(),
            }
        return {}  # local 認證不需要額外 headers
```

**JWT 模式**:
- `auto`: 自動產生短期 Token（預設 1 小時）
- `static`: 使用預先產生的長期 Token

#### 2. Local 認證（已棄用）

僅適用於 Unix Socket 連線，使用本地使用者身份驗證。

---

## 連線方式

### Unix Socket

**檔案**: `slurmweb/slurmrestd/unix.py`

使用自訂的 requests 適配器：

```python
class SlurmrestdUnixAdapter(requests.adapters.HTTPAdapter):
    """Unix Socket HTTP 適配器"""

    def get_connection(self, url, proxies=None):
        return SlurmrestdUnixConnectionPool(self.socket_path)

class SlurmrestdUnixConnection(urllib3.connection.HTTPConnection):
    """Unix Socket HTTP 連線"""

    def __init__(self, socket_path):
        super().__init__("localhost")
        self.socket_path = socket_path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(self.socket_path)
```

**配置範例**:
```ini
[slurmrestd]
uri = unix:///run/slurmrestd/slurmrestd.socket
```

### HTTP/TCP

直接使用 requests 預設的 HTTP 連線：

**配置範例**:
```ini
[slurmrestd]
uri = http://localhost:6820
```

---

## 版本適配器

### 適配器架構

**檔案**: `slurmweb/slurmrestd/adapters/`

slurmrestd API 在不同版本間可能有結構差異，適配器負責轉換回應格式：

```python
# adapters/__init__.py

_ADAPTERS = {
    "0.0.41": AdapterV0_0_41,
    "0.0.42": AdapterV0_0_42,
    "0.0.43": AdapterV0_0_43,
    "0.0.44": AdapterV0_0_44,
}

def build_adaptation_chain(api_version: str, supported_versions: list) -> list:
    """建立適配鏈

    例如：API 版本 0.0.43，支援版本 [0.0.41, 0.0.42, 0.0.43]
    適配鏈：[AdapterV0_0_43, AdapterV0_0_42, AdapterV0_0_41]
    """
    chain = []
    for version in reversed(supported_versions):
        if version <= api_version:
            chain.append(_ADAPTERS[version]())
    return chain
```

### 基礎適配器

**檔案**: `slurmweb/slurmrestd/adapters/base.py`

```python
class BaseAdapter:
    """適配器基礎類別"""

    def adapt(self, endpoint: str, data: Any) -> Any:
        """根據端點類型進行適配"""
        method_name = f"adapt_{endpoint.replace('/', '_')}"
        method = getattr(self, method_name, None)
        if method:
            return method(data)
        return data

    def adapt_slurm_jobs(self, data: dict) -> dict:
        """適配 jobs 回應"""
        return data

    def adapt_slurmdb_qos(self, data: dict) -> dict:
        """適配 qos 回應"""
        return data
```

### 版本特定適配器範例

**檔案**: `slurmweb/slurmrestd/adapters/v0_0_41.py`

```python
class AdapterV0_0_41(BaseAdapter):
    """v0.0.41 API 適配器

    API 差異：
    - 某些欄位使用不同的巢狀結構
    - 時間戳記格式不同
    """

    def adapt_slurm_jobs(self, data: dict) -> dict:
        """轉換 jobs 回應格式"""
        for job in data.get("jobs", []):
            # 轉換時間格式
            if "time" in job:
                job["time"] = self._convert_time_format(job["time"])
        return data
```

---

## 快取機制

### CachingService 類別

**檔案**: `slurmweb/cache.py`

```python
class CachingService:
    """Redis 快取服務"""

    def __init__(self, host: str, port: int, password: str = None):
        self.redis = redis.Redis(
            host=host,
            port=port,
            password=password,
            decode_responses=True
        )

    def get(self, key: CacheKey) -> Any:
        """取得快取值"""
        data = self.redis.get(str(key))
        if data:
            return json.loads(data)
        return None

    def put(self, key: CacheKey, value: Any, ttl: int):
        """設定快取值"""
        self.redis.setex(
            str(key),
            ttl,
            json.dumps(value)
        )

    def count_hit(self, key: CacheKey):
        """記錄快取命中"""
        self.redis.hincrby("cache:hits", str(key), 1)

    def count_miss(self, key: CacheKey):
        """記錄快取未命中"""
        self.redis.hincrby("cache:misses", str(key), 1)

    def metrics(self) -> tuple:
        """取得快取指標"""
        hits = self.redis.hgetall("cache:hits")
        misses = self.redis.hgetall("cache:misses")
        return (hits, misses, sum(hits.values()), sum(misses.values()))

    def reset(self):
        """重設所有快取"""
        self.redis.flushdb()
```

### 快取 TTL 配置

```ini
# agent.ini
[cache]
enabled = yes
host = localhost
port = 6379

# 各資料類型的 TTL（秒）
jobs = 10
nodes = 30
partitions = 60
qos = 60
reservations = 30
accounts = 120
associations = 120
```

---

## 完整資料流程

### 1. 請求流程

```
Frontend                Gateway                Agent               slurmrestd
   │                       │                     │                      │
   │  GET /api/agents/     │                     │                      │
   │  cluster1/jobs        │                     │                      │
   │──────────────────────>│                     │                      │
   │                       │  GET /v6/jobs       │                      │
   │                       │  (Bearer JWT)       │                      │
   │                       │────────────────────>│                      │
   │                       │                     │                      │
   │                       │                     │  Check Redis Cache   │
   │                       │                     │─────────┐            │
   │                       │                     │<────────┘            │
   │                       │                     │                      │
   │                       │                     │  Cache Miss:         │
   │                       │                     │  GET /slurm/v0.0.43/ │
   │                       │                     │  jobs                │
   │                       │                     │  (X-SLURM-USER-*)    │
   │                       │                     │─────────────────────>│
   │                       │                     │                      │
   │                       │                     │<─────────────────────│
   │                       │                     │  { "jobs": [...] }   │
   │                       │                     │                      │
   │                       │                     │  Apply Adapters      │
   │                       │                     │  Apply Filters       │
   │                       │                     │  Store in Redis      │
   │                       │                     │─────────┐            │
   │                       │                     │<────────┘            │
   │                       │                     │                      │
   │                       │<────────────────────│                      │
   │                       │  [filtered jobs]    │                      │
   │                       │                     │                      │
   │<──────────────────────│                     │                      │
   │  [filtered jobs]      │                     │                      │
```

### 2. 初始化流程

當 Agent 啟動時：

```python
# slurmweb/apps/agent.py

class SlurmwebAppAgent(SlurmwebWebApp, RFLTokenizedRBACWebApp):
    def __init__(self, seed):
        # 1. 初始化 Flask 應用
        SlurmwebWebApp.__init__(self, seed)

        # 2. 初始化快取服務（如果啟用）
        if self.settings.cache.enabled:
            self.cache = CachingService(
                host=self.settings.cache.host,
                port=self.settings.cache.port,
                password=self.settings.cache.password,
            )

        # 3. 初始化 slurmrestd 客戶端
        self.slurmrestd = SlurmrestdFilteredCached(
            self.settings.slurmrestd.uri,           # 連線 URI
            SlurmrestdAuthentifier(                  # 認證器
                self.settings.slurmrestd.auth,
                self.settings.slurmrestd.jwt_mode,
                self.settings.slurmrestd.jwt_user,
                self.settings.slurmrestd.jwt_key,
                self.settings.slurmrestd.jwt_lifespan,
                self.settings.slurmrestd.jwt_token,
            ),
            self.settings.slurmrestd.versions,      # 支援的 API 版本
            self.settings.filters,                   # 欄位過濾設定
            self.settings.cache,                     # 快取 TTL 設定
            self.cache,                              # 快取服務實例
        )
```

### 3. API 端點呼叫

**檔案**: `slurmweb/views/agent.py`

```python
# 通用錯誤處理裝飾器
def handle_slurmrestd_errors(func):
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except SlurmrestdNotFoundError as err:
            abort(404, f"URL not found on slurmrestd: {err}")
        except SlurmrestConnectionError as err:
            abort(500, f"Unable to connect to slurmrestd: {err}")
        except SlurmrestdAuthenticationError as err:
            abort(401, f"Authentication error: {err}")
        # ... 其他錯誤處理
    return wrapper

# 通用 slurmrestd 呼叫函式
@handle_slurmrestd_errors
def slurmrest(method: str, *args):
    return getattr(current_app.slurmrestd, method)(*args)

# 工作列表端點
@rbac_action("view-jobs")
def jobs():
    node = request.args.get("node")
    if node:
        return jsonify(slurmrest("jobs_by_node", node))
    else:
        return jsonify(slurmrest("jobs"))

# 單一工作端點
@rbac_action("view-jobs")
def job(job: int):
    return jsonify(slurmrest("job", job))

# 節點列表端點
@rbac_action("view-nodes")
def nodes():
    return jsonify(slurmrest("nodes"))
```

---

## API 端點對照

### 完整端點對照表

以下為從 Frontend 到 slurmrestd 的完整請求路徑對照：

| Frontend 請求 | Gateway 端點 | Agent 端點 | slurmrestd 端點 |
|---------------|--------------|------------|-----------------|
| `GET /api/agents/{cluster}/jobs` | `/api/agents/<cluster>/jobs` | `/v6/jobs` | `/slurm/v0.0.4x/jobs` |
| `GET /api/agents/{cluster}/job/123` | `/api/agents/<cluster>/job/<job>` | `/v6/job/<job>` | `/slurm/v0.0.4x/job/<id>` |
| `GET /api/agents/{cluster}/nodes` | `/api/agents/<cluster>/nodes` | `/v6/nodes` | `/slurm/v0.0.4x/nodes` |
| `GET /api/agents/{cluster}/node/n01` | `/api/agents/<cluster>/node/<name>` | `/v6/node/<name>` | `/slurm/v0.0.4x/node/<name>` |
| `GET /api/agents/{cluster}/partitions` | `/api/agents/<cluster>/partitions` | `/v6/partitions` | `/slurm/v0.0.4x/partitions` |
| `GET /api/agents/{cluster}/qos` | `/api/agents/<cluster>/qos` | `/v6/qos` | `/slurmdb/v0.0.4x/qos` |
| `GET /api/agents/{cluster}/reservations` | `/api/agents/<cluster>/reservations` | `/v6/reservations` | `/slurm/v0.0.4x/reservations` |
| `GET /api/agents/{cluster}/accounts` | `/api/agents/<cluster>/accounts` | `/v6/accounts` | `/slurmdb/v0.0.4x/accounts` |
| `GET /api/agents/{cluster}/associations` | `/api/agents/<cluster>/associations` | `/v6/associations` | `/slurmdb/v0.0.4x/associations` |

### Gateway 專屬端點（不代理）

| 端點 | 方法 | 說明 |
|------|------|------|
| `/api/version` | GET | Gateway 版本資訊 |
| `/api/login` | POST | 使用者登入（LDAP 認證） |
| `/api/anonymous` | GET | 匿名存取（認證關閉時） |
| `/api/clusters` | GET | 取得可用叢集列表與權限 |
| `/api/users` | GET | 取得 LDAP 使用者列表 |
| `/api/messages/login` | GET | 登入頁面訊息 |

### Agent 專屬端點

| 端點 | 方法 | RBAC Action | 說明 |
|------|------|-------------|------|
| `/version` | GET | - | Agent 版本資訊 |
| `/info` | GET | - | Agent 狀態資訊 |
| `/v6/permissions` | GET | - | 使用者權限 |
| `/v6/ping` | GET | - | slurmrestd 連線測試 |
| `/v6/stats` | GET | view-stats | 統計摘要 |
| `/v6/cache/stats` | GET | cache-view | 快取統計 |
| `/v6/cache/reset` | POST | cache-reset | 重設快取 |
| `/v6/metrics/<metric>` | GET | 動態 | Prometheus 指標查詢 |
| `/metrics` | GET | - | Prometheus 端點 |

---

## 錯誤處理

### 例外類別

**檔案**: `slurmweb/slurmrestd/errors.py`

```python
class SlurmrestConnectionError(Exception):
    """無法連接 slurmrestd"""
    pass

class SlurmrestdNotFoundError(Exception):
    """資源不存在 (HTTP 404)"""
    pass

class SlurmrestdInvalidResponseError(Exception):
    """回應格式無效"""
    pass

class SlurmrestdAuthenticationError(Exception):
    """認證失敗 (HTTP 401)"""
    pass

class SlurmrestdInternalError(Exception):
    """slurmrestd 內部錯誤"""
    def __init__(self, description, message, error, source):
        self.description = description
        self.message = message
        self.error = error
        self.source = source
```

### HTTP 回應處理

```python
# slurmweb/slurmrestd/__init__.py

def request(self, query: str) -> dict:
    response = self._execute_request(query)

    match response.status_code:
        case 200:
            return response.json()
        case 401:
            raise SlurmrestdAuthenticationError(response.text)
        case 404:
            raise SlurmrestdNotFoundError(query)
        case _:
            # 嘗試解析 slurmrestd 的錯誤格式
            try:
                error_data = response.json()
                raise SlurmrestdInternalError(
                    description=error_data.get("description"),
                    message=error_data.get("message"),
                    error=error_data.get("error"),
                    source=error_data.get("source"),
                )
            except json.JSONDecodeError:
                raise SlurmrestdInvalidResponseError(response.text)
```

---

## 配置範例

### Agent 配置 (agent.ini)

```ini
[service]
cluster = mycluster
interface = 0.0.0.0
port = 5012

[slurmrestd]
# 連線方式（二選一）
uri = unix:///run/slurmrestd/slurmrestd.socket
# uri = http://localhost:6820

# 認證設定
auth = jwt
jwt_mode = auto
jwt_user = slurm
jwt_key = /var/lib/slurm-web/slurmrestd.key
jwt_lifespan = 3600

# 支援的 API 版本
versions =
  0.0.41
  0.0.42
  0.0.43
  0.0.44

[cache]
enabled = yes
host = localhost
port = 6379
jobs = 10
nodes = 30
partitions = 60
qos = 60
reservations = 30
accounts = 120
associations = 120

[jwt]
key = /var/lib/slurm-web/jwt.key
algorithm = HS256
audience = slurm-web
```

### slurmrestd 配置

```bash
# /etc/slurm/slurmrestd.conf
include /etc/slurm/slurm.conf
AuthType=auth/jwt
```

### systemd 服務

```ini
# /etc/systemd/system/slurmrestd.service
[Unit]
Description=Slurm REST API daemon
After=network.target munge.service

[Service]
Type=simple
User=slurm
ExecStart=/usr/sbin/slurmrestd unix:/run/slurmrestd/slurmrestd.socket
RuntimeDirectory=slurmrestd

[Install]
WantedBy=multi-user.target
```

---

## 最佳實踐

### 1. 連線方式選擇

| 方式 | 優點 | 缺點 | 適用場景 |
|------|------|------|----------|
| Unix Socket | 高效能、安全 | 必須在同一主機 | Agent 與 slurmrestd 同主機 |
| HTTP/TCP | 支援遠端連線 | 需額外安全設定 | 分散式部署 |

**建議**: 優先使用 Unix Socket，除非有跨主機需求。

### 2. 認證設定

```ini
# 推薦配置
[slurmrestd]
auth = jwt
jwt_mode = auto
jwt_lifespan = 3600  # 1 小時
```

**避免**:
- 不要使用 `local` 認證（已棄用）
- 不要將 JWT Token 存放在版本控制中

### 3. 快取策略

| 資料類型 | 建議 TTL | 原因 |
|----------|----------|------|
| jobs | 5-15 秒 | 狀態變化頻繁 |
| nodes | 15-60 秒 | 相對穩定 |
| partitions | 60-300 秒 | 很少變化 |
| qos | 60-300 秒 | 很少變化 |
| accounts | 300-600 秒 | 幾乎不變 |

### 4. 版本相容性

```ini
# 支援多個版本以確保相容性
[slurmrestd]
versions =
  0.0.41
  0.0.42
  0.0.43
  0.0.44
```

**注意**: 適配器按版本倒序執行，確保最新版本的適配先套用。

### 5. 錯誤處理

```python
# 建議的錯誤處理模式
try:
    result = slurmrestd.jobs()
except SlurmrestConnectionError:
    # 連線失敗 - 可能需要重試
    logger.error("無法連接 slurmrestd")
except SlurmrestdAuthenticationError:
    # 認證失敗 - 檢查 JWT 設定
    logger.error("slurmrestd 認證失敗")
except SlurmrestdInternalError as err:
    # slurmrestd 內部錯誤 - 記錄詳細資訊
    logger.error(f"slurmrestd 錯誤: {err.description}")
```

---

## 常見問題 (FAQ)

### Q1: 為什麼選擇 slurmrestd 而不是直接呼叫 Slurm 命令？

**A**:
- **效能**: REST API 比 fork/exec 更高效
- **安全**: 可透過 JWT 控制存取權限
- **標準化**: JSON 格式易於處理
- **維護性**: Slurm 官方維護，穩定可靠

### Q2: 快取會造成資料不一致嗎？

**A**: 可能會有短暫的延遲，但這是效能與即時性的權衡。建議：
- 對於顯示用途，10-30 秒的延遲通常可接受
- 對於需要即時資料的操作，可以呼叫 cache reset API

### Q3: 如何診斷連線問題？

**A**: 使用內建診斷工具：

```bash
# 測試 slurmrestd 連線
slurm-web-connect

# 測試 JWT Token 產生
slurm-web-genjwt

# 顯示目前配置
slurm-web-showconf agent
```

### Q4: 升級 Slurm 後 API 不相容怎麼辦？

**A**:
1. 確認 slurmrestd API 版本（透過 `/ping` 端點）
2. 檢查是否有對應的適配器
3. 如果沒有，可能需要新增適配器或升級 Slurm-web

### Q5: 如何監控 slurmrestd 連線狀態？

**A**:
- 使用 `/v6/ping` 端點檢查連線
- 監控 `/v6/cache/stats` 查看快取命中率
- 查看 Agent 日誌中的錯誤訊息

### Q6: Unix Socket 權限問題如何解決？

**A**: 確保：
1. slurmrestd 服務使用正確的使用者執行
2. socket 檔案權限允許 Agent 使用者讀取
3. RuntimeDirectory 設定正確

```bash
# 檢查 socket 權限
ls -la /run/slurmrestd/slurmrestd.socket

# 可能需要調整群組權限
chmod 660 /run/slurmrestd/slurmrestd.socket
chgrp slurm-web /run/slurmrestd/slurmrestd.socket
```

---

## 擴充開發指南

### 新增 API 端點

1. **在 slurmrestd 確認端點存在**
2. **新增方法到 SlurmrestdFiltered**:

```python
# slurmweb/slurmrestd/__init__.py

class SlurmrestdFiltered(SlurmrestdAdapter):
    def my_new_endpoint(self, param: str) -> dict:
        data = self.request(f"{self.api_path}/my-endpoint/{param}")
        return self._apply_filters(data, "my-endpoint")
```

3. **新增快取支援（如需要）**:

```python
# slurmweb/slurmrestd/__init__.py

class SlurmrestdFilteredCached(SlurmrestdFiltered):
    def my_new_endpoint(self, param: str) -> dict:
        cache_key = CacheKey(f"my-endpoint:{param}")
        cached = self.cache.get(cache_key)
        if cached:
            return cached
        result = super().my_new_endpoint(param)
        self.cache.put(cache_key, result, ttl=60)
        return result
```

4. **新增 Agent 視圖**:

```python
# slurmweb/views/agent.py

@rbac_action("view-my-endpoint")
def my_endpoint(param: str):
    return jsonify(slurmrest("my_new_endpoint", param))
```

### 新增版本適配器

1. **建立適配器檔案**:

```python
# slurmweb/slurmrestd/adapters/v0_0_45.py

from .base import BaseAdapter

class AdapterV0_0_45(BaseAdapter):
    def adapt_slurm_jobs(self, data: dict) -> dict:
        # 處理 0.0.45 版本的差異
        return data
```

2. **註冊適配器**:

```python
# slurmweb/slurmrestd/adapters/__init__.py

from .v0_0_45 import AdapterV0_0_45

_ADAPTERS = {
    ...
    "0.0.45": AdapterV0_0_45,
}
```

---

## 相關資源

- [Slurm REST API 官方文件](https://slurm.schedmd.com/rest_api.html)
- [slurmrestd 配置指南](https://slurm.schedmd.com/slurmrestd.html)
- [JWT 認證設定](https://slurm.schedmd.com/jwt.html)

---

*此文件由 Slurm-web 專案深入分析產生*
