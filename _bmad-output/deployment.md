# Slurm-web 部署指南

## 系統需求 {#requirements}

### 硬體需求

| 組件 | 最低需求 | 建議配置 |
|------|----------|----------|
| Gateway | 1 CPU, 512MB RAM | 2 CPU, 2GB RAM |
| Agent | 1 CPU, 512MB RAM | 2 CPU, 1GB RAM |
| Redis (可選) | 1 CPU, 256MB RAM | 1 CPU, 1GB RAM |

### 軟體需求

| 軟體 | Gateway | Agent |
|------|---------|-------|
| Python | 3.6+ | 3.6+ |
| Slurm | - | 21.08+ |
| slurmrestd | - | 21.08+ |
| Redis | 可選 | 可選 |
| LDAP Server | 可選 | - |

### 網路埠

| 服務 | 預設埠 | 說明 |
|------|--------|------|
| Gateway | 5011 | Web 介面與 API |
| Agent | 5012 | 叢集 API |
| Redis | 6379 | 快取服務 |

---

## 部署選項 {#options}

### 方式 1: 系統套件（推薦）

#### Debian/Ubuntu

```bash
# 新增套件庫
curl -fsSL https://packages.rackslab.io/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/rackslab.gpg
echo "deb https://packages.rackslab.io/deb stable main" | sudo tee /etc/apt/sources.list.d/rackslab.list

# 安裝
sudo apt update
sudo apt install slurm-web
```

#### RHEL/CentOS

```bash
# 新增套件庫
sudo cat > /etc/yum.repos.d/rackslab.repo << EOF
[rackslab]
name=Rackslab Repository
baseurl=https://packages.rackslab.io/rpm/stable
enabled=1
gpgcheck=1
gpgkey=https://packages.rackslab.io/gpg
EOF

# 安裝
sudo dnf install slurm-web
```

### 方式 2: pip 安裝

```bash
pip install slurm-web
```

### 方式 3: 從原始碼安裝

```bash
git clone https://github.com/rackslab/Slurm-web.git
cd Slurm-web
pip install .
cd frontend && npm install && npm run build
```

---

## 配置說明 {#configuration}

### 配置檔案位置

| 檔案 | 說明 |
|------|------|
| `/etc/slurm-web/gateway.ini` | Gateway 站點配置 |
| `/etc/slurm-web/agent.ini` | Agent 站點配置 |
| `/etc/slurm-web/policy.ini` | RBAC 角色配置 |
| `/usr/share/slurm-web/conf/` | Vendor 預設配置 |

### Gateway 配置

#### 基本配置

```ini
# /etc/slurm-web/gateway.ini

[service]
interface = 0.0.0.0
port = 5011
cors = no

[ui]
host = https://dashboard.example.com
enabled = yes
path = /usr/share/slurm-web/frontend

[agents]
url =
  https://cluster1.example.com:5012
  https://cluster2.example.com:5012

[authentication]
enabled = yes
method = ldap

[ldap]
uri = ldap://ldap.example.com
user_base = ou=people,dc=example,dc=com
group_base = ou=groups,dc=example,dc=com

[jwt]
key = /var/lib/slurm-web/jwt.key
duration = 1
algorithm = HS256
```

#### LDAP 配置範例

```ini
[ldap]
uri = ldaps://ldap.example.com
cacert = /etc/ssl/certs/ca-certificates.crt
user_base = ou=people,dc=example,dc=com
group_base = ou=groups,dc=example,dc=com
user_class = posixAccount
user_name_attribute = uid
user_fullname_attribute = cn
group_name_attribute = cn
bind_dn = cn=readonly,dc=example,dc=com
bind_password_file = /etc/slurm-web/ldap_password
restricted_groups =
  hpc-users
  admins
```

### Agent 配置

#### 基本配置

```ini
# /etc/slurm-web/agent.ini

[service]
cluster = mycluster
interface = 0.0.0.0
port = 5012

[slurmrestd]
uri = unix:///run/slurmrestd/slurmrestd.socket
auth = jwt
jwt_mode = auto
jwt_key = /var/lib/slurm-web/slurmrestd.key

[jwt]
key = /var/lib/slurm-web/jwt.key
algorithm = HS256

[cache]
enabled = yes
host = localhost
port = 6379

[racksdb]
enabled = yes
db = /var/lib/racksdb
infrastructure = mycluster

[metrics]
enabled = yes
host = http://prometheus.example.com:9090
job = slurm
```

### RBAC 配置

```ini
# /etc/slurm-web/policy.ini

[user]
actions = view-stats, view-jobs, view-nodes, view-partitions, view-qos, view-reservations

[operator]
actions = view-stats, view-jobs, view-nodes, view-partitions, view-qos, view-reservations, cache-view

[admin]
actions = view-stats, view-jobs, view-nodes, view-partitions, view-qos, view-reservations, view-accounts, associations-view, cache-view, cache-reset
```

