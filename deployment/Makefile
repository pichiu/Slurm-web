# Slurm-web Kubernetes Deployment Makefile
# Usage: make <target> [VARIABLE=value]

# =============================================================================
# Configuration Variables
# =============================================================================

# Container Registry
REGISTRY ?= your-registry.example.com
IMAGE_NAME ?= $(REGISTRY)/slurm-web
TAG ?= mvp

# Helm Configuration
HELM_CHART ?= ./helm/slurm-web
HELM_RELEASE ?= slurm-web
NAMESPACE ?= slurm-web
VALUES_FILE ?= ./helm/slurm-web/values.yaml

# Docker Build Context
BUILD_CONTEXT ?= ..
DOCKER_DIR ?= ./docker

# =============================================================================
# Build Targets
# =============================================================================

.PHONY: help
help: ## 顯示說明
	@echo "Slurm-web K8s Deployment - Available Targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Configuration Variables:"
	@echo "  REGISTRY=$(REGISTRY)"
	@echo "  TAG=$(TAG)"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo ""
	@echo "Example: make build-all REGISTRY=my-registry.com TAG=v1.0.0"

.PHONY: build-gateway
build-gateway: ## 建置 Gateway 映像檔
	@echo "Building image: $(IMAGE_NAME):gateway-$(TAG)"
	docker build \
		-f $(DOCKER_DIR)/gateway.Dockerfile \
		-t $(IMAGE_NAME):gateway-$(TAG) \
		$(BUILD_CONTEXT)

.PHONY: build-agent
build-agent: ## 建置 Agent 映像檔
	@echo "Building image: $(IMAGE_NAME):agent-$(TAG)"
	docker build \
		-f $(DOCKER_DIR)/agent.Dockerfile \
		-t $(IMAGE_NAME):agent-$(TAG) \
		$(BUILD_CONTEXT)

.PHONY: build-all
build-all: build-gateway build-agent ## 建置所有映像檔

.PHONY: push-gateway
push-gateway: ## 推送 Gateway 映像檔
	@echo "Pushing image: $(IMAGE_NAME):gateway-$(TAG)"
	docker push $(IMAGE_NAME):gateway-$(TAG)

.PHONY: push-agent
push-agent: ## 推送 Agent 映像檔
	@echo "Pushing image: $(IMAGE_NAME):agent-$(TAG)"
	docker push $(IMAGE_NAME):agent-$(TAG)

.PHONY: push-all
push-all: push-gateway push-agent ## 推送所有映像檔

.PHONY: build-and-push
build-and-push: build-all push-all ## 建置並推送所有映像檔

# =============================================================================
# Kubernetes Deployment Targets
# =============================================================================

.PHONY: create-namespace
create-namespace: ## 建立 Kubernetes Namespace
	@echo "Creating namespace: $(NAMESPACE)"
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

.PHONY: helm-lint
helm-lint: ## 檢查 Helm Chart 語法
	@echo "Linting Helm chart: $(HELM_CHART)"
	helm lint $(HELM_CHART)

.PHONY: helm-template
helm-template: ## 產生 Helm 模板（不部署）
	@echo "Rendering Helm templates:"
	helm template $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(NAMESPACE) \
		--values $(VALUES_FILE) \
		--set gateway.image=$(IMAGE_NAME):gateway-$(TAG) \
		--set agent.image=$(IMAGE_NAME):agent-$(TAG)

.PHONY: helm-dry-run
helm-dry-run: ## Helm 試運行（模擬安裝）
	@echo "Dry-run Helm install/upgrade:"
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--values $(VALUES_FILE) \
		--set gateway.image=$(IMAGE_NAME):gateway-$(TAG) \
		--set agent.image=$(IMAGE_NAME):agent-$(TAG) \
		--dry-run

.PHONY: deploy
deploy: create-namespace ## 部署到 Kubernetes
	@echo "Deploying Slurm-web to namespace: $(NAMESPACE)"
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--values $(VALUES_FILE) \
		--set gateway.image=$(IMAGE_NAME):gateway-$(TAG) \
		--set agent.image=$(IMAGE_NAME):agent-$(TAG) \
		--wait \
		--timeout 5m

.PHONY: upgrade
upgrade: ## 更新 Helm Release
	@echo "Upgrading Helm release: $(HELM_RELEASE)"
	helm upgrade $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(NAMESPACE) \
		--values $(VALUES_FILE) \
		--set gateway.image=$(IMAGE_NAME):gateway-$(TAG) \
		--set agent.image=$(IMAGE_NAME):agent-$(TAG) \
		--wait \
		--timeout 5m

.PHONY: rollback
rollback: ## 回滾到上一版本
	@echo "Rolling back Helm release: $(HELM_RELEASE)"
	helm rollback $(HELM_RELEASE) --namespace $(NAMESPACE)

.PHONY: uninstall
uninstall: ## 移除 Helm Release
	@echo "Uninstalling Helm release: $(HELM_RELEASE)"
	helm uninstall $(HELM_RELEASE) --namespace $(NAMESPACE)

# =============================================================================
# Validation Targets
# =============================================================================

