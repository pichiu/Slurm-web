# Slurm-web 前端文件

## 概述

Slurm-web 前端是一個基於 Vue 3 的單頁應用程式（SPA），使用 Composition API 和 TypeScript 開發。

## 技術堆疊

| 類別 | 技術 | 版本 |
|------|------|------|
| Framework | Vue | ^3.5.13 |
| Language | TypeScript | ~5.6.3 |
| Build Tool | Vite | ^6.0.3 |
| Styling | Tailwind CSS | ^4.0.0 |
| State Management | Pinia | ^2.3.0 |
| Routing | Vue Router | ^4.5.0 |
| HTTP Client | Axios | ^1.7.9 |
| Charts | Chart.js | ^4.4.7 |
| Date Handling | Luxon | ^3.5.0 |
| UI Components | @headlessui/vue | ^1.7.23 |
| Icons | @heroicons/vue | ^2.2.0 |
| Testing | Vitest | ^2.1.8 |

## 專案結構

```
frontend/
├── src/
│   ├── main.ts              # 應用程式入口
│   ├── App.vue              # 根組件
│   ├── style.css            # 全局樣式
│   ├── components/          # 可復用組件
│   │   ├── accounts/        # 帳戶相關組件
│   │   ├── clusters/        # 叢集相關組件
│   │   ├── dashboard/       # 儀表板組件
│   │   ├── filters/         # 過濾器組件
│   │   ├── job/             # 單一工作詳情組件
│   │   ├── jobs/            # 工作列表組件
│   │   ├── login/           # 登入組件
│   │   ├── notifications/   # 通知組件
│   │   ├── qos/             # QoS 組件
│   │   ├── resources/       # 資源視圖組件
│   │   └── settings/        # 設定組件
│   ├── views/               # 頁面視圖
│   │   ├── resources/       # 資源頁面
│   │   ├── settings/        # 設定頁面
│   │   └── tests/           # 測試頁面
│   ├── stores/              # Pinia Stores
│   │   ├── auth.ts          # 認證狀態
│   │   ├── runtime.ts       # 執行時狀態
│   │   └── runtime/         # 子 Store 模組
│   ├── composables/         # Vue Composables
│   │   ├── charts/          # 圖表相關
│   │   ├── DataGetter.ts    # 資料獲取
│   │   ├── DataPoller.ts    # 資料輪詢
│   │   ├── GatewayAPI.ts    # API 封裝
│   │   └── ...
│   ├── plugins/             # Vue 插件
│   │   ├── http.ts          # HTTP 插件
│   │   └── runtimeConfiguration.ts
│   └── router/              # 路由配置
│       └── index.ts
├── tests/                   # 測試
│   ├── components/          # 組件測試
│   ├── composables/         # Composables 測試
│   └── ...
├── package.json
├── vite.config.ts
├── vitest.config.ts
└── tsconfig.json
```

---

## 核心模組

### 1. State Management (Pinia Stores)

#### Auth Store (`/src/stores/auth.ts`)

管理使用者認證狀態。

```typescript
interface AuthStore {
  // State
  token: string | null
  username: string | null
  fullname: string | null
  groups: string[]
  returnUrl: string | null

  // Actions
  login(token: string, username: string, fullname: string, groups: string[]): void
  anonymousLogin(token: string): void
  logout(): void
}
```

**特性**:
- JWT Token 持久化（localStorage）
- 自動重定向到登入前頁面

#### Runtime Store (`/src/stores/runtime.ts`)

管理應用程式執行時狀態。

```typescript
interface RuntimeStore {
  // State
  routePath: string
  beforeSettingsRoute: RouteLocation | undefined
  dashboard: DashboardRuntimeStore
  jobs: JobsRuntimeStore
  resources: ResourcesRuntimeStore
  errors: RuntimeError[]
  notifications: Notification[]
  availableClusters: ClusterDescription[]
  currentCluster: ClusterDescription | undefined

  // Actions
  addCluster(cluster: ClusterDescription): void
  getCluster(name: string): ClusterDescription
  getAllowedClusters(): ClusterDescription[]
  hasPermission(permission: string): boolean
  reportError(message: string): void
  reportInfo(message: string): void
}
```

