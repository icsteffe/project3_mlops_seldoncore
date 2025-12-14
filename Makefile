# Makefile for Seldon Core MLOps Project
# This file provides simple commands to manage the entire deployment lifecycle

# Variables
CLUSTER_NAME ?= mlops-seldon
MODEL_NAME ?= distilbert-classifier
DOCKER_IMAGE ?= distilbert-serving:latest
MODEL_DIR ?= exported_model
NAMESPACE ?= default

# Default target - show available commands
.PHONY: help
help:
	@echo "════════════════════════════════════════════════════════════════"
	@echo "  Seldon Core MLOps Project - Available Commands"
	@echo "════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "  Setup & Installation:"
	@echo "    make setup            - Complete local K8s setup (Kind + Seldon Core)"
	@echo "    make setup-cluster    - Create Kind cluster only"
	@echo "    make install-seldon   - Install Seldon Core only"
	@echo ""
	@echo "  Model Deployment:"
	@echo "    make build-image      - Build Docker image for inference server"
	@echo "    make deploy           - Deploy model to Kubernetes"
	@echo "    make undeploy         - Remove model deployment"
	@echo "    make redeploy         - Rebuild and redeploy (build + deploy)"
	@echo ""
	@echo "  Testing & Validation:"
	@echo "    make test             - Send sample inference requests"
	@echo "    make test-health      - Check model health status"
	@echo "    make test-load        - Run basic load test"
	@echo ""
	@echo "  Monitoring & Debugging:"
	@echo "    make logs             - View model server logs"
	@echo "    make status           - Check deployment status"
	@echo "    make metrics          - View Prometheus metrics"
	@echo "    make describe         - Detailed resource information"
	@echo ""
	@echo "  Port Forwarding (Access from localhost):"
	@echo "    make forward          - Forward model API port (8000 -> localhost:8000)"
	@echo "    make forward-metrics  - Forward metrics port (8000 -> localhost:8001)"
	@echo ""
	@echo "  Cleanup:"
	@echo "    make cleanup          - Remove deployment and cluster"
	@echo "    make cleanup-deploy   - Remove deployment only (keep cluster)"
	@echo "    make cleanup-cluster  - Delete Kind cluster only"
	@echo ""
	@echo "════════════════════════════════════════════════════════════════"

#═══════════════════════════════════════════════════════════════════════
# SETUP - Install all dependencies and create local Kubernetes cluster
#═══════════════════════════════════════════════════════════════════════

.PHONY: setup
setup: check-prerequisites setup-cluster install-seldon
	@echo "v Setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Export a trained model:  python export_model.py --checkpoint <path>"
	@echo "  2. Build inference image:   make build-image"
	@echo "  3. Deploy to Kubernetes:    make deploy"

.PHONY: check-prerequisites
check-prerequisites:
	@echo "Checking prerequisites..."
	@powershell -Command "if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Host \"❌ Docker is required but not installed. See: https://docs.docker.com/get-docker/\"; exit 1; }"
	@powershell -Command "if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { Write-Host \"❌ kubectl is required but not installed. See: https://kubernetes.io/docs/tasks/tools/\"; exit 1; }"
	@powershell -Command "if (-not (Get-Command kind -ErrorAction SilentlyContinue)) { Write-Host \"❌ Kind is required but not installed. See: https://kind.sigs.k8s.io/docs/user/quick-start/#installation\"; exit 1; }"
	@powershell -Command "if (-not (Get-Command helm -ErrorAction SilentlyContinue)) { Write-Host \"❌ Helm is required but not installed. See: https://helm.sh/docs/intro/install/\"; exit 1; }"
	@echo "v All prerequisites installed"

.PHONY: setup-cluster
setup-cluster:
	@echo "Creating Kind cluster '$(CLUSTER_NAME)'..."
	@powershell -File "./scripts/setup-kind-cluster.ps1" -ClusterName "$(CLUSTER_NAME)"
	@kubectl cluster-info --context kind-$(CLUSTER_NAME)

.PHONY: install-seldon
install-seldon:
	@echo "Installing Seldon Core v1.17.1..."
	@kubectl create namespace seldon-system --dry-run=client -o yaml | kubectl apply -f -
	@helm repo add seldonio https://storage.googleapis.com/seldon-charts || true
	@helm repo update
	@helm upgrade --install seldon-core seldonio/seldon-core-operator \
		--namespace seldon-system \
		--version 1.17.1 \
		--set usageMetrics.enabled=false \
		--set istio.enabled=false \
		--wait \
		--timeout 5m
	@echo "v Seldon Core installed"
	@echo "Waiting for Seldon operator to be ready..."
	@kubectl wait --for=condition=available --timeout=300s \
		deployment/seldon-controller-manager -n seldon-system
	@echo "v Seldon Core is ready"