.PHONY: status
status: ## 查看部署狀態
	@echo "=== Helm Release Status ==="
	helm status $(HELM_RELEASE) -n $(NAMESPACE)
	@echo ""
	@echo "=== Pods Status ==="
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/instance=$(HELM_RELEASE)
	@echo ""
	@echo "=== Services ==="
	kubectl get svc -n $(NAMESPACE) -l app.kubernetes.io/instance=$(HELM_RELEASE)

.PHONY: logs-gateway
logs-gateway: ## 查看 Gateway 日誌
	@echo "Streaming Gateway logs (Ctrl+C to exit):"
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=slurm-web-gateway -f --tail=100

.PHONY: logs-agent
logs-agent: ## 查看 Agent 日誌
	@echo "Streaming Agent logs (Ctrl+C to exit):"
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=slurm-web-agent -f --tail=100

.PHONY: logs-redis
logs-redis: ## 查看 Redis 日誌
	@echo "Streaming Redis logs (Ctrl+C to exit):"
	kubectl logs -n $(NAMESPACE) -l app=redis -f --tail=100

.PHONY: test-agent
test-agent: ## 測試 Agent 連線（內部）
	@echo "Testing Agent connectivity:"
	kubectl exec -it -n $(NAMESPACE) deploy/$(HELM_RELEASE)-agent -- \
		curl -s http://localhost:5012/info | jq .

.PHONY: test-gateway
test-gateway: ## 測試 Gateway 連線（內部）
	@echo "Testing Gateway connectivity:"
	kubectl exec -it -n $(NAMESPACE) deploy/$(HELM_RELEASE)-gateway -- \
		curl -s http://localhost:5011/api/gateway/agents | jq .

.PHONY: shell-gateway
shell-gateway: ## 進入 Gateway Pod Shell
	kubectl exec -it -n $(NAMESPACE) deploy/$(HELM_RELEASE)-gateway -- /bin/bash

.PHONY: shell-agent
shell-agent: ## 進入 Agent Pod Shell
	kubectl exec -it -n $(NAMESPACE) deploy/$(HELM_RELEASE)-agent -- /bin/bash

.PHONY: verify
verify: ## 完整驗證流程
	@echo "=== Verification Started ==="
	@echo ""
	@echo "1. Checking Pods..."
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/instance=$(HELM_RELEASE)
	@echo ""
	@echo "2. Testing Redis connectivity..."
	kubectl exec -n $(NAMESPACE) deploy/$(HELM_RELEASE)-gateway -- redis-cli -h $(HELM_RELEASE)-redis ping
	@echo ""
	@echo "3. Testing Agent /info endpoint..."
	kubectl exec -n $(NAMESPACE) deploy/$(HELM_RELEASE)-agent -- curl -sf http://localhost:5012/info || echo "FAIL: Agent not responding"
	@echo ""
	@echo "4. Testing Gateway /agents endpoint..."
	kubectl exec -n $(NAMESPACE) deploy/$(HELM_RELEASE)-gateway -- curl -sf http://localhost:5011/api/gateway/agents || echo "FAIL: Gateway not responding"
	@echo ""
	@echo "=== Verification Completed ==="

# =============================================================================
# Complete Workflow Targets
# =============================================================================

.PHONY: full-deploy
full-deploy: build-and-push deploy verify ## 完整部署流程（建置→推送→部署→驗證）
	@echo ""
	@echo "=========================================="
	@echo "  Full Deployment Completed Successfully!"
	@echo "=========================================="
	@echo ""
	@echo "Next steps:"
	@echo "  1. Configure Ingress: kubectl edit ingress -n $(NAMESPACE)"
	@echo "  2. Access Gateway: https://<your-ingress-host>"
	@echo "  3. Monitor logs: make logs-gateway"

.PHONY: redeploy
redeploy: build-and-push upgrade verify ## 重新部署（建置→推送→更新→驗證）

# =============================================================================
# Development Helpers
# =============================================================================

.PHONY: watch
watch: ## 持續監控 Pod 狀態
	watch -n 2 kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/instance=$(HELM_RELEASE)

.PHONY: describe-gateway
describe-gateway: ## 查看 Gateway Pod 詳細資訊
	kubectl describe pod -n $(NAMESPACE) -l app.kubernetes.io/name=slurm-web-gateway

.PHONY: describe-agent
describe-agent: ## 查看 Agent Pod 詳細資訊
	kubectl describe pod -n $(NAMESPACE) -l app.kubernetes.io/name=slurm-web-agent

.PHONY: port-forward-gateway
port-forward-gateway: ## 本地 Port Forward Gateway (5011)
	@echo "Port forwarding Gateway to localhost:5011"
	kubectl port-forward -n $(NAMESPACE) svc/$(HELM_RELEASE)-gateway 5011:5011

.PHONY: port-forward-agent
port-forward-agent: ## 本地 Port Forward Agent (5012)
	@echo "Port forwarding Agent to localhost:5012"
	kubectl port-forward -n $(NAMESPACE) svc/$(HELM_RELEASE)-agent 5012:5012

.PHONY: clean
clean: ## 清理所有資源（危險操作！）
	@echo "WARNING: This will delete ALL resources in namespace $(NAMESPACE)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		helm uninstall $(HELM_RELEASE) -n $(NAMESPACE) || true; \
		kubectl delete namespace $(NAMESPACE) || true; \
	fi

# =============================================================================
# Default Target
# =============================================================================

.DEFAULT_GOAL := help