---

### 2. Composables

#### GatewayAPI (`/src/composables/GatewayAPI.ts`)

封裝所有與 Gateway 的 API 互動。

```typescript
function useGatewayAPI() {
  return {
    // 認證
    login(idents: loginIdents): Promise<GatewayLoginResponse>
    anonymousLogin(): Promise<GatewayAnonymousLoginResponse>

    // 叢集
    clusters(): Promise<ClusterDescription[]>
    ping(cluster: string): Promise<ClusterPingResponse>
    stats(cluster: string): Promise<ClusterStats>

    // 工作
    jobs(cluster: string, node?: string): Promise<ClusterJob[]>
    job(cluster: string, job: number): Promise<ClusterIndividualJob>

    // 節點
    nodes(cluster: string): Promise<ClusterNode[]>
    node(cluster: string, nodeName: string): Promise<ClusterIndividualNode>

    // 其他
    partitions(cluster: string): Promise<ClusterPartition[]>
    qos(cluster: string): Promise<ClusterQos[]>
    reservations(cluster: string): Promise<ClusterReservation[]>
    accounts(cluster: string): Promise<AccountDescription[]>
    associations(cluster: string): Promise<ClusterAssociation[]>

    // 快取
    cache_stats(cluster: string): Promise<CacheStatistics>
    cache_reset(cluster: string): Promise<CacheStatistics>

    // 指標
    metrics_nodes(cluster: string, last: string): Promise<Record<...>>
    metrics_cores(cluster: string, last: string): Promise<Record<...>>
    metrics_gpus(cluster: string, last: string): Promise<Record<...>>
    metrics_jobs(cluster: string, last: string): Promise<Record<...>>

    // RacksDB
    infrastructureImagePng(cluster: string, infrastructure: string, width: number, height: number): Promise<[RacksDBAPIImage, RacksDBInfrastructureCoordinates]>
  }
}
```

#### DataPoller (`/src/composables/DataPoller.ts`)

提供自動輪詢資料的功能。

#### Nodeset (`/src/composables/Nodeset.ts`)

解析和處理 Slurm nodeset 格式（如 `node[001-100]`）。

---

### 3. Router

#### 路由結構

```typescript
const routes = [
  { path: '/', redirect: { name: 'clusters' } },
  { path: '/login', name: 'login', component: LoginView },
  { path: '/anonymous', name: 'anonymous', component: AnonymousView },
  { path: '/clusters', name: 'clusters', component: ClustersView },
  { path: '/signout', name: 'signout', component: SignoutView },
  { path: '/settings', component: SettingsLayout, children: [...] },
  { path: '/:cluster', children: [
    { path: 'dashboard', name: 'dashboard', component: DashboardView },
    { path: 'jobs', name: 'jobs', component: JobsView },
    { path: 'job/:id', name: 'job', component: JobView },
    { path: 'resources', name: 'resources', component: ResourcesView },
    { path: 'node/:nodeName', name: 'node', component: NodeView },
    { path: 'qos', name: 'qos', component: QosView },
    { path: 'reservations', name: 'reservations', component: ReservationsView },
    { path: 'accounts', name: 'accounts', component: AccountsView },
    { path: 'accounts/:account', name: 'account', component: AccountView },
    { path: 'users/:user', name: 'user', component: UserView },
  ]},
  { path: '/:pathMatch(.*)*', name: 'not-found', component: NotFoundView },
]
```

#### Navigation Guard

路由守衛處理認證邏輯：
- 未登入時重定向到 `/login`
- 認證關閉時重定向到 `/anonymous`
- 追蹤當前叢集
- 保存設定頁面前的路由

---

### 4. 主要視圖

#### ClustersView
叢集選擇頁面，顯示所有可用叢集及其狀態。

#### DashboardView
叢集儀表板，顯示：
- 資源統計（節點、CPU、記憶體、GPU）
- 工作統計（執行中、總數）
- 歷史圖表（若 metrics 啟用）

#### JobsView
工作列表頁面，功能包含：
- 過濾（使用者、帳戶、QoS、分區、狀態）
- 排序（ID、使用者、狀態、優先級、資源）
- 分頁

