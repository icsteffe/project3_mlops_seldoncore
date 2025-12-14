"""
Custom Seldon Core inference server for DistilBERT model.

This is a Python class that wraps our trained model to work with Seldon Core.
Seldon Core will automatically convert this class into a REST/gRPC microservice.

The class must implement:
- __init__(): Load the model (called once at startup)
- predict(): Process inference requests (called for each prediction)

Why use Seldon Core instead of a simple Flask API?
- Automatic REST/gRPC endpoints (no need to write HTTP handlers)
- Built-in monitoring and metrics (Prometheus integration)
- Kubernetes-native scaling and health checks
- Standardized prediction API (V1/V2 protocol)
"""

import logging
import os
from typing import List, Dict, Any, Union

import numpy as np
import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification, AutoConfig


# Configure logging to help with debugging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class Model:
    """
    Seldon Core model wrapper for DistilBERT sequence classification.

    This class follows the Seldon Core Python interface:
    https://docs.seldon.io/projects/seldon-core/en/v1.17.0/python/python_component.html
    """

    def __init__(self):
        """
        Initialize the model (called once when the container starts).

        This method loads the model weights, tokenizer, and configuration
        from the /mnt/model directory (Seldon's default model storage path).

        Seldon Core will automatically mount our model files to /mnt/model
        when we specify modelUri in the SeldonDeployment manifest.
        """
        logger.info("Initializing DistilBERT model for inference...")

        # Path where Seldon mounts the model files
        # This can be overridden with SELDON_MODEL_PATH environment variable
        # Since the model is now embedded in the Docker image, we load from /app/exported_model
        self.model_path = os.getenv("SELDON_MODEL_PATH", "/app/exported_model")
        logger.info(f"Loading model from: {self.model_path}")

        try:
            # Load the model configuration
            # This tells us the architecture details (num_labels, etc.)
            config_path = os.path.join(self.model_path, "config.json")
            self.config = AutoConfig.from_pretrained(config_path)
            logger.info(f"Loaded config: {self.config.num_labels} labels")

            # Load the tokenizer
            # The tokenizer converts text into tokens the model understands
            tokenizer_path = os.path.join(self.model_path, "tokenizer")
            self.tokenizer = AutoTokenizer.from_pretrained(tokenizer_path)
            logger.info(f"Loaded tokenizer with vocab size: {len(self.tokenizer)}")

            # Initialize the model architecture from config
            # We'll load the trained weights separately from model.pt
            self.model = AutoModelForSequenceClassification.from_config(
                self.config
            )

            # Load the trained weights
            # These are the weights we saved during training
            weights_path = os.path.join(self.model_path, "model.pt")
            state_dict = torch.load(weights_path, map_location='cpu')
            self.model.load_state_dict(state_dict)

            # Set model to evaluation mode
            # This disables dropout and uses batch norm stats from training
            self.model.eval()

            # Use GPU if available, otherwise CPU
            self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
            self.model.to(self.device)

            logger.info(f"Model loaded successfully on device: {self.device}")
            logger.info("✓ Model initialization complete")

        except Exception as e:
            logger.error(f"Failed to initialize model: {str(e)}")
            raise

    def predict(
        self,
        X: Union[np.ndarray, List, Dict],
        features_names: List[str] = None
    ) -> Union[np.ndarray, List, Dict]:
        """
        Make predictions on input data.

        This method is called by Seldon Core for each inference request.
        It must accept input and return predictions in a format Seldon understands.

        Args:
            X: Input data. Can be:
               - List of strings: ["sentence1", "sentence2", ...]
               - List of pairs: [["sent1_a", "sent1_b"], ["sent2_a", "sent2_b"], ...]
               - Dict with 'instances': {"instances": [["sent1", "sent2"], ...]}
            features_names: Optional list of feature names (usually None)

        Returns:
            Predictions as numpy array with shape (batch_size, num_labels)
            Each row contains class probabilities for one input

        Example request:
            POST /api/v1.0/predictions
            {
              "data": {
                "ndarray": [
                  ["The movie was great", "I loved it"],
                  ["Bad film", "Very disappointing"]
                ]
              }
            }

        Example response:
            {
              "data": {
                "ndarray": [[0.1, 0.9], [0.8, 0.2]]
              }
            }
        """
        logger.info(f"Received prediction request with input type: {type(X)}")
        logger.debug(f"Input shape: {np.array(X).shape if isinstance(X, (list, np.ndarray)) else 'dict'}")

        try:
            # Parse the input into a consistent format
            # Seldon can send data in different formats depending on the client
            inputs = self._parse_input(X)

            # Tokenize the input text
            # This converts text into token IDs the model can process
            encoded = self._tokenize_inputs(inputs)

            # Run inference (without computing gradients for efficiency)
            with torch.no_grad():
                outputs = self.model(**encoded)

            # Extract logits (raw model outputs before softmax)
            logits = outputs.logits

            # Convert to probabilities using softmax
            # This gives us class probabilities that sum to 1.0
            probabilities = torch.nn.functional.softmax(logits, dim=-1)

            # Convert to numpy array for Seldon
            # Seldon expects predictions as numpy arrays
            predictions = probabilities.cpu().numpy()

            logger.info(f"Generated predictions with shape: {predictions.shape}")
            return predictions

        except Exception as e:
            logger.error(f"Prediction failed: {str(e)}")
            raise

    def _parse_input(self, X: Union[np.ndarray, List, Dict]) -> List:
        """
        Parse various input formats into a consistent list format.

        Handles different input formats that clients might send:
        - Direct list of strings: ["text1", "text2"]
        - List of pairs: [["text1_a", "text1_b"], ["text2_a", "text2_b"]]
        - Dict format: {"instances": [...]}

        Args:
            X: Input in various formats

        Returns:
            Parsed input as list of strings or list of pairs
        """
        # Handle dict format (common with REST API)
        if isinstance(X, dict):
            if 'instances' in X:
                X = X['instances']
            elif 'data' in X:
                X = X['data']

        # Convert numpy array to list
        if isinstance(X, np.ndarray):
            X = X.tolist()

        # Ensure we have a list
        if not isinstance(X, list):
            raise ValueError(f"Unexpected input type: {type(X)}")

        return X

    def _tokenize_inputs(self, inputs: List) -> Dict[str, torch.Tensor]:
        """
        Tokenize input text(s) for the model.

        Handles both single sentences and sentence pairs (for tasks like MRPC).

        Args:
            inputs: List of strings or list of pairs

        Returns:
            Dictionary with input_ids, attention_mask, etc. as tensors
        """
        # Check if we have sentence pairs or single sentences
        # MRPC task uses pairs: ["sentence1", "sentence2"]
        if inputs and isinstance(inputs[0], (list, tuple)) and len(inputs[0]) == 2:
            # Sentence pairs: separate them for tokenization
            texts_a = [item[0] for item in inputs]
            texts_b = [item[1] for item in inputs]
            text_pairs = list(zip(texts_a, texts_b))
        else:
            # Single sentences
            text_pairs = inputs

        # Tokenize with padding and truncation
        # max_length=128 matches our training configuration
        encoded = self.tokenizer.batch_encode_plus(
            text_pairs,
            max_length=128,
            padding='max_length',
            truncation=True,
            return_tensors='pt'  # Return PyTorch tensors
        )

        # Move tensors to the same device as the model (CPU or GPU)
        encoded = {key: value.to(self.device) for key, value in encoded.items()}

        return encoded

    def health_status(self) -> Dict[str, Any]:
        """
        Health check endpoint (optional but recommended).

        Seldon Core can use this to check if the model is ready.
        Kubernetes will use this for liveness/readiness probes.

        Returns:
            Dictionary with health status information
        """
        return {
            "status": "ok",
            "model_loaded": self.model is not None,
            "device": str(self.device)
        }