#═══════════════════════════════════════════════════════════════════════
# BUILD - Create Docker image with inference server
#═══════════════════════════════════════════════════════════════════════

.PHONY: build-image
build-image:
	@echo "Building Docker image '$(DOCKER_IMAGE)'..."
	@docker build -t $(DOCKER_IMAGE) -f ./model-serving/Dockerfile .
	@echo "v Image built successfully"
	@echo "Loading image into Kind cluster..."
	@kind load docker-image $(DOCKER_IMAGE) --name $(CLUSTER_NAME)

#═══════════════════════════════════════════════════════════════════════
# DEPLOY - Deploy model to Kubernetes using Seldon Core
#═══════════════════════════════════════════════════════════════════════

.PHONY: deploy
deploy: check-model-export
	@powershell -File "./scripts/deploy-model.ps1" -ModelName "$(MODEL_NAME)" -Namespace "$(NAMESPACE)" -ErrorAction Stop
	@make status

.PHONY: check-model-export
check-model-export:
	@powershell -Command " \
		if (-not (Test-Path -Path '$(MODEL_DIR)' -PathType Container)) { \
			Write-Host \"x Model directory '$(MODEL_DIR)' not found\"; \
			Write-Host \"\"; \
			Write-Host \"Please export a trained model first:\"; \
			Write-Host \"  python export_model.py --checkpoint <path-to-checkpoint.ckpt>\"; \
			Write-Host \"\"; \
		exit 1; \
		}"

.PHONY: undeploy
undeploy:
	@echo "Removing deployment..."
	@kubectl delete -f k8s/seldon-deployment.yaml --ignore-not-found=true
	@kubectl delete configmap $(MODEL_NAME)-model --ignore-not-found=true
	@echo "v Deployment removed"

.PHONY: redeploy
redeploy: undeploy build-image deploy
	@echo "v Redeployment complete"

#═══════════════════════════════════════════════════════════════════════
# TEST - Validate the deployment works correctly
#═══════════════════════════════════════════════════════════════════════

.PHONY: test
test:
	@echo "Sending test inference requests..."
	@echo ""
	@echo "Test 1: Similar sentences (should predict 1 = paraphrase)"
	@kubectl run -it --rm test-client --image=curlimages/curl:latest --restart=Never -- powershell -Command "curl -s -X POST http://$(MODEL_NAME)-default.$(NAMESPACE):8000/api/v1.0/predictions -H 'Content-Type: application/json' -d '{\"data\": {\"ndarray\": [[\"The cat sat on the mat\", \"A cat was sitting on a mat\"]]}}' | python -m json.tool"
	@echo ""
	@echo "Test 2: Different sentences (should predict 0 = not paraphrase)"
	@kubectl run -it --rm test-client --image=curlimages/curl:latest --restart=Never -- powershell -Command "curl -s -X POST http://$(MODEL_NAME)-default.$(NAMESPACE):8000/api/v1.0/predictions -H 'Content-Type: application/json' -d '{\"data\": {\"ndarray\": [[\"The weather is nice\", \"I like pizza\"]]}}' | python -m json.tool"

.PHONY: test-health
test-health:
	@echo "Checking model health..."
	@kubectl run -it --rm test-client --image=curlimages/curl:latest --restart=Never -- powershell -Command "curl -s http://$(MODEL_NAME)-default.$(NAMESPACE):8000/health/status"

.PHONY: test-load
test-load:
	@echo "Running basic load test (100 requests)..."
	@echo "This tests if the model can handle concurrent requests"
	@powershell -Command "for ($i = 1; $i -le 100; $i++) { kubectl run test-client-$i --image=curlimages/curl:latest --restart=Never -- curl -s -X POST http://$(MODEL_NAME)-default.$(NAMESPACE):8000/api/v1.0/predictions -H \'Content-Type: application/json\' -d \'{\\\"data\\\": {\\\"ndarray\\\": [[\\\"test sentence 1\\\", \\\"test sentence 2\\\"]]}}\'; Start-Sleep -Milliseconds 100 }"
	@echo "Load test started. Check 'make logs' for results"

