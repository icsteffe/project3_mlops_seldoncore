# Dockerfile for Seldon Core inference server
# This creates a container that Seldon Core can use to serve our model

# Use Seldon's pre-built Python base image
# This image includes the Seldon Core runtime and Python 3.9
# Available at: https://hub.docker.com/r/seldonio/seldon-core-s2i-python39
FROM seldonio/seldon-core-s2i-python39:1.17.1

# Why use Seldon's base image instead of plain Python?
# - Pre-configured Seldon Core runtime (handles REST/gRPC automatically)
# - Built-in monitoring and metrics endpoints
# - Kubernetes health check support
# - Standardized prediction API (V1 protocol)

# Set working directory
WORKDIR /microservice

# Copy requirements file
# We do this first to leverage Docker layer caching
# If requirements don't change, Docker reuses this layer
COPY requirements.txt .

# Install Python dependencies
# --no-cache-dir reduces image size by not storing pip cache
RUN pip install --no-cache-dir -r requirements.txt

# Copy our custom model class
# This is the Model.py file we created with predict() method
COPY Model.py /microservice/Model.py

# Set environment variables
# SELDON_MODEL_PATH: Where Seldon mounts the model files (can be overridden)
ENV SELDON_MODEL_PATH=/mnt/model

# Expose ports
# 5000: REST API endpoint (used by Seldon for predictions)
# 9000: gRPC endpoint (alternative to REST)
# These are Seldon Core's default ports
EXPOSE 5000 9000

# The base image's ENTRYPOINT automatically starts the Seldon server
# It will:
# 1. Import our Model class
# 2. Call __init__() to load the model
# 3. Start REST/gRPC servers
# 4. Route /predict requests to our predict() method
# 5. Expose /health and /metrics endpoints

# No CMD needed - the base image handles starting the server
