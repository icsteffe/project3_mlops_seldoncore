# MLOps: Model Training & Deployment with Seldon Core

This project demonstrates a complete MLOps pipeline for training and deploying a DistilBERT model using:
- **Training**: PyTorch Lightning with Weights & Biases tracking
- **Deployment**: Seldon Core on Kubernetes for production-grade model serving

**Learning Goals:**
1. Understand end-to-end ML deployment workflows
2. Learn how Seldon Core simplifies Kubernetes model serving
3. Compare manual Kubernetes deployment vs. MLOps platforms
4. Implement monitoring and observability for ML systems

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Quick Start (5 Minutes)](#quick-start-5-minutes)
- [Part 1: Model Training](#part-1-model-training)
- [Part 2: Model Deployment with Seldon Core](#part-2-model-deployment-with-seldon-core)
- [Seldon Core vs Vanilla Kubernetes](#seldon-core-vs-vanilla-kubernetes)
- [Pros & Cons of Seldon Core](#pros--cons-of-seldon-core)
- [Monitoring & Observability](#monitoring--observability)
- [Troubleshooting](#troubleshooting)
- [Learning Resources](#learning-resources)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        TRAINING PHASE                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  1. train.py → PyTorch Lightning → W&B Logging                  │
│  2. Save checkpoint (.ckpt file)                                 │
│  3. export_model.py → Extract model weights                      │
│                                                                   │
│  Output: exported_model/                                         │
│    ├── model.pt           (trained weights)                      │
│    ├── config.json        (model architecture)                   │
│    ├── tokenizer/         (text preprocessing)                   │
│    └── metadata.txt       (training info)                        │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                      DEPLOYMENT PHASE                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────┐                                            │
│  │  Kubernetes     │                                            │
│  │  (Kind cluster) │                                            │
│  └────────┬────────┘                                            │
│           │                                                      │
│  ┌────────▼──────────────────────────────────────────┐         │
│  │  Seldon Core Operator (watches for resources)     │         │
│  └────────┬──────────────────────────────────────────┘         │
│           │                                                      │
│           │ Creates                                              │
│           ▼                                                      │
│  ┌─────────────────────────────────────────────────┐           │
│  │  SeldonDeployment (CRD)                         │           │
│  │  - Name: distilbert-classifier                  │           │
│  │  - Model: exported_model/                       │           │
│  │  - Replicas: 1                                  │           │
│  └────────┬────────────────────────────────────────┘           │
│           │                                                      │
│           │ Automatically Creates                                │
│           ▼                                                      │
│  ┌──────────────────────────────────────────────────┐          │
│  │  Pod: Model Server Container                     │          │
│  │  ┌────────────────────────────────────────────┐ │          │
│  │  │  - Loads model from ConfigMap              │ │          │
│  │  │  - Starts REST API (port 5000)             │ │          │
│  │  │  - Exposes /predict endpoint               │ │          │
│  │  │  - Exposes /health endpoint                │ │          │
│  │  │  - Exposes /prometheus metrics             │ │          │
│  │  └────────────────────────────────────────────┘ │          │
│  └────────┬─────────────────────────────────────────┘          │
│           │                                                      │
│           ▼                                                      │
│  ┌──────────────────────────────────────────────────┐          │
│  │  Kubernetes Service                              │          │
│  │  - Exposes model API                             │          │
│  │  - Load balances requests                        │          │
│  └────────┬─────────────────────────────────────────┘          │
│           │                                                      │
│           ▼                                                      │
│     Inference Requests                                           │
│     POST /api/v1.0/predictions                                  │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

**Key Insight**: Seldon Core abstracts away the complexity of manually creating Deployments, Services, ConfigMaps, and monitoring infrastructure. You just define a `SeldonDeployment` resource!

---

## Quick Start (5 Minutes)

Get a working model deployment in 5 minutes:

```bash
# 1. Install prerequisites (Docker, kubectl, kind, helm)
make setup

# 2. Train a model (optional - skip if you have a checkpoint)
docker compose up --build

# 3. Export the trained model
python export_model.py --checkpoint models/your-checkpoint.ckpt

# 4. Build inference container
make build-image

# 5. Deploy to Kubernetes
make deploy

# 6. Test the deployment
make test

# 7. View logs and metrics
make logs
make metrics
```

That's it! You now have a production-grade model serving infrastructure.

---

## Part 1: Model Training

### Prerequisites

- **Git**
- **Docker**: [Install Docker Desktop](https://www.docker.com/products/docker-desktop/)
- **Weights & Biases Account**: [Sign up](https://wandb.ai/) and get your [API key](https://wandb.ai/authorize)

### Setup Environment Variables

```bash
# Copy example env file
cp .env.example .env

# Edit .env and add your W&B API key
WANDB_API_KEY=your_wandb_api_key_here
```

### Train the Model

#### Option 1: Using Docker (Recommended)

```bash
# Train with default hyperparameters
docker compose up --build

# Train with custom hyperparameters
docker compose run --rm train \
  --wandb-project my-project \
  --batch-size 16 \
  --learning-rate 5e-5 \
  --optimizer AdamW
```

#### Option 2: Run Locally

```bash
# Install dependencies
uv sync --extra cpu  # or --extra cu129 for GPU

# Run training
python train.py --wandb-project my-project
```

### Training Configuration Options

| Argument | Type | Description |
|----------|------|-------------|
| `--wandb-project` | string | **Required.** W&B project name |
| `--checkpoint-dir` | string | Directory for model checkpoints (default: `models`) |
| `--batch-size` | int | Training batch size |
| `--learning-rate` | float | Optimizer learning rate |
| `--warmup-steps` | int | LR warmup steps |
| `--weight-decay` | float | L2 regularization |
| `--optimizer` | choice | AdamW, Adam, NAdam, or SGD |

See `python train.py --help` for all options.

### Export Trained Model

After training, export the model for deployment:

```bash
python export_model.py \
  --checkpoint models/your-checkpoint.ckpt \
  --output-dir exported_model
```

This creates:
```
exported_model/
├── model.pt         # Trained weights (PyTorch state dict)
├── config.json      # Model architecture config
├── tokenizer/       # Tokenizer files for text preprocessing
└── metadata.txt     # Training metadata
```

---

## Part 2: Model Deployment with Seldon Core

### Prerequisites for Deployment

Ensure you have the following installed:

| Tool | Purpose | Installation Link |
|------|---------|-------------------|
| **Docker** | Container runtime | [docker.com](https://docs.docker.com/get-docker/) |
| **kubectl** | Kubernetes CLI | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| **kind** | Local Kubernetes | [kind.sigs.k8s.io](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| **helm** | K8s package manager | [helm.sh](https://helm.sh/docs/intro/install/) |

**Quick Install (macOS/Linux):**
```bash
# macOS (using Homebrew)
brew install docker kubectl kind helm

# Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
```

### Step-by-Step Deployment Guide

#### Step 1: Setup Local Kubernetes Cluster

```bash
# Create Kind cluster + Install Seldon Core
make setup
```

This command:
1. Creates a Kubernetes cluster using Kind
2. Installs Seldon Core v1.17.1 operator
3. Waits for all components to be ready

**What's happening under the hood?**
- Kind creates a Docker container running Kubernetes
- Helm installs Seldon Core's Custom Resource Definitions (CRDs)
- Seldon Operator starts watching for `SeldonDeployment` resources

#### Step 2: Build Inference Container

```bash
make build-image
```

This:
1. Builds Docker image with:
   - Seldon Core Python runtime
   - Your custom `Model.py` class
   - Dependencies (transformers, pytorch, etc.)
2. Loads image into Kind cluster

**Why a custom image?**
- Seldon needs to know how to load YOUR specific model
- The `Model.py` class implements `predict()` method
- Seldon wraps this into a REST/gRPC microservice automatically

#### Step 3: Deploy Model to Kubernetes

```bash
make deploy
```

This:
1. Creates a ConfigMap with your model files
2. Applies the `SeldonDeployment` manifest
3. Waits for pods to be ready
4. Shows deployment status

**What Seldon Creates:**
- **Deployment**: Runs your model container
- **Service**: Exposes REST API endpoints
- **ConfigMap**: Stores model weights/config
- **ServiceMonitor**: Prometheus metrics scraping

#### Step 4: Test the Deployment

```bash
# Send test prediction requests
make test

# Check health status
make test-health

# View real-time logs
make logs

# View Prometheus metrics
make metrics
```

#### Step 5: Access from Your Machine

```bash
# Option 1: Port forwarding
make forward
# Now accessible at http://localhost:8000

# Option 2: Send request through kubectl
curl -X POST http://localhost:8000/api/v1.0/predictions \
  -H 'Content-Type: application/json' \
  -d '{
    "data": {
      "ndarray": [
        ["The cat sat on the mat", "A cat was sitting on a mat"]
      ]
    }
  }'
```

**Response format:**
```json
{
  "data": {
    "ndarray": [[0.12, 0.88]]  // Class probabilities [not_paraphrase, paraphrase]
  },
  "meta": {}
}
```

---

## Seldon Core vs Vanilla Kubernetes

### What Problems Does Seldon Core Solve?

| Aspect | Vanilla Kubernetes | With Seldon Core | What Seldon Eliminates |
|--------|-------------------|------------------|------------------------|
| **Deployment** | Write Deployment YAML (50-100 lines)<br>- Container spec<br>- Volumes for model<br>- Resource limits<br>- Health checks | `SeldonDeployment` (20 lines)<br>- Specify model location<br>- Seldon handles the rest | ✅ 80% less YAML<br>✅ No container orchestration |
| **Service Exposure** | Manually create:<br>- Service<br>- Ingress rules<br>- Load balancer config | Automatic Service creation<br>- Built-in load balancing | ✅ No networking config |
| **API Layer** | Write REST API code:<br>- Flask/FastAPI routes<br>- Request parsing<br>- Response formatting | Automatic REST/gRPC<br>- Standard V1 protocol | ✅ No API code needed |
| **Monitoring** | Implement:<br>- Prometheus client<br>- Custom metrics<br>- `/metrics` endpoint | Auto-exposed metrics:<br>- Request latency<br>- Throughput<br>- Error rates | ✅ No instrumentation code |
| **Health Checks** | Configure:<br>- Liveness probes<br>- Readiness probes<br>- Custom health endpoints | Automatic `/health` endpoints<br>- Model-aware checks | ✅ No health check code |
| **Scaling** | Configure HPA:<br>- Define metrics<br>- Set thresholds<br>- Tune parameters | Built-in autoscaling<br>- Request-based scaling | ✅ Simplified scaling |
| **A/B Testing** | Implement:<br>- Traffic splitting logic<br>- Multiple deployments<br>- Custom routing | Multi-predictor config:<br>- Traffic percentages<br>- Automatic routing | ✅ No routing logic |
| **Model Updates** | Manual process:<br>- Build new image<br>- Update deployment<br>- Rolling restart | Update `modelUri`<br>- Automatic reload | ✅ Zero-downtime updates |

### Code Comparison Example

<details>
<summary><b>Vanilla Kubernetes Approach (Click to expand)</b></summary>

You'd need to write:

**1. API Server Code (`app.py`):**
```python
from flask import Flask, request, jsonify
from prometheus_client import Counter, Histogram, generate_latest
import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification

app = Flask(__name__)

# Load model (30+ lines of code)
model = AutoModelForSequenceClassification.from_pretrained("...")
tokenizer = AutoTokenizer.from_pretrained("...")

# Monitoring metrics
REQUEST_COUNT = Counter('model_requests_total', 'Total requests')
REQUEST_LATENCY = Histogram('model_request_duration_seconds', 'Request latency')

@app.route('/predict', methods=['POST'])
@REQUEST_LATENCY.time()
def predict():
    REQUEST_COUNT.inc()
    data = request.json
    # Parse input, tokenize, run inference, format output (20+ lines)
    ...

@app.route('/health')
def health():
    return jsonify({"status": "ok"})

@app.route('/metrics')
def metrics():
    return generate_latest()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

**2. Dockerfile:**
```dockerfile
FROM python:3.9
COPY app.py /app/
RUN pip install flask torch transformers prometheus_client
CMD ["python", "app.py"]
```

**3. Kubernetes Deployment (`deployment.yaml` - 100+ lines):**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: model-server
spec:
  replicas: 2
  selector:
    matchLabels:
      app: model-server
  template:
    metadata:
      labels:
        app: model-server
    spec:
      containers:
      - name: model
        image: myregistry/model-server:v1
        ports:
        - containerPort: 5000
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 20
          periodSeconds: 5
        volumeMounts:
        - name: model-storage
          mountPath: /models
      volumes:
      - name: model-storage
        persistentVolumeClaim:
          claimName: model-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: model-server
spec:
  selector:
    app: model-server
  ports:
  - port: 80
    targetPort: 5000
---
apiVersion: v1
kind: ServiceMonitor
metadata:
  name: model-server
spec:
  selector:
    matchLabels:
      app: model-server
  endpoints:
  - port: 5000
    path: /metrics
```

**Total: ~200 lines of code + ongoing maintenance**

</details>

<details>
<summary><b>Seldon Core Approach (Click to expand)</b></summary>

**1. Model Class (`Model.py`):**
```python
import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification

class Model:
    def __init__(self):
        self.model = AutoModelForSequenceClassification.from_pretrained("/mnt/model")
        self.tokenizer = AutoTokenizer.from_pretrained("/mnt/model/tokenizer")

    def predict(self, X):
        encoded = self.tokenizer(X, return_tensors='pt', padding=True)
        outputs = self.model(**encoded)
        return outputs.logits.softmax(dim=-1).numpy()
```

**2. SeldonDeployment (`seldon-deployment.yaml` - 50 lines):**
```yaml
apiVersion: machinelearning.seldon.io/v1
kind: SeldonDeployment
metadata:
  name: model-server
spec:
  predictors:
  - name: default
    graph:
      name: classifier
      type: MODEL
    componentSpecs:
    - spec:
        containers:
        - name: classifier
          image: seldonio/seldon-core-s2i-python39:1.17.1
          resources:
            requests:
              memory: "512Mi"
              cpu: "500m"
    replicas: 2
```

**Total: ~50 lines - Seldon handles the rest!**

</details>

### Time Investment Comparison

| Task | Vanilla K8s | Seldon Core | Time Saved |
|------|-------------|-------------|------------|
| Initial setup | 4-8 hours | 30 minutes | 75-90% |
| Adding monitoring | 2-4 hours | 0 (built-in) | 100% |
| Implementing health checks | 1-2 hours | 0 (built-in) | 100% |
| Adding A/B testing | 4-6 hours | 15 minutes | 95% |
| **Total** | **11-20 hours** | **~1 hour** | **90%+** |

---

## Pros & Cons of Seldon Core

### Pros ✅

| Benefit | Why It Matters | Example |
|---------|----------------|---------|
| **Rapid Deployment** | Get models to production in hours, not days | Initial deployment: 1 hour vs 8+ hours manually |
| **Reduced Boilerplate** | Focus on model logic, not infrastructure | No Flask/FastAPI code needed |
| **Built-in Monitoring** | Production-ready observability out of the box | Prometheus metrics automatic |
| **Standard API** | Consistent prediction interface across models | All models use V1 protocol |
| **Advanced Patterns** | A/B testing, canary deployments, multi-model serving | Traffic splitting with config change |
| **Kubernetes Native** | Fits naturally into cloud-native workflows | Uses standard K8s patterns (CRDs, operators) |
| **Active Community** | Well-documented, maintained by Seldon team | Regular updates, extensive examples |

### Cons ❌

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| **Learning Curve** | Need to understand Seldon concepts (predictors, graphs, etc.) | ~2-3 hours to grasp basics |
| **Abstraction Overhead** | Less control over underlying infrastructure | Can customize via `componentSpecs` |
| **Debugging Complexity** | Errors can be buried in Seldon's abstractions | Use `kubectl logs` and Seldon's debug mode |
| **Resource Usage** | Seldon operator adds overhead (~100-200MB) | Negligible for most use cases |
| **Version Lock-in** | Tied to Seldon's release cycle | Can extend with custom components |
| **Licensing** | v1.18+ uses BSL (production requires license) | Use v1.17.1 (Apache 2.0) for learning |
| **Overkill for Simple Cases** | For a single model, vanilla K8s might suffice | Trade-off: simplicity vs future flexibility |

### When to Use Seldon Core

**✅ Good Fit:**
- Multiple models to deploy
- Need monitoring/observability
- Want A/B testing or canaries
- Rapid iteration required
- Team lacks K8s expertise

**❌ Not Ideal:**
- Single simple model
- Have custom infrastructure already
- Need extreme performance optimization
- Want full control over every detail

---

## Monitoring & Observability

See [monitoring/README.md](monitoring/README.md) for detailed monitoring documentation.

### Quick Metrics Access

```bash
# View Prometheus metrics
make metrics

# Access Grafana (if installed)
make forward-metrics
open http://localhost:8001/prometheus
```

### Key Metrics to Monitor

1. **Request Latency** (p50, p95, p99)
   - Target: <100ms for most applications
2. **Throughput** (requests/second)
3. **Error Rate** (4xx, 5xx errors)
   - Target: <1%
4. **Resource Usage** (CPU, memory)

---

## Troubleshooting

### Common Issues

<details>
<summary><b>Deployment stuck in "Pending"</b></summary>

**Symptom:** Pod never starts

```bash
# Check pod status
kubectl get pods -l app=distilbert-classifier-default-0-classifier

# View events
kubectl describe pod <pod-name>
```

**Common causes:**
- Image not loaded into Kind: `make build-image`
- Insufficient resources: Check `kubectl top nodes`
- ConfigMap missing: `kubectl get configmap`

</details>

<details>
<summary><b>Prediction errors (500)</b></summary>

**Symptom:** API returns errors

```bash
# View logs
make logs

# Common issues:
# - Model files not mounted correctly
# - Missing dependencies
# - OOM (out of memory)
```

**Fix:**
```bash
# Check model ConfigMap
kubectl describe configmap distilbert-classifier-model

# Increase memory limits in seldon-deployment.yaml
resources:
  limits:
    memory: "4Gi"  # Increase from 2Gi
```

</details>

<details>
<summary><b>Seldon Operator not found</b></summary>

```bash
# Verify Seldon is installed
kubectl get pods -n seldon-system

# Reinstall if needed
make install-seldon
```

</details>

### Getting Help

```bash
# View deployment status
make status

# Detailed debugging info
make describe

# Check all resources
kubectl get all -l app=distilbert-classifier
```

---

## Project Structure

```
project3_mlops/
├── train.py                    # PyTorch Lightning training script
├── export_model.py            # Export trained model for deployment
├── Makefile                   # Automation commands
├── kind-config.yaml           # Local K8s cluster config
├── README.md                  # This file
│
├── model-serving/             # Inference server
│   ├── Model.py              # Custom Seldon model class
│   ├── Dockerfile            # Container image for serving
│   └── requirements.txt      # Serving dependencies
│
├── k8s/                       # Kubernetes manifests
│   └── seldon-deployment.yaml # SeldonDeployment CRD
│
├── monitoring/                # Monitoring configs
│   └── README.md             # Monitoring guide
│
└── src/                       # Training code
    ├── glue_data_module.py   # Data loading
    └── glue_transformer.py   # Model architecture
```

---

## Makefile Commands Reference

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make setup` | Complete local K8s setup |
| `make build-image` | Build inference Docker image |
| `make deploy` | Deploy model to Kubernetes |
| `make test` | Send test prediction requests |
| `make logs` | View model server logs |
| `make status` | Check deployment status |
| `make metrics` | View Prometheus metrics |
| `make forward` | Port forward API (localhost:8000) |
| `make cleanup` | Remove everything |

---

## Learning Resources

### Seldon Core Documentation
- [Official Docs](https://docs.seldon.io/projects/seldon-core/en/v1.17.0/)
- [Python Model Serving](https://docs.seldon.io/projects/seldon-core/en/v1.17.0/python/python_component.html)
- [Examples Repository](https://github.com/SeldonIO/seldon-core-examples)

### Kubernetes & MLOps
- [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Prometheus Monitoring](https://prometheus.io/docs/introduction/overview/)

### Model Serving Alternatives
- [KServe](https://kserve.github.io/website/) - Serverless inference
- [BentoML](https://www.bentoml.com/) - Model serving framework
- [TorchServe](https://pytorch.org/serve/) - PyTorch-specific

---

## License Note

This project uses **Seldon Core v1.17.1** (Apache 2.0 License - fully open source).

**Important:** Seldon Core versions after v1.17.1 use the Business Source License (BSL), which restricts production use without a commercial license. For educational purposes, this is not an issue.

---

## Contributing

This is an educational project. Suggestions and improvements welcome!

---

## Acknowledgments

- **Seldon Team** for building amazing MLOps tools
- **PyTorch Lightning** for simplified training
- **Weights & Biases** for experiment tracking
- **Hugging Face** for transformers library

---

**Next Steps:**
1. ✅ Train a model
2. ✅ Export and deploy with Seldon
3. 🎯 Try A/B testing with two models
4. 🎯 Add request logging
5. 🎯 Implement canary deployments

Happy learning! 🚀
