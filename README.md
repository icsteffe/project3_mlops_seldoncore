# MLOPS Hyperparameter Tuning

This project trains a DistilBERT model on the GLUE MRPC task with configurable hyperparameters and logs results to
Weights & Biases (W&B).

## Table of Contents

- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Running with Docker (Recommended)](#running-with-docker-recommended)
- [Running Locally](#running-locally)
- [Configuration Options](#configuration-options)

## Prerequisites

Before you begin, ensure you have the following installed:

- **Git** (to clone the repository)
- **Weights & Biases Account**
    - Sign up at [wandb.ai](https://wandb.ai/)
    - Get your API key from [wandb.ai/authorize](https://wandb.ai/authorize)


## Getting Started

### 1. Clone the Repository

```bash
git clone git@gitlab.com:i.ba_mlops.h25/hyperparameter-tuning.git
cd hyperparameter-tuning
```

### 2. Set Up Your W&B API Key

You'll need your Weights & Biases API key to log training metrics. You can find it
at [wandb.ai/authorize](https://wandb.ai/authorize).

### 3. Set Up Environment Variables

Create a `.env` file from the example:

```bash
# On Windows (CMD)
copy .env.example .env

# On Windows (PowerShell) or macOS/Linux
cp .env.example .env
```

Edit the `.env` file and add your W&B API key:

```
WANDB_API_KEY=your_wandb_api_key_here
```

## Running with Docker (Recommended)

Docker provides a consistent environment and handles all dependencies automatically.

### Prerequisites

- **Docker**: [Install Docker Desktop](https://www.docker.com/products/docker-desktop/) for Windows, macOS, or Linux

### Step 1: Build and Run with Default Configuration

Build and run with default configuration:

```bash
docker compose up --build
```

Build and run with custom arguments:

```bash
docker compose run --rm train [-h] --wandb-project WANDB_PROJECT [--checkpoint-dir CHECKPOINT_DIR] [-bs BATCH_SIZE] [-lr LEARNING_RATE] [-ws WARMUP_STEPS] [-wd WEIGHT_DECAY] [-o {AdamW,Adam,NAdam,SGD}] [-adm-b ADAM_BETAS] [-adm-e ADAM_EPS] [-sgd-m SGD_MOMENTUM] [-sgd-d SGD_DAMPENING] [-sgd-n]
```

**This command:**
- Builds the Docker image (if not already built or if changes detected)
- Runs the training with default or custom configuration
- Shows output in your terminal

### Step 2: View Results

After training completes, view your results at [wandb.ai](https://wandb.ai/) in your specified project.

### Save Model Checkpoints locally

To persist model checkpoints on your local machine, uncomment the volumes section in `docker-compose.yml`:

```yaml
volumes:
  - ./models:/app/models
```

## Running Locally

If you prefer to run without Docker:

### Prerequisites

- **Python 3.12**
- **[uv](https://docs.astral.sh/uv/)** package manager

### Step 1: Install Dependencies

```bash
uv sync --extra cpu
```

For using your GPU with [CUDA 12.9](https://developer.nvidia.com/cuda-12-9-1-download-archive):

```bash
uv sync --extra cu129
```

### Step 2: Run Training

Run the training script:

```bash
python train.py [-h] --wandb-project WANDB_PROJECT [--checkpoint-dir CHECKPOINT_DIR] [-bs BATCH_SIZE] [-lr LEARNING_RATE] [-ws WARMUP_STEPS] [-wd WEIGHT_DECAY] [-o {AdamW,Adam,NAdam,SGD}] [-adm-b ADAM_BETAS] [-adm-e ADAM_EPS] [-sgd-m SGD_MOMENTUM] [-sgd-d SGD_DAMPENING] [-sgd-n]
```

### Step 3: View Results

After training completes, view your results at [wandb.ai](https://wandb.ai/) in your specified project.

## Configuration Options

The training script supports various hyperparameters:

| Argument           | Short    | Type   | Description                                    |
|--------------------|----------|--------|------------------------------------------------|
| `--wandb-project`  | -        | string | **Required.** Name of Weights & Biases project |
| `--checkpoint-dir` | -        | string | Directory to store checkpoints in              |
| `--batch-size`     | `-bs`    | int    | Training & evaluation batch size               |
| `--learning-rate`  | `-lr`    | float  | Optimizer learning rate                        |
| `--warmup-steps`   | `-ws`    | int    | Number of warmup steps                         |
| `--weight-decay`   | `-wd`    | float  | Weight decay (L2 regularization)               |
| `--optimizer`      | `-o`     | choice | Optimizer to use: AdamW, Adam, NAdam, SGD      |
| `--adam-betas`     | `-adm-b` | tuple  | Adam betas as 'beta1,beta2' (comma-separated)  |
| `--adam-eps`       | `-adm-e` | float  | Adam epsilon                                   |
| `--sgd-momentum`   | `-sgd-m` | float  | SGD momentum                                   |
| `--sgd-dampening`  | `-sgd-d` | float  | SGD dampening                                  |
| `--sgd-nesterov`   | `-sgd-n` | flag   | Enable Nesterov momentum                       |
