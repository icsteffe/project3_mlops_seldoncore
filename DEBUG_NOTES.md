# Prediction Request Debugging Notes

## Current Status
- **Pod Status**: Running and Ready (2/2 containers)
- **Containers**: Both `classifier` and `seldon-container-engine` are running
- **Model Loading**: ✅ Model loads successfully in classifier container
- **Health Probes**: ✅ Health endpoints (`/health/ping`, `/health/status`) work when tested inside pod
- **Services**: All Kubernetes services created successfully

## Issues Found & Fixed

### 1. External Service Misconfiguration ✅ FIXED
**Problem**: External NodePort service had wrong `targetPort`
- **Was**: `targetPort: 9000` (pointing directly to classifier)
- **Fixed**: `targetPort: 8000` (now points to seldon-container-engine)
- **File**: `k8s/seldon-deployment.yaml:159`

### 2. Initial Pod Readiness Issues ✅ RESOLVED
**Problem**: Classifier container was failing liveness/readiness probes
- Exit code 137 suggested potential OOM issues
- Container was restarting repeatedly (3+ restarts)
- **Resolved**: Pod eventually stabilized and became 2/2 Ready

## Current Problem: Prediction Requests Timeout

### Symptoms
1. ❌ Requests via NodePort (localhost:8080) timeout after 30+ seconds
2. ❌ Requests from inside cluster to service DNS name fail immediately
3. ❌ Direct requests to pod IP (10.244.0.16:8000) timeout
4. ❌ Even with curl showing data upload (100 67 bytes), no response received

### Service Configuration
```yaml
# External Service (NodePort)
Name: distilbert-classifier-external
Type: NodePort
Selector: seldon-app=distilbert-classifier-default
Port: 8000 -> TargetPort: 8000 -> NodePort: 30080
Endpoints: 10.244.0.16:8000 ✅ (correctly populated)

# Internal Service (Seldon-managed)
Name: distilbert-classifier-default
Type: ClusterIP
Port: 8000 -> TargetPort: 8000
```

### Port Mapping (Kind Cluster)
```
Kind cluster: mlops-seldon
Docker port mapping: 0.0.0.0:8080 -> 30080/tcp
Access from host: localhost:8080 -> NodePort 30080 -> Service 8000 -> Pod 8000
```

### Container Architecture
```
Pod: distilbert-classifier-default-0-classifier-6c84695df8-ghq5k
├── Container: classifier
│   ├── Port 9000: Model inference server (Python/Seldon wrapper)
│   ├── Port 9500: gRPC
│   └── Port 6000: Metrics
└── Container: seldon-container-engine
    ├── Port 8000: REST API (main entry point)
    └── Port 5001: gRPC

Request flow should be:
  External -> Port 8000 (engine) -> Port 9000 (classifier) -> Model
```

### Logs Analysis

**seldon-container-engine** (last startup):
```
{"level":"info","msg":"Running http server","port":8000}
{"level":"info","msg":"Listening","Address":"0.0.0.0:8000"}
{"level":"info","msg":"http server started"}
```
✅ Engine starts successfully and listens on port 8000

**classifier** (last startup):
```
INFO: Initializing DistilBERT model for inference...
INFO: Loading model from: /app/exported_model
INFO: Loaded config: 2 labels
INFO: Loaded tokenizer with vocab size: 30522
INFO: Model loaded successfully on device: cpu
INFO: ✓ Model initialization complete
INFO: REST gunicorn microservice running on port 9000
```
✅ Classifier starts successfully and listens on port 9000

### Test Requests Attempted
1. `curl http://localhost:8080/api/v1.0/predictions` - ❌ Timeout
2. `curl http://distilbert-classifier-default.default:8000/api/v1.0/predictions` (from pod) - ❌ Connection refused
3. `curl http://10.244.0.16:8000/api/v1.0/predictions` (direct pod IP) - ❌ Timeout
4. Health check from inside classifier container: `curl http://localhost:9000/health/ping` - ✅ Works (returns "pong")

### Request Format Used
```json
POST /api/v1.0/predictions
Content-Type: application/json
{
  "data": {
    "ndarray": [["The movie was great", "I loved it"]]
  }
}
```

## Hypotheses for Tomorrow's Debugging

### High Priority
1. **Seldon-container-engine routing issue**: Engine might not be correctly configured to route to classifier on port 9000
   - Check: `PREDICTIVE_UNIT_HTTP_SERVICE_PORT` env var (should be 9000)
   - Check: Engine's predictor graph configuration

2. **Network connectivity between containers**: Containers might not be able to communicate within pod
   - Test: Exec into engine container and curl localhost:9000 directly
   - Test: Check if both containers share network namespace

3. **Request timeout in model inference**: Model might be hanging during prediction
   - Test: Check classifier logs during a request attempt
   - Test: Verify model files are complete and not corrupted

### Medium Priority
4. **Network policies**: Cluster might have network policies blocking traffic
   - Check: `kubectl get networkpolicies`
   - Check: Kind cluster CNI configuration

5. **Wrong API endpoint or request format**: Seldon might expect different format
   - Test: Try V2 protocol endpoint
   - Test: Simpler request format without nested arrays

### Low Priority
6. **Resource exhaustion**: Container running out of memory during inference
   - Check: `kubectl top pod` (if metrics-server installed)
   - Check: Increase memory limits

7. **Kubernetes DNS issues**: Service discovery failing
   - Test: `nslookup distilbert-classifier-default` from test pod
   - Check: CoreDNS logs

## Files Modified
- `k8s/seldon-deployment.yaml` - Fixed external service targetPort (9000 -> 8000)

## Next Steps for Debugging

### Immediate Actions
1. Check seldon-container-engine can reach classifier:
   ```bash
   kubectl exec POD_NAME -c seldon-container-engine -- wget -O- http://localhost:9000/health/ping
   ```

2. Monitor both container logs simultaneously during request:
   ```bash
   kubectl logs POD_NAME -c classifier -f &
   kubectl logs POD_NAME -c seldon-container-engine -f &
   # Then make request
   ```

3. Check environment variables in engine container:
   ```bash
   kubectl exec POD_NAME -c seldon-container-engine -- env | grep -E 'PORT|HOST|PREDICT'
   ```

4. Verify the predictor graph configuration:
   ```bash
   kubectl exec POD_NAME -c seldon-container-engine -- env | grep ENGINE_PREDICTOR | base64 -d | python -m json.tool
   ```

5. Test direct classifier endpoint (bypassing engine):
   ```bash
   kubectl port-forward POD_NAME 9001:9000
   curl -X POST http://localhost:9001/predict -H "Content-Type: application/json" -d '{"data": {"ndarray": [["test", "test"]]}}'
   ```

### Alternative Endpoints to Try
- `/predict` (direct Seldon Python wrapper endpoint)
- `/api/v1.0/doc` (API documentation)
- `/seldon/default/distilbert-classifier/api/v1.0/predictions` (full path)

## Environment Info
- Cluster: Kind cluster `mlops-seldon`
- Platform: Windows (desktop-linux context)
- Seldon Core: v1.17.1
- Model: DistilBERT text classifier (2 labels)
- Model location: `/app/exported_model` (embedded in Docker image)
