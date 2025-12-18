# Slurm-web 開發指南

## 開發環境設置 {#setup}

### 系統需求

- **Python**: 3.6+
- **Node.js**: 18+
- **npm**: 8+
- **Redis**: 6+ (可選，用於快取)

### 後端設置

#### 1. 建立 Python 虛擬環境

```bash
python -m venv venv
source venv/bin/activate  # Linux/macOS
# 或
venv\Scripts\activate     # Windows
```

#### 2. 安裝後端依賴

```bash
pip install -e ".[dev]"
```

#### 3. 建立配置檔案

```bash
# 建立配置目錄
mkdir -p /etc/slurm-web

# 複製範例配置
cp dev/gateway.ini /etc/slurm-web/gateway.ini
cp dev/agent.ini /etc/slurm-web/agent.ini
```

#### 4. 產生 JWT 金鑰

```bash
# 產生隨機金鑰
openssl rand -base64 32 > /var/lib/slurm-web/jwt.key
```

### 前端設置

#### 1. 安裝前端依賴

```bash
cd frontend
npm install
```

#### 2. 配置開發環境

建立 `.env.local`（可選）：

```
VITE_BASE_PATH=/
```

---

## 本地開發

### 使用開發環境

專案提供 `dev/` 目錄包含完整的開發環境配置。

#### 啟動後端

```bash
# 啟動 Gateway（Port 5011）
slurm-web-gateway --debug --conf dev/gateway.ini

# 啟動 Agent（Port 5012）
slurm-web-agent --debug --conf dev/agent.ini
```

#### 啟動前端開發伺服器

```bash
cd frontend
npm run dev
```

前端開發伺服器預設在 http://localhost:5173 啟動。

### Mock 模式

若無法連接真實的 Slurm 叢集，可使用測試資產模擬：

```bash
# 參考 tests/assets/ 目錄的 JSON 檔案
```

---

## 測試 {#testing}

### 後端測試

#### 執行所有測試

```bash
pytest slurmweb/tests/
```

#### 執行特定測試

```bash
# 測試特定模組
pytest slurmweb/tests/apps/test_gateway.py

# 測試特定函數
pytest slurmweb/tests/apps/test_gateway.py::test_login
```

#### 測試覆蓋率

```bash
pytest --cov=slurmweb --cov-report=html slurmweb/tests/
```

### 前端測試

#### 執行單元測試

```bash
cd frontend
npm run test:unit
```

#### 執行帶覆蓋率

```bash
npm run test:coverage
```

#### 監視模式

```bash
npm run test:watch
```

---

## 程式碼品質

### 後端

#### Linting

```bash
# 使用 flake8
flake8 slurmweb/

# 使用 pylint
pylint slurmweb/
```

#### 格式化

```bash
# 使用 black
black slurmweb/

# 使用 isort
isort slurmweb/
```

#### 型別檢查

```bash
mypy slurmweb/
```

### 前端

#### Linting

```bash
cd frontend
npm run lint
```

#### 格式化

```bash
npm run format
```

#### 型別檢查

```bash
npm run type-check
```

---

## 專案結構

### 後端關鍵檔案

| 檔案 | 說明 |
|------|------|
| `pyproject.toml` | Python 專案配置 |
| `slurmweb/apps/__init__.py` | 基礎應用類別 |
| `slurmweb/apps/gateway.py` | Gateway 應用 |
| `slurmweb/apps/agent.py` | Agent 應用 |
| `slurmweb/views/*.py` | API 視圖函數 |
| `slurmweb/slurmrestd/__init__.py` | Slurm REST 客戶端 |
| `conf/vendor/*.yml` | 配置定義 |

### 前端關鍵檔案

| 檔案 | 說明 |
|------|------|
| `package.json` | NPM 專案配置 |
| `vite.config.ts` | Vite 建置配置 |
| `src/main.ts` | 應用入口 |
| `src/router/index.ts` | 路由配置 |
| `src/stores/*.ts` | Pinia Stores |
| `src/composables/*.ts` | Vue Composables |

---

## 新增功能指南

### 新增後端 API 端點

1. **定義路由**

在 `slurmweb/views/__init__.py` 確認 `SlurmwebAppRoute` 類別。

2. **實作視圖函數**

在 `slurmweb/views/agent.py` 或 `slurmweb/views/gateway.py` 新增：

```python
@rbac_action("your-action")  # 若需要 RBAC
def your_endpoint():
    # 實作邏輯
    return jsonify(result)
```

3. **註冊路由**

在對應的 App 類別（`SlurmwebAppGateway` 或 `SlurmwebAppAgent`）的 `VIEWS` 集合中新增：

```python
VIEWS = {
    # ...
    SlurmwebAppRoute("/v{version}/your-endpoint", views.your_endpoint),
}
```

4. **撰寫測試**

在 `slurmweb/tests/views/` 新增測試。

### 新增前端頁面

1. **建立視圖組件**

```typescript
// src/views/YourView.vue
<script setup lang="ts">
// ...
</script>

<template>
  <!-- ... -->
</template>
```

2. **新增路由**

```typescript
// src/router/index.ts
{
  path: '/your-path',
  name: 'your-view',
  component: YourView
}
```

3. **更新導航**

在 `MainMenu.vue` 或相關組件新增連結。

### 新增 Store

```typescript
// src/stores/yourStore.ts
import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useYourStore = defineStore('your', () => {
  const state = ref(initialValue)

  function action() {
    // ...
  }

  return { state, action }
})
```

---

## 除錯技巧

### 後端除錯

#### 啟用詳細日誌

```bash
slurm-web-gateway --debug --log-flags ALL
```

#### 使用 Flask debugger

配置中啟用 CORS 和 debug 模式：

```ini
[service]
cors = yes
debug = yes
```

### 前端除錯

#### Vue DevTools

安裝 [Vue.js devtools](https://devtools.vuejs.org/) 瀏覽器擴充功能。

#### Console 日誌

應用程式在開發模式會輸出詳細日誌到瀏覽器 console。

---

## 建置與發布

### 後端打包

```bash
python -m build
```

產出：
- `dist/slurm_web-<version>.tar.gz`
- `dist/slurm_web-<version>-py3-none-any.whl`

### 前端建置

```bash
cd frontend
npm run build
```

產出目錄：`frontend/dist/`

### 系統套件

專案支援產生 DEB 和 RPM 套件，詳見 `dev/` 目錄的打包腳本。

---

## 貢獻流程

1. Fork 專案
2. 建立功能分支 (`git checkout -b feature/your-feature`)
3. 提交變更 (`git commit -m 'feat: add your feature'`)
4. 推送分支 (`git push origin feature/your-feature`)
5. 建立 Pull Request

### Commit 訊息格式

遵循 [Conventional Commits](https://www.conventionalcommits.org/)：

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`

---

## 相關資源

- [Flask 文件](https://flask.palletsprojects.com/)
- [Vue 3 文件](https://vuejs.org/)
- [Pinia 文件](https://pinia.vuejs.org/)
- [Vite 文件](https://vitejs.dev/)
- [Slurm REST API](https://slurm.schedmd.com/rest_api.html)

---

*此文件由 BMAD Document Project Workflow 自動生成*
