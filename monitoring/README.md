# Monitoring with Seldon Core

This directory contains monitoring configuration for Seldon Core deployments.

## What Monitoring Does Seldon Core Provide?

Seldon Core automatically provides **built-in monitoring** without requiring custom instrumentation:

### 1. **Prometheus Metrics** (Automatic)

Every Seldon deployment automatically exposes metrics at `/prometheus` endpoint:

- **Request metrics**:
  - `seldon_api_executor_client_requests_seconds` - Request latency
  - `seldon_api_executor_server_requests_seconds` - Server processing time
  - Total requests, failed requests, request rates

- **Model performance**:
  - Prediction counts per model
  - Input/output data statistics
  - Error rates by model

- **Infrastructure metrics**:
  - CPU usage
  - Memory usage
  - Pod restarts
  - Container health

**Key Benefit**: You get these metrics without writing any monitoring code!

### 2. **Request/Response Logging** (Optional)

Seldon can log all predictions for:
- Debugging model issues
- Compliance and auditing
- Building datasets for retraining

### 3. **Data Drift Detection** (Advanced)

With Seldon's Alibi Detect integration, you can:
- Monitor for changes in input data distribution
- Detect concept drift in production
- Trigger alerts when model performance degrades

---

## Comparison: Seldon Core vs Manual Monitoring

| Aspect | Manual Implementation | With Seldon Core |
|--------|----------------------|------------------|
| **Metrics Collection** | Write Prometheus client code in your app | Automatic - no code needed |
| **Metric Endpoints** | Configure `/metrics` endpoint manually | Auto-exposed at `/prometheus` |
| **Request Logging** | Implement logging middleware | Built-in logger component |
| **Dashboards** | Build from scratch | Pre-built Grafana dashboards |
| **Setup Time** | Hours to days | Minutes |
| **Code Maintenance** | Need to update monitoring code | Maintained by Seldon team |

**Example**: To add request latency monitoring manually:
```python
# Manual approach (without Seldon)
from prometheus_client import Histogram
import time

REQUEST_TIME = Histogram('request_duration_seconds', 'Request duration')

@app.route('/predict')
@REQUEST_TIME.time()
def predict():
    # ... your code ...
```

**With Seldon**: This is automatic - no code needed!

---

## Quick Start: View Metrics

### Option 1: Direct Metrics Access

```bash
# Forward the Seldon service port
kubectl port-forward svc/distilbert-classifier-default 8000:8000

# View Prometheus metrics
curl http://localhost:8000/prometheus
```

You'll see output like:
```
# HELP seldon_api_executor_client_requests_seconds Help
# TYPE seldon_api_executor_client_requests_seconds histogram
seldon_api_executor_client_requests_seconds_bucket{deployment_name="distilbert-classifier",le="0.005",} 42.0
seldon_api_executor_client_requests_seconds_sum{deployment_name="distilbert-classifier",} 1.23
seldon_api_executor_client_requests_seconds_count{deployment_name="distilbert-classifier",} 100.0
```

### Option 2: Install Prometheus & Grafana (Full Monitoring Stack)

For a complete monitoring setup:

```bash
# Install Prometheus (collects metrics)
kubectl create namespace monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# Seldon automatically creates ServiceMonitor resources
# Prometheus will auto-discover them!

# Access Grafana dashboard
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Login: admin / prom-operator
# Import Seldon's pre-built dashboard (ID: 10839)
```

---

## What Metrics Should You Monitor?

For a production ML system, focus on:

1. **Latency**: How fast are predictions?
   - p50, p95, p99 latencies
   - Target: <100ms for most applications

2. **Throughput**: How many requests/second?
   - Monitor peak traffic patterns
   - Scale replicas based on load

3. **Error Rate**: What percentage of requests fail?
   - 4xx errors (bad input)
   - 5xx errors (model/server issues)
   - Target: <1% error rate

4. **Resource Usage**: Is the model over/under-provisioned?
   - CPU and memory utilization
   - If consistently >80%, increase resources
   - If consistently <30%, decrease to save costs

---

## Why Not Use Custom Dashboards?

For this learning project, we keep monitoring simple:
- Focus on understanding Seldon's built-in capabilities
- Avoid complexity of maintaining custom dashboards
- Learn what metrics matter before building custom views

**In production**: You'd create custom Grafana dashboards tailored to your specific needs.

---

## Optional: Enable Request Logging

To log all predictions (useful for debugging):

```yaml
# Add to your SeldonDeployment manifest
apiVersion: machinelearning.seldon.io/v1
kind: SeldonDeployment
metadata:
  name: distilbert-classifier
spec:
  predictors:
    - name: default
      # Enable request logging
      logger:
        mode: all  # Log requests and responses
        url: http://logger-service:8080  # Where to send logs
```

**Use Cases**:
- Debugging production issues
- Compliance (e.g., GDPR requires logging)
- Building datasets for model retraining
- Analyzing user behavior

**Warning**: Logging all predictions can generate large amounts of data!

---

## Learning Resources

- [Seldon Core Metrics Documentation](https://docs.seldon.io/projects/seldon-core/en/v1.17.0/analytics/analytics.html)
- [Grafana Dashboard #10839](https://grafana.com/grafana/dashboards/10839) - Pre-built Seldon dashboard
- [Prometheus Query Examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)

---

## Summary

**What Seldon Monitoring Gives You:**
✅ Automatic Prometheus metrics (no code needed)
✅ Pre-configured health checks
✅ Optional request/response logging
✅ Compatible with standard Kubernetes monitoring stacks
✅ Pre-built Grafana dashboards available

**What You'd Need to Build Manually:**
❌ Prometheus client integration
❌ Custom metric definitions
❌ Health check endpoints
❌ Logging middleware
❌ Dashboard creation
❌ Metric aggregation logic

**Time Saved**: 4-8 hours of development + ongoing maintenance
