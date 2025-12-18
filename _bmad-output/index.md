# Slurm-web 專案文件

> **版本**: 6.0.0
> **掃描日期**: 2025-12-18
> **掃描模式**: Exhaustive Scan
> **文件語言**: 繁體中文（台灣）

## 專案概述

Slurm-web 是一個用於管理 HPC（高效能運算）叢集的網頁介面，提供對 [Slurm](https://slurm.schedmd.com/) 工作排程系統的完整視覺化管理能力。

### 核心功能

- **叢集管理**：多叢集支援與即時狀態監控
- **工作管理**：檢視、過濾和監控 HPC 工作
- **資源視覺化**：節點狀態、CPU/GPU 使用率的圖形化呈現
- **使用者管理**：LDAP 整合認證與 RBAC 權限控制
- **效能指標**：與 Prometheus 整合的歷史資料視覺化
- **機房視覺化**：透過 RacksDB 整合提供 3D 機架圖

### 架構類型

**Multi-part Repository** - 前後端分離架構

---

## 目錄

1. [架構概覽](./architecture.md)
2. [前端文件](./frontend.md)
3. [後端文件](./backend.md)
4. [API 參考](./api-reference.md)
5. [開發指南](./development.md)
6. [部署指南](./deployment.md)

---

## 技術堆疊摘要

### Frontend (`/frontend/`)

| 類別 | 技術 |
|------|------|
| Framework | Vue 3 (Composition API) |
| Language | TypeScript |
| Build Tool | Vite |
| Styling | Tailwind CSS 4 |
| State Management | Pinia |
| Routing | Vue Router |
| HTTP Client | Axios |
| Charts | Chart.js + Luxon |
| UI Components | Headless UI + Heroicons |
| Testing | Vitest |

### Backend (`/slurmweb/`)

| 類別 | 技術 |
|------|------|
| Framework | Flask |
| Language | Python 3.6+ |
| Async HTTP | aiohttp |
| Authentication | LDAP + JWT |
| Caching | Redis |
| RBAC | RFL.authentication |
| Metrics | Prometheus |
| External APIs | Slurm slurmrestd, RacksDB |

### Infrastructure (`/lib/`)

| 類別 | 技術 |
|------|------|
| Service Management | systemd |
| Web Server | WSGI (Gunicorn/uWSGI) |
| Package Formats | DEB, RPM |

---

## 專案結構

```
Slurm-web/
├── frontend/                 # Vue 3 前端應用
│   ├── src/
│   │   ├── components/       # Vue 組件
│   │   ├── views/            # 頁面視圖
│   │   ├── stores/           # Pinia 狀態管理
│   │   ├── composables/      # Vue Composables
│   │   ├── plugins/          # Vue 插件
│   │   └── router/           # 路由配置
│   └── tests/                # 前端測試
├── slurmweb/                 # Python 後端
│   ├── apps/                 # Flask 應用（Gateway, Agent）
│   ├── views/                # API 視圖函數
│   ├── slurmrestd/           # Slurm REST API 客戶端
│   ├── metrics/              # Prometheus 指標收集
│   ├── exec/                 # CLI 入口點
│   └── tests/                # 後端測試
├── conf/                     # 配置定義檔
│   └── vendor/               # 預設配置 YAML
├── lib/                      # 系統整合
│   ├── systemd/              # systemd 服務檔案
│   ├── wsgi/                 # WSGI 配置
│   └── exec/                 # 執行腳本
├── docs/                     # 使用者文件（Sphinx）
├── dev/                      # 開發環境配置
└── tests/                    # 整合測試資產
```

---

## 快速連結

### 開發
- [開發環境設置](./development.md#setup)
- [測試指南](./development.md#testing)
- [貢獻指南](/CONTRIBUTING.md)

### 部署
- [部署選項](./deployment.md#options)
- [配置說明](./deployment.md#configuration)
- [系統需求](./deployment.md#requirements)

### API
- [Gateway API](./api-reference.md#gateway)
- [Agent API](./api-reference.md#agent)
- [認證](./api-reference.md#authentication)

---

## 相關資源

- **官方文件**: https://slurm-web.rtfd.io
- **GitHub Repository**: https://github.com/rackslab/Slurm-web
- **Slurm 官網**: https://slurm.schedmd.com/
- **RacksDB**: https://github.com/rackslab/RacksDB

---

*此文件由 BMAD Document Project Workflow 自動生成*
