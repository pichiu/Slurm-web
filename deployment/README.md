# Slurm-web Kubernetes 部署指南 (MVP)

本指南提供 Slurm-web 在 Kubernetes 環境的最小可行產品 (MVP) 部署方法。

## 目錄結構

```
deployment/
├── README.md                          # 本檔案
├── Makefile                           # 自動化部署腳本
├── docker/                            # Container 映像檔
│   ├── gateway.Dockerfile
│   ├── agent.Dockerfile
│   └── .dockerignore
└── helm/
    └── slurm-web/
        ├── Chart.yaml                 # Helm Chart 定義
        ├── values.yaml                # 預設配置值
        ├── values-example.yaml        # 配置範例
        └── templates/                 # Kubernetes 資源模板
            ├── _helpers.tpl           # Helm helper functions
            ├── pre-install-job.yaml   # 部署前安全驗證
            ├── gateway-deployment.yaml
            ├── gateway-service.yaml
            ├── gateway-configmap.yaml
            ├── agent-deployment.yaml
            ├── agent-service.yaml
            ├── agent-configmap.yaml
            ├── redis-deployment.yaml
            ├── redis-service.yaml
            ├── secret.yaml
            └── ingress.yaml
```

## 前置需求

1. **Kubernetes 叢集** (v1.23+)
2. **Helm** (v3.8+)
3. **Container Registry** (Docker Hub、Harbor、或其他)
4. **Slurm REST API** 服務（由 Slurm Operator 管理）
5. **Ingress Controller** (例如: nginx-ingress)

## 快速開始

### 使用 Makefile (推薦)

進入 `deployment/` 目錄，使用 Makefile 進行自動化部署：

```bash
cd deployment

# 查看所有可用命令
make help

# 完整部署流程（建置→推送→部署→驗證）
make full-deploy \
  REGISTRY=my-registry.example.com \
  TAG=mvp \
  NAMESPACE=slurm-web

# 或分步執行：
# 1. 建置所有映像檔
make build-all REGISTRY=my-registry.example.com TAG=mvp

# 2. 推送到 Registry
make push-all REGISTRY=my-registry.example.com TAG=mvp

# 3. 部署到 K8s
make deploy NAMESPACE=slurm-web

# 4. 驗證部署
make verify NAMESPACE=slurm-web
```

### 手動建置 (如果不使用 Makefile)

在專案根目錄執行以下命令：

```bash
# 設定您的 registry URL
export REGISTRY="my-registry.example.com"

# 建置 Gateway image
docker build -f deployment/docker/gateway.Dockerfile -t ${REGISTRY}/slurm-web:gateway-mvp .

# 建置 Agent image
docker build -f deployment/docker/agent.Dockerfile -t ${REGISTRY}/slurm-web:agent-mvp .

# 推送到 Registry
docker push ${REGISTRY}/slurm-web:gateway-mvp
docker push ${REGISTRY}/slurm-web:agent-mvp
```

### 步驟 2: 配置 values.yaml

編輯 `deployment/helm/slurm-web/values.yaml`，更新以下重要參數：

```yaml
# 更新 container image 位置
gateway:
  image: "YOUR-REGISTRY/slurm-web:gateway-mvp"
  ingress:
    host: "slurm-web.your-domain.com"  # 修改為您的域名

agent:
  image: "YOUR-REGISTRY/slurm-web:agent-mvp"
  slurmrestd:
    uri: "http://slurm-restapi.slurm-namespace.svc.cluster.local:6820"  # 修改為實際的 Slurm API 服務

# 生成並設定 JWT secret key（至少 32 字元）
secrets:
  jwtKey: "YOUR-SECURE-JWT-KEY-AT-LEAST-32-CHARACTERS"
```

**生成安全的 JWT Key:**

```bash
openssl rand -base64 32
```

### 步驟 3: 部署到 Kubernetes

**使用 Makefile:**

```bash
cd deployment
make deploy NAMESPACE=slurm-web
```

**或手動執行 Helm 命令:**

```bash
# 建立 namespace
kubectl create namespace slurm-web

# 使用 Helm 安裝
helm upgrade --install slurm-web ./deployment/helm/slurm-web \
  --namespace slurm-web \
  --create-namespace

# 檢查部署狀態
kubectl get pods -n slurm-web
kubectl get svc -n slurm-web
kubectl get ingress -n slurm-web
```

### 步驟 4: 驗證部署

**使用 Makefile 一鍵驗證:**

```bash
cd deployment
make verify NAMESPACE=slurm-web
```

**或手動執行驗證步驟:**

#### 4.1 檢查 Pod 狀態

