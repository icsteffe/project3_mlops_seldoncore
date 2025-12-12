# Quick Start Guide: Seldon Core Model Deployment

This guide gets you from zero to deployed model in **under 10 minutes**.

---

## Prerequisites Check

Before starting, verify you have these tools installed:

```bash
# Check if tools are installed
docker --version          # Should show v20+
kubectl version --client  # Should show v1.24+
kind version              # Should show v0.17+
helm version              # Should show v3+
python --version          # Should show 3.12+
uv --version              # Should show v0.1+
```

**Don't have them?** Follow the detailed Windows installation instructions in [README.md#windows-setup](README.md#windows-setup).

---

## Step 1: Setup (2 minutes)

Create the local Kubernetes cluster and install Seldon Core:

```bash
make setup
```

**What this does:**
- Creates Kind cluster (Kubernetes in Docker)
- Installs Seldon Core v1.17.1
- Waits for all components to be ready

**Expected output:**
```
✓ All prerequisites installed
✓ Cluster created
✓ Seldon Core installed
✓ Seldon Core is ready
```

---

## Step 2: Train Model (Optional - 5-10 minutes)

If you don't have a trained checkpoint, train one now:

```bash
# Create .env file with your W&B API key
cp .env.example .env
# Edit .env and add: WANDB_API_KEY=your_key

# Train model (runs for 3 epochs)
docker compose up --build
```

**Or skip this step** if you already have a `.ckpt` checkpoint file.

---

## Step 2.5: Install Python Dependencies (1 minute)

If running locally (not in Docker) or exporting a model, install Python dependencies:

```bash
# Activate your Python virtual environment first
.\venv\Scripts\Activate.ps1

# Then install dependencies
uv sync --extra cpu  # or --extra cu129 for GPU
```

---

## Step 3: Export Model (30 seconds)

Convert your checkpoint to deployment format:

```bash
python export_model.py --checkpoint models/your-checkpoint.ckpt --output-dir exported_model
```

**What this creates:**
```
exported_model/
├── model.pt         # Trained weights
├── config.json      # Model architecture
├── tokenizer/       # Text preprocessing
└── metadata.txt     # Training info
```

---

## Step 4: Build Inference Image (1-2 minutes)

Create the Docker container that will serve predictions:

```bash
make build-image
```

**What this does:**
- Builds Docker image with Seldon runtime + your model code
- Loads image into Kind cluster

---

## Step 5: Deploy to Kubernetes (30 seconds)

Deploy your model with one command:

```bash
make deploy
```

**What happens:**
- Creates ConfigMap with model files
- Applies SeldonDeployment manifest
- Starts model server pod
- Exposes REST API endpoint

**Wait for ready status:**
```
✓ Model files uploaded as ConfigMap
✓ SeldonDeployment created
✓ Deployment complete!
```

---

## Step 6: Test It Works (30 seconds)

Send a test prediction:

```bash
make test
```

**Expected response:**
```json
{
  "data": {
    "ndarray": [[0.12, 0.88]]
  }
}
```

The numbers are class probabilities: `[not_paraphrase, paraphrase]`

---

## Step 7: Explore

### View Logs
```bash
make logs
```

### Check Status
```bash
make status
```

### View Metrics
```bash
make metrics
```

### Port Forward for Direct Access
```bash
# In one terminal
make forward

# In another terminal, send a request
curl -X POST http://localhost:8000/api/v1.0/predictions \
  -H 'Content-Type: application/json' \
  -d '{
    "data": {
      "ndarray": [
        ["The movie was great", "I loved the film"]
      ]
    }
  }'
```

---

## Cleanup

When you're done:

```bash
# Remove everything (deployment + cluster)
make cleanup

# Or just remove deployment (keep cluster for next time)
make cleanup-deploy
```

---

## What Next?

Now that you have a working deployment, explore:

1. **Architecture**: Read [README.md#architecture-overview](README.md#architecture-overview)
2. **Comparisons**: See [README.md#seldon-core-vs-vanilla-kubernetes](README.md#seldon-core-vs-vanilla-kubernetes)
3. **Monitoring**: Learn about [monitoring/README.md](monitoring/README.md)
4. **Advanced**: Try A/B testing with multiple models

---

## Troubleshooting

### "make setup" fails

**Issue**: Can't create cluster

**Fix**:
```bash
# Delete existing cluster and retry
kind delete cluster --name mlops-seldon
make setup
```

### "make deploy" stuck

**Issue**: Pod not starting

**Fix**:
```bash
# Check what's wrong
kubectl describe pod -l app=distilbert-classifier-default-0-classifier

# Common fix: rebuild image
make build-image
make deploy
```

### "make test" returns errors

**Issue**: Model not responding

**Fix**:
```bash
# Check logs for errors
make logs

# Verify model files are present
kubectl describe configmap distilbert-classifier-model
```

---

## Quick Reference

```bash
# Common commands
make help            # Show all commands
make setup           # Initial setup
make build-image     # Build Docker image
make deploy          # Deploy to K8s
make test            # Test prediction
make logs            # View logs
make status          # Check status
make cleanup         # Remove everything
```

---

**Total Time**: ~10 minutes from zero to working deployment ⚡

For detailed documentation, see [README.md](README.md).