---

## 服務管理

### systemd 服務

#### 啟動服務

```bash
# Gateway
sudo systemctl enable --now slurm-web-gateway

# Agent
sudo systemctl enable --now slurm-web-agent
```

#### 檢視狀態

```bash
sudo systemctl status slurm-web-gateway
sudo systemctl status slurm-web-agent
```

#### 檢視日誌

```bash
sudo journalctl -u slurm-web-gateway -f
sudo journalctl -u slurm-web-agent -f
```

### WSGI 部署（生產環境）

#### 使用 Gunicorn

```bash
gunicorn -w 4 -b 0.0.0.0:5011 "slurmweb.exec.gateway:create_app()"
```

#### 使用 uWSGI

```ini
# /etc/slurm-web/gateway.uwsgi.ini
[uwsgi]
module = slurmweb.exec.gateway:create_app()
master = true
processes = 4
socket = /run/slurm-web/gateway.sock
chmod-socket = 660
vacuum = true
```

---

## SSL/TLS 配置

### 使用 Nginx 反向代理

```nginx
# /etc/nginx/sites-available/slurm-web
server {
    listen 443 ssl http2;
    server_name dashboard.example.com;

    ssl_certificate /etc/ssl/certs/dashboard.crt;
    ssl_certificate_key /etc/ssl/private/dashboard.key;

    location / {
        proxy_pass http://127.0.0.1:5011;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Agent HTTPS

使用自簽憑證或 CA 簽發憑證：

```bash
# 產生自簽憑證
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/slurm-web/agent.key \
  -out /etc/slurm-web/agent.crt
```

Gateway 配置中指定 CA 憑證：

```ini
[agents]
cacert = /etc/slurm-web/ca.crt
```

---

## 整合配置

### slurmrestd 整合

#### 配置 slurmrestd

```bash
# /etc/slurm/slurmrestd.conf
include /etc/slurm/slurm.conf

# JWT 認證
AuthType=auth/jwt
```

#### systemd 服務

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

### Redis 整合

```bash
# 安裝 Redis
sudo apt install redis-server

# 配置密碼（可選）
sudo vim /etc/redis/redis.conf
# requirepass YOUR_PASSWORD

# 重啟服務
sudo systemctl restart redis
```

### Prometheus 整合

#### 配置 Prometheus 抓取

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'slurm'
    static_configs:
      - targets:
        - 'cluster1-agent.example.com:5012'
        - 'cluster2-agent.example.com:5012'
    metrics_path: /metrics
```

### RacksDB 整合

```bash
# 安裝 RacksDB
pip install racksdb

# 初始化資料庫
mkdir -p /var/lib/racksdb
racksdb init /var/lib/racksdb
```

---

## 故障排除

### 常見問題

#### Gateway 無法連接 Agent

1. 檢查網路連線
   ```bash
   curl -k https://agent-host:5012/info
   ```

2. 檢查防火牆
   ```bash
   sudo firewall-cmd --list-ports
   sudo firewall-cmd --add-port=5012/tcp --permanent
   ```

3. 檢查 Agent 日誌
   ```bash
   sudo journalctl -u slurm-web-agent -n 100
   ```

#### LDAP 認證失敗

1. 測試 LDAP 連線
   ```bash
   slurm-web-ldap --user testuser
   ```

2. 檢查憑證
   ```bash
   openssl s_client -connect ldap.example.com:636
   ```

#### slurmrestd 連線錯誤

1. 檢查 socket 權限
   ```bash
   ls -la /run/slurmrestd/slurmrestd.socket
   ```

2. 測試連線
   ```bash
   slurm-web-connect
   ```

### 診斷工具

```bash
# 顯示配置
slurm-web-showconf gateway
slurm-web-showconf agent

# 測試 LDAP
slurm-web-ldap --user username

# 測試 slurmrestd 連線
slurm-web-connect

# 產生 JWT Token
slurm-web-genjwt
```

---

## 監控與維護

### 健康檢查

```bash
# Gateway 健康檢查
curl http://localhost:5011/api/version

# Agent 健康檢查
curl http://localhost:5012/info
```

### 效能監控

- 監控 Redis 快取命中率
- 監控 API 回應時間
- 監控記憶體使用量

### 備份

需要備份的檔案：
- `/etc/slurm-web/` - 配置檔案
- `/var/lib/slurm-web/` - JWT 金鑰

---

## 安全建議

1. **使用 HTTPS**: 所有生產環境應使用 SSL/TLS
2. **限制網路存取**: 使用防火牆限制 Agent 端口存取
3. **定期更新**: 保持軟體更新以修復安全漏洞
4. **審計日誌**: 啟用詳細日誌並定期審查
5. **最小權限**: RBAC 配置遵循最小權限原則

---

*此文件由 BMAD Document Project Workflow 自動生成*