```bash
# 使用 Makefile
make status NAMESPACE=slurm-web

# 或手動執行
kubectl get pods -n slurm-web

# 預期輸出：
# NAME                                   READY   STATUS    RESTARTS   AGE
# slurm-web-gateway-xxxxxxxxxx-xxxxx    1/1     Running   0          2m
# slurm-web-agent-xxxxxxxxxx-xxxxx      1/1     Running   0          2m
# slurm-web-redis-xxxxxxxxxx-xxxxx      1/1     Running   0          2m
```

#### 4.2 驗證 Agent 連線到 Slurm REST API

```bash
# 使用 Makefile
make test-agent NAMESPACE=slurm-web

# 或手動執行
kubectl exec -it -n slurm-web deploy/slurm-web-agent -- \
  curl http://localhost:5012/info

# 預期看到 JSON 回應，包含 cluster 資訊
```

#### 4.3 檢查 Gateway 健康狀態

```bash
# 使用 Makefile
make test-gateway NAMESPACE=slurm-web

# 或手動執行
kubectl exec -it -n slurm-web deploy/slurm-web-gateway -- \
  curl http://localhost:5011/api/gateway/agents

# 預期回應: {"agents": [...]}
```

#### 4.4 測試外部存取

```bash
# 透過 Ingress 存取
curl -k https://slurm-web.your-domain.com

# 或使用 Makefile port-forward
make port-forward-gateway NAMESPACE=slurm-web

# 瀏覽器開啟: http://localhost:5011
```

## Makefile 常用命令

`deployment/Makefile` 提供完整的自動化部署工具，以下為常用命令：

### 建置與推送

```bash
# 查看所有可用命令
make help

# 建置所有映像檔
make build-all REGISTRY=my-registry.com TAG=v1.0.0

# 建置並推送
make build-and-push REGISTRY=my-registry.com TAG=v1.0.0

# 僅建置 Gateway
make build-gateway REGISTRY=my-registry.com TAG=v1.0.0

# 僅建置 Agent
make build-agent REGISTRY=my-registry.com TAG=v1.0.0
```

### 部署與管理

```bash
# 完整部署流程（建置→推送→部署→驗證）
make full-deploy REGISTRY=my-registry.com TAG=mvp NAMESPACE=slurm-web

# 僅部署（不建置）
make deploy NAMESPACE=slurm-web

# 更新現有部署
make upgrade NAMESPACE=slurm-web

# 回滾到上一版本
make rollback NAMESPACE=slurm-web

# 卸載
make uninstall NAMESPACE=slurm-web
```

### 驗證與除錯

```bash
# 完整驗證流程
make verify NAMESPACE=slurm-web

# 查看部署狀態
make status NAMESPACE=slurm-web

# 查看日誌
make logs-gateway NAMESPACE=slurm-web
make logs-agent NAMESPACE=slurm-web
make logs-redis NAMESPACE=slurm-web

# 測試各元件
make test-agent NAMESPACE=slurm-web
make test-gateway NAMESPACE=slurm-web

# 進入 Pod Shell
make shell-gateway NAMESPACE=slurm-web
make shell-agent NAMESPACE=slurm-web

# Port Forward（本地測試）
make port-forward-gateway NAMESPACE=slurm-web  # localhost:5011
make port-forward-agent NAMESPACE=slurm-web    # localhost:5012
```

### Helm 工具

```bash
# 檢查 Chart 語法
make helm-lint

# 產生模板（不部署）
make helm-template NAMESPACE=slurm-web

# 試運行（模擬安裝）
make helm-dry-run NAMESPACE=slurm-web
```

### 開發工具

```bash
# 持續監控 Pod 狀態
make watch NAMESPACE=slurm-web

# 查看 Pod 詳細資訊
make describe-gateway NAMESPACE=slurm-web
make describe-agent NAMESPACE=slurm-web
```

## 常見配置調整

### 更改認證方式

編輯 `values.yaml`:

```yaml
gateway:
  auth:
    method: "ldap"  # 選項: "ldap", "jwt", "none"
```

如果使用 LDAP，需要在 `gateway-configmap.yaml` 中配置 LDAP 參數。

### 調整資源限制

```yaml
gateway:
  resources:
    requests:
      memory: "512Mi"
      cpu: "200m"
    limits:
      memory: "1Gi"
      cpu: "1000m"
```

### 啟用 TLS

```yaml
gateway:
  ingress:
    tls:
      enabled: true
      secretName: "slurm-web-tls"  # 需要預先建立 TLS Secret
```

建立 TLS Secret:

```bash
kubectl create secret tls slurm-web-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n slurm-web
```

## 安全性說明

本 MVP 部署已包含以下安全性強化措施：

### 1. Container 安全性

**Non-root User**: 所有容器以非 root 使用者執行 (UID/GID 1000)
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
```

**Capabilities Drop**: 移除所有不必要的 Linux capabilities
```yaml
capabilities:
  drop:
  - ALL