#═══════════════════════════════════════════════════════════════════════
# MONITOR - View logs, metrics, and deployment status
#═══════════════════════════════════════════════════════════════════════

.PHONY: logs
logs:
	@echo "Streaming logs from model server..."
	@echo "Press Ctrl+C to stop"
	@kubectl logs -f -l app=$(MODEL_NAME)-default-0-classifier --tail=50

.PHONY: status
status:
	@echo "════════════════════════════════════════════════════════════════"
	@echo "  Deployment Status"
	@echo "════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "SeldonDeployment:"
	@powershell -Command "kubectl get seldondeployment $(MODEL_NAME) -o wide 2>$null || Write-Host \"Not found\""
	@echo ""
	@echo "Pods:"
	@kubectl get pods -l app=$(MODEL_NAME)-default-0-classifier -o wide
	@echo ""
	@echo "Services:"
	@kubectl get svc -l app=$(MODEL_NAME)
	@echo ""
	@echo "To access the model:"
	@echo "  1. Port forward:  make forward"
	@echo "  2. Send request:  make test"

.PHONY: describe
describe:
	@echo "Detailed deployment information:"
	@echo ""
	@echo "═══ SeldonDeployment ═══"
	@kubectl describe seldondeployment $(MODEL_NAME)
	@echo ""
	@echo "═══ Pods ═══"
	@kubectl describe pods -l app=$(MODEL_NAME)-default-0-classifier
	@echo ""
	@echo "═══ Events ═══"
	@powershell -Command "kubectl get events --sort-by=.metadata.creationTimestamp | Select-Object -Last 20"

.PHONY: metrics
metrics:
	@echo "Fetching Prometheus metrics..."
	@kubectl run -it --rm metrics-client --image=curlimages/curl:latest --restart=Never -- powershell -Command "curl -s http://$(MODEL_NAME)-default.$(NAMESPACE):8000/prometheus"

#═══════════════════════════════════════════════════════════════════════
# PORT FORWARDING - Access services from localhost
#═══════════════════════════════════════════════════════════════════════

.PHONY: forward
forward:
	@echo "Forwarding model API to localhost:8000..."
	@echo "You can now send requests to: http://localhost:8000"
	@echo ""
	@echo "Example with curl:"
	@echo '  curl -X POST http://localhost:8000/api/v1.0/predictions \'
	@echo '    -H "Content-Type: application/json" \'
	@echo '    -d '"'"'{"data": {"ndarray": [["sentence 1", "sentence 2"]]}}'"'"
	@echo ""
	@echo "Press Ctrl+C to stop forwarding"
	@kubectl port-forward svc/$(MODEL_NAME)-default 8000:8000

.PHONY: forward-metrics
forward-metrics:
	@echo "Forwarding metrics to localhost:8001..."
	@echo "View metrics at: http://localhost:8001/prometheus"
	@echo "Press Ctrl+C to stop"
	@kubectl port-forward svc/$(MODEL_NAME)-default 8001:8000

#═══════════════════════════════════════════════════════════════════════
# CLEANUP - Remove deployments and cluster
#═══════════════════════════════════════════════════════════════════════

.PHONY: cleanup
cleanup: cleanup-deploy cleanup-cluster
	@echo "v Complete cleanup finished"

.PHONY: cleanup-deploy
cleanup-deploy:
	@echo "Removing deployment and resources..."
	@kubectl delete seldondeployment $(MODEL_NAME) --ignore-not-found=true
	@kubectl delete configmap $(MODEL_NAME)-model --ignore-not-found=true
	@kubectl delete svc $(MODEL_NAME)-external --ignore-not-found=true
	@echo "v Deployment cleaned up"

.PHONY: cleanup-cluster
cleanup-cluster:
	@echo "Deleting Kind cluster '$(CLUSTER_NAME)'..."
	@kind delete cluster --name $(CLUSTER_NAME)
	@echo "v Cluster deleted"

#═══════════════════════════════════════════════════════════════════════
# UTILITY TARGETS
#═══════════════════════════════════════════════════════════════════════

.PHONY: shell
shell:
	@echo "Opening shell in model container..."
	@powershell -Command "$podName = kubectl get pod -l app=$(MODEL_NAME)-default-0-classifier -o jsonpath='{.items[0].metadata.name}'; kubectl exec -it $podName -- /bin/bash"

.PHONY: kubectl-config
kubectl-config:
	@echo "Configuring kubectl context..."
	@kubectl config use-context kind-$(CLUSTER_NAME)
	@echo "v kubectl configured to use Kind cluster"
