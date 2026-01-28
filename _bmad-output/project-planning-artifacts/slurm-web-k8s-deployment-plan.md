# Slurm-web Kubernetes 部署方案 (MVP 簡化版)

## 一、目標與架構設計

### 1.1 部署目標
- **MVP 模式**: 以最快速度建立可運行的環境，不進行過度設計 (Over-design)。
- **單一叢集**: 僅部署一個 Gateway、一個 Agent 服務。
- **Helm 管理**: 使用 Helm Chart 進行統一的版本控制與部署。
- **開發導向**: 適用於開發驗證、POC 或小型內部環境。

### 1.2 簡化架構
| 組件 | 說明 | 部署方式 |
|------|------|----------|
| **Gateway** | 前端入口與 API 網關 | K8s Deployment |
| **Agent** | 負責與 Slurm 通訊 (僅 1 個) | K8s Deployment |
| **Redis** | 用於快取，不需 HA 與持久化 | K8s Deployment (單機版) |
| **Slurm API** | 由 Slurm Operator 管理的 restapi | 外部 Service (同 K8s 叢集) |

---

## 二、Dockerfile 設計 (極簡版)

### 2.1 Gateway Dockerfile
```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y gcc libldap2-dev libsasl2-dev && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml README.md ./
COPY slurmweb/ ./slurmweb/
RUN pip install --no-cache-dir --user .[gateway]

FROM node:20-slim AS frontend-builder
WORKDIR /frontend
COPY frontend/package*.json ./
RUN npm ci --only=production
COPY frontend/ ./
RUN npm run build

FROM python:3.11-slim
RUN apt-get update && apt-get install -y libldap-2.5-0 libsasl2-2 ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH
COPY --from=frontend-builder /frontend/dist /usr/share/slurm-web/frontend
COPY conf/ /usr/share/slurm-web/conf/
USER 1000
EXPOSE 5011
ENTRYPOINT ["slurm-web-gateway"]
CMD ["--conf", "/etc/slurm-web/gateway.ini"]
```

### 2.2 Agent Dockerfile
```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y gcc && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml README.md ./
COPY slurmweb/ ./slurmweb/
RUN pip install --no-cache-dir --user .[agent]

FROM python:3.11-slim
RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH
COPY conf/ /usr/share/slurm-web/conf/
USER 1000
EXPOSE 5012
ENTRYPOINT ["slurm-web-agent"]
CMD ["--conf", "/etc/slurm-web/agent.ini"]
```

---

## 三、Helm Chart 設計

### 3.1 極簡 values.yaml
```yaml
# values.yaml
gateway:
  image: "my-reg/gateway:mvp"
  ingress:
    enabled: true
    host: "slurm-web.local"
  auth:
    method: "ldap" # 可改為 "none" 進行快速測試

agent:
  image: "my-reg/agent:mvp"
  slurmrestd:
    # 填寫 Slurm Operator 建立的 restapi service 名稱
    uri: "http://slurm-restapi.slurm-namespace.svc.cluster.local:6820"

redis:
  enabled: true
  image: "redis:alpine"

secrets:
  jwtKey: "at-least-32-character-secret-key"
```

--- 

## 四、部署與執行流程 (手動模式)

### 4.1 手動建置並推送映像檔
```bash
# 建置 Gateway
docker build -f gateway.Dockerfile -t my-reg/gateway:mvp .
# 建置 Agent
docker build -f agent.Dockerfile -t my-reg/agent:mvp .

# 推送
docker push my-reg/gateway:mvp
docker push my-reg/agent:mvp
```

### 4.2 使用 Helm 部署
```bash
# 建立命名空間
kubectl create namespace slurm-web

# 安裝 Chart
helm upgrade --install slurm-web ./deployment/helm/slurm-web \
  -n slurm-web \
  -f values.yaml
```

### 4.3 驗證連線
```bash
# 檢查 Pod
kubectl get pods -n slurm-web

# 測試 Agent 連接 Slurm restapi 是否正常
kubectl exec -it -n slurm-web deploy/slurm-web-agent -- curl http://localhost:5012/info
```

--- 

## 五、後續調整建議 (若有需要)
1. **持久化**: 若快取資料很重要，再為 Redis 加上 PVC。
2. **認證**: 若暫時沒有 LDAP，可在 `gateway.ini` 中暫時使用簡單認證或關閉。
3. **Ingress**: 確保 K8s 叢集內有 Ingress Controller (如 Nginx Ingress)。