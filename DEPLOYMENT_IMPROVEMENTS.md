# 部署架構改進說明

## 變更摘要

本次更新重新組織了 Slurm-web Kubernetes 部署的檔案結構，並新增 Makefile 自動化工具，提升部署效率與維護性。

## 檔案結構調整

### 變更前
```
專案根目錄/
├── gateway.Dockerfile
├── agent.Dockerfile
├── .dockerignore
└── deployment/
    ├── README.md
    └── helm/...
```

### 變更後
```
專案根目錄/
└── deployment/
    ├── README.md           (已更新)
    ├── Makefile            (新增)
    ├── docker/             (新增)
    │   ├── gateway.Dockerfile
    │   ├── agent.Dockerfile
    │   └── .dockerignore
    └── helm/...
```

## 主要改進

### 1. 統一部署目錄結構

**目的**: 將所有部署相關檔案集中在 `deployment/` 目錄下

**優點**:
- 更清晰的專案結構
- 便於部署工具管理
- 符合常見專案慣例

### 2. 新增 Makefile 自動化工具

**檔案**: `deployment/Makefile`

**功能分類**:

#### 建置與推送
- `make build-all` - 建置所有映像檔
- `make push-all` - 推送所有映像檔
- `make build-and-push` - 建置並推送

#### 部署與管理
- `make deploy` - 部署到 Kubernetes
- `make upgrade` - 更新現有部署
- `make rollback` - 回滾到上一版本
- `make uninstall` - 移除部署

#### 驗證與除錯
- `make verify` - 完整驗證流程
- `make status` - 查看部署狀態
- `make logs-gateway` / `make logs-agent` - 查看日誌
- `make test-agent` / `make test-gateway` - 測試元件
- `make shell-gateway` / `make shell-agent` - 進入 Pod Shell

#### 完整工作流程
- `make full-deploy` - 建置→推送→部署→驗證（一鍵完成）
- `make redeploy` - 重新部署（建置→推送→更新→驗證）

### 3. 更新部署文件

**檔案**: `deployment/README.md`

**更新內容**:
- 新增 Makefile 使用說明
- 提供手動與自動化兩種部署方式
- 新增 "Makefile 常用命令" 章節
- 更新快速開始流程

## 使用範例

### 情境 1: 首次完整部署

```bash
cd deployment

# 一鍵完成所有步驟
make full-deploy \
  REGISTRY=my-registry.example.com \
  TAG=v1.0.0 \
  NAMESPACE=slurm-web
```

這個命令會自動執行:
1. 建置 Gateway 和 Agent 映像檔
2. 推送到 Container Registry
3. 使用 Helm 部署到 Kubernetes
4. 執行完整驗證流程

### 情境 2: 更新程式碼後重新部署

```bash
cd deployment

# 重新建置、推送、更新
make redeploy \
  REGISTRY=my-registry.example.com \
  TAG=v1.0.1 \
  NAMESPACE=slurm-web
```

### 情境 3: 僅更新 Helm 配置

```bash
cd deployment

# 編輯 values.yaml 後
make upgrade NAMESPACE=slurm-web
```

### 情境 4: 除錯與日誌查看

```bash
cd deployment

# 查看即時日誌
make logs-gateway NAMESPACE=slurm-web

# 進入 Pod 進行除錯
make shell-agent NAMESPACE=slurm-web

# 本地 Port Forward 測試
make port-forward-gateway NAMESPACE=slurm-web
# 瀏覽器開啟 http://localhost:5011
```

## 可配置參數

所有 Makefile 命令都支援以下參數覆寫:

| 參數 | 預設值 | 說明 |
|------|--------|------|
| `REGISTRY` | `your-registry.example.com` | Container Registry URL |
| `TAG` | `mvp` | 映像檔標籤 |
| `NAMESPACE` | `slurm-web` | Kubernetes Namespace |
| `VALUES_FILE` | `./helm/slurm-web/values.yaml` | Helm values 檔案 |
| `HELM_RELEASE` | `slurm-web` | Helm Release 名稱 |

範例:
```bash
make deploy \
  REGISTRY=harbor.example.com/slurm \
  TAG=production-v2.1.0 \
  NAMESPACE=slurm-prod \
  VALUES_FILE=./helm/slurm-web/values-prod.yaml
```

## 相容性

- 所有原有的手動部署步驟仍然可用
- Makefile 純為輔助工具，不影響現有工作流程
- 可依需求選擇 Makefile 或手動命令

## 後續改進建議

1. **CI/CD 整合**: 將 Makefile 命令整合到 GitLab CI / GitHub Actions
2. **多環境管理**: 建立 `values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`
3. **自動化測試**: 在 `make verify` 中加入更完整的 E2E 測試
4. **Helm Chart 發布**: 將 Chart 發布到 Helm Repository

## 檔案清單

### 新增檔案
- `deployment/Makefile` (9.7 KB)
- `deployment/docker/gateway.Dockerfile`
- `deployment/docker/agent.Dockerfile`
- `deployment/docker/.dockerignore`

### 更新檔案
- `deployment/README.md` (新增 Makefile 使用說明)

### 移除檔案
- `gateway.Dockerfile` (移至 `deployment/docker/`)
- `agent.Dockerfile` (移至 `deployment/docker/`)
- `.dockerignore` (移至 `deployment/docker/`)

## 驗證步驟

部署改進後的驗證流程:

```bash
# 1. 檢查檔案結構
ls -R deployment/

# 2. 查看 Makefile 命令
cd deployment
make help

# 3. 驗證 Helm Chart 語法
make helm-lint

# 4. 試運行（不實際部署）
make helm-dry-run NAMESPACE=slurm-web

# 5. 實際部署（需要 K8s 叢集）
make full-deploy \
  REGISTRY=your-registry.com \
  TAG=test \
  NAMESPACE=slurm-test
```

---

**改進完成日期**: 2026-01-28
**影響範圍**: 部署流程與檔案結構
**向下相容**: 是（所有手動步驟仍可用）
