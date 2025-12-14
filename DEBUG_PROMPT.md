# Debug Prompt for Tomorrow

## Quick Context
We have a Seldon Core deployment running in a Kind cluster. The pod is healthy (2/2 Ready), model loads successfully, health checks pass, but **all prediction requests timeout**. We've already fixed the external service targetPort issue (was 9000, now 8000).

## Ideal Prompt to Continue Debugging

```
I need help debugging why prediction requests are timing out in my Seldon Core deployment.

CURRENT STATE:
- Pod: distilbert-classifier-default-0-classifier-6c84695df8-ghq5k (2/2 Running, Ready)
- Both containers (classifier + seldon-container-engine) start successfully
- Model loads correctly in classifier container (logs confirm)
- Health checks work: /health/ping returns "pong" when tested inside pod
- Service endpoints are correctly populated: 10.244.0.16:8000
- External service fixed: targetPort changed from 9000 to 8000

PROBLEM:
All prediction requests timeout (30+ seconds), including:
- External requests via NodePort (localhost:8080)
- Requests from inside cluster to service DNS
- Direct requests to pod IP (10.244.0.16:8000)

NEXT DEBUGGING STEPS:
1. Check if seldon-container-engine (port 8000) can communicate with classifier (port 9000) within the pod
2. Monitor both container logs simultaneously while making a request
3. Try accessing the classifier directly on port 9000 (bypassing the engine)
4. Verify the ENGINE_PREDICTOR configuration is correct
5. Test alternative endpoints like /predict instead of /api/v1.0/predictions

Please start by checking inter-container communication within the pod, then monitor logs during a request attempt. See DEBUG_NOTES.md for detailed findings.
```

## Quick Commands Reference

### Get current pod name
```bash
kubectl get pods -l seldon-app=distilbert-classifier-default -o name
```

### Test inter-container communication
```bash
POD_NAME=$(kubectl get pods -l seldon-app=distilbert-classifier-default -o jsonpath='{.items[0].metadata.name}')

# Test if engine can reach classifier
kubectl exec $POD_NAME -c seldon-container-engine -- sh -c "wget -O- http://localhost:9000/health/ping 2>&1"
```

### Monitor both logs during request
```bash
POD_NAME=$(kubectl get pods -l seldon-app=distilbert-classifier-default -o jsonpath='{.items[0].metadata.name}')

# Terminal 1: Watch classifier logs
kubectl logs $POD_NAME -c classifier -f

# Terminal 2: Watch engine logs
kubectl logs $POD_NAME -c seldon-container-engine -f

# Terminal 3: Make request
curl -X POST http://localhost:8080/api/v1.0/predictions \
  -H "Content-Type: application/json" \
  -d '{"data": {"ndarray": [["test sentence", "another test"]]}}'
```

### Port-forward to classifier directly
```bash
POD_NAME=$(kubectl get pods -l seldon-app=distilbert-classifier-default -o jsonpath='{.items[0].metadata.name}')

kubectl port-forward $POD_NAME 9001:9000

# Then test
curl -X POST http://localhost:9001/predict \
  -H "Content-Type: application/json" \
  -d '{"data": {"ndarray": [["test", "test"]]}}'
```

### Check engine configuration
```bash
POD_NAME=$(kubectl get pods -l seldon-app=distilbert-classifier-default -o jsonpath='{.items[0].metadata.name}')

kubectl exec $POD_NAME -c seldon-container-engine -- env | grep -E 'PORT|PREDICT|ENGINE'
```