```

**Privilege Escalation**: 禁止權限提升
```yaml
allowPrivilegeEscalation: false
```

### 2. JWT Secret 驗證

部署前會自動驗證 JWT secret 的安全性：
- ✅ 檢查是否使用預設值（包含 "CHANGE-ME"）
- ✅ 驗證 secret 長度（最小 32 字元）
- ❌ 使用不安全 secret 時部署將失敗

**生成安全的 JWT Secret**:
```bash
# 生成 32 字元 base64 編碼的 secret
openssl rand -base64 32

# 在 values.yaml 中設定
secrets:
  jwtKey: "your-generated-secure-key-here"
```

### 3. Pod Security Context

所有 Pod 啟用以下安全設定：
- `runAsNonRoot: true` - 強制非 root 執行
- `fsGroup: 1000` - 統一檔案系統群組權限
- `seccompProfile: RuntimeDefault` - 啟用 seccomp 過濾

### 4. Startup Probes

新增 startupProbe 支援慢啟動服務：
- 初始延遲: 5 秒
- 檢查週期: 5 秒
- 最大失敗次數: 12 次 (最多等待 60 秒)

### 5. Health Checks

容器內建 health check：
```bash
# Gateway
curl -f http://localhost:5011/health

# Agent
curl -f http://localhost:5012/info
```

### 安全性檢查清單

部署前請確認：
- [ ] JWT secret 已修改為安全的隨機值
- [ ] Container images 來自可信任的 registry
- [ ] Ingress TLS 已啟用並配置有效憑證
- [ ] Slurm REST API 連線使用內部網路
- [ ] Namespace 已配置適當的 RBAC 權限

### 進階安全建議 (Phase 2)

MVP 之後可考慮以下安全強化：
1. **Network Policies**: 限制 Pod 間網路流量
2. **Pod Security Admission**: 啟用 Kubernetes PSA
3. **Secret 加密**: 使用 Sealed Secrets 或 External Secrets Operator
4. **Rate Limiting**: 在 Ingress 層級配置 rate limiting
5. **WAF**: 整合 Web Application Firewall (ModSecurity)
6. **mTLS**: 實作 Service Mesh (Istio/Linkerd)

詳細安全性修復說明請參閱: [SECURITY_FIXES.md](../SECURITY_FIXES.md)

---

## 疑難排解

### Pod 無法啟動

```bash
# 查看 Pod 詳細狀態
kubectl describe pod <pod-name> -n slurm-web

# 查看 logs
kubectl logs <pod-name> -n slurm-web
```

### Agent 無法連接 Slurm REST API

1. 確認 `agent.slurmrestd.uri` 配置正確
2. 檢查 Slurm REST API 服務是否運行：

```bash
kubectl get svc -n slurm-namespace
```

3. 測試網路連通性：

```bash
kubectl exec -it -n slurm-web deploy/slurm-web-agent -- \
  curl http://slurm-restapi.slurm-namespace.svc.cluster.local:6820/openapi/v3
```

### Ingress 無法存取

1. 確認 Ingress Controller 已安裝：

```bash
kubectl get pods -n ingress-nginx
```

2. 檢查 Ingress 規則：

```bash
kubectl describe ingress slurm-web -n slurm-web
```

3. 確認 DNS 解析正確指向 Ingress Controller 的 External IP

## 升級部署

```bash
# 更新 values.yaml 或 images 後執行
helm upgrade slurm-web ./deployment/helm/slurm-web \
  --namespace slurm-web
```

## 卸載

```bash
# 移除 Helm release
helm uninstall slurm-web -n slurm-web

# 刪除 namespace（可選）
kubectl delete namespace slurm-web
```

## 架構說明

此 MVP 部署包含以下元件：

- **Gateway (1 replica)**: 提供前端界面與 API 入口
- **Agent (1 replica)**: 與 Slurm REST API 通訊
- **Redis (1 replica)**: 快取服務（無持久化）
- **Ingress**: 提供外部存取

### 網路拓撲

```
Internet
    ↓
Ingress (gateway.ingress.host)
    ↓
Gateway Service (:5011)
    ↓
Gateway Pod
    ↓
Agent Service (:5012)
    ↓
Agent Pod
    ↓
Slurm REST API (:6820)
```

## 下一步

MVP 部署成功後，可以考慮以下改進：

1. **高可用性 (HA)**: 增加 Gateway 和 Agent replica 數量
2. **持久化**: 為 Redis 添加 PersistentVolume
3. **監控**: 整合 Prometheus 和 Grafana
4. **備份**: 實作定期備份策略
5. **CI/CD**: 建立自動化部署流程
6. **安全加固**: 實施 Network Policy、RBAC、Secret 加密等

## 支援與回饋

如有問題或建議，請至專案 GitHub 提交 Issue：
https://github.com/rackslab/slurm-web/issues