#### JobView
單一工作詳情頁面，顯示：
- 工作基本資訊
- 執行步驟
- 資源使用
- 腳本內容

#### ResourcesView
資源視圖，顯示節點狀態和分配情況。

#### NodeView
單一節點詳情頁面。

#### QosView
QoS 配置列表和限制說明。

#### AccountsView / AccountView
帳戶階層樹狀結構和詳情。

---

### 5. 組件庫

#### 通用組件

| 組件 | 說明 |
|------|------|
| `LoadingSpinner.vue` | 載入指示器 |
| `ErrorAlert.vue` | 錯誤訊息顯示 |
| `InfoAlert.vue` | 資訊訊息顯示 |
| `ClusterMainLayout.vue` | 叢集頁面佈局 |
| `MainMenu.vue` | 主導航選單 |
| `ClustersPopOver.vue` | 叢集切換彈出選單 |

#### 工作相關組件

| 組件 | 說明 |
|------|------|
| `JobsFiltersPanel.vue` | 過濾面板 |
| `JobsFiltersBar.vue` | 過濾標籤列 |
| `JobsSorter.vue` | 排序選擇器 |
| `JobResources.vue` | 工作資源顯示 |
| `JobStatusBadge.vue` | 狀態徽章 |
| `JobProgress.vue` | 進度指示器 |

#### 資源相關組件

| 組件 | 說明 |
|------|------|
| `ResourcesCanvas.vue` | 資源圖形化顯示 |
| `ResourcesDiagramGeneric.vue` | 通用圖表組件 |
| `NodeMainState.vue` | 節點主狀態顯示 |
| `NodeAllocationState.vue` | 節點分配狀態 |
| `NodeGPU.vue` | GPU 資訊顯示 |

#### 圖表組件

| 組件 | 說明 |
|------|------|
| `ChartJobsHistogram.vue` | 工作歷史直方圖 |
| `ChartResourcesHistogram.vue` | 資源歷史直方圖 |

---

## TypeScript 型別

### 主要介面

```typescript
// 叢集描述
interface ClusterDescription {
  name: string
  racksdb: boolean
  infrastructure: string
  metrics: boolean
  cache: boolean
  permissions: ClusterPermissions
  versions?: ClusterVersions
  stats?: ClusterStats
  error?: boolean
}

// 工作
interface ClusterJob {
  account: string
  cpus: ClusterOptionalNumber
  gres_detail: string[]
  job_id: number
  job_state: string[]
  node_count: ClusterOptionalNumber
  nodes: string
  partition: string
  priority: ClusterOptionalNumber
  qos: string
  // ...
}

// 節點
interface ClusterNode {
  alloc_cpus: number
  alloc_idle_cpus: number
  cores: number
  cpus: number
  gres: string
  gres_used: string
  name: string
  partitions: string[]
  real_memory: number
  sockets: number
  state: string[]
  reason: string
}

// Optional Number（處理 Slurm 的特殊數值格式）
interface ClusterOptionalNumber {
  infinite: boolean
  number: number
  set: boolean
}
```

---

## 開發

### 本地開發

```bash
cd frontend
npm install
npm run dev      # 開發伺服器 (port 5173)
```

### 建置

```bash
npm run build    # 產出到 dist/
npm run preview  # 預覽建置結果
```

### 測試

```bash
npm run test:unit        # 執行單元測試
npm run test:coverage    # 測試覆蓋率報告
```

### Linting

```bash
npm run lint     # ESLint 檢查
npm run format   # Prettier 格式化
```

---

## 配置

### 環境變數

| 變數 | 說明 | 預設值 |
|------|------|--------|
| `VITE_BASE_PATH` | 應用程式 base path | `/` (dev) `/__SLURMWEB_BASE__` (prod) |

### Runtime Configuration

前端透過 `/config.json` 取得執行時配置：

```json
{
  "API_SERVER": "http://localhost:5011",
  "AUTHENTICATION": true,
  "RACKSDB_ROWS_LABELS": false,
  "RACKSDB_RACKS_LABELS": false,
  "VERSION": "6.0.0"
}
```

---

*此文件由 BMAD Document Project Workflow 自動生成*
