"""
Export trained model for serving with Seldon Core.

This script exports a trained DistilBERT model from a checkpoint directory
into a format that can be loaded by our custom Seldon inference server.
It saves the model weights and tokenizer in a standard format.
"""

import argparse
import os
import shutil
from pathlib import Path

import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification


def export_model(checkpoint_path: str, output_dir: str):
    """
    Export a trained model checkpoint for serving.

    Args:
        checkpoint_path: Path to the PyTorch Lightning checkpoint (.ckpt file)
        output_dir: Directory to save the exported model

    The exported model includes:
    - PyTorch model weights (model.pt)
    - Tokenizer files (tokenizer/)
    - Model configuration (config.json)
    """
    print(f"Loading checkpoint from: {checkpoint_path}")

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Load the Lightning checkpoint
    # PyTorch Lightning saves the model state in checkpoint['state_dict']
    checkpoint = torch.load(checkpoint_path, map_location='cpu')

    # Extract model hyperparameters from the checkpoint
    # Lightning automatically saves hyperparameters in the checkpoint
    hparams = checkpoint.get('hyper_parameters', {})
    model_name = hparams.get('model_name_or_path', 'distilbert-base-uncased')
    num_labels = hparams.get('num_labels', 2)

    print(f"Model: {model_name}, Num Labels: {num_labels}")

    # Initialize a fresh model with the same architecture
    model = AutoModelForSequenceClassification.from_pretrained(
        model_name,
        num_labels=num_labels
    )

    # Load the trained weights from checkpoint
    # Remove the 'model.' prefix that Lightning adds to state dict keys
    state_dict = checkpoint['state_dict']
    new_state_dict = {}
    for key, value in state_dict.items():
        # Lightning prefixes keys with 'model.' - we need to remove it
        if key.startswith('model.'):
            new_key = key[6:]  # Remove 'model.' prefix
            new_state_dict[new_key] = value

    model.load_state_dict(new_state_dict)

    # Save the model in PyTorch format
    # We save just the state dict for faster loading during inference
    model_path = os.path.join(output_dir, 'model.pt')
    torch.save(model.state_dict(), model_path)
    print(f"Saved model weights to: {model_path}")

    # Save the model configuration
    # This includes architecture details needed to reconstruct the model
    config_path = os.path.join(output_dir, 'config.json')
    model.config.to_json_file(config_path)
    print(f"Saved model config to: {config_path}")

    # Save the tokenizer
    # The tokenizer is needed to preprocess input text during inference
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    tokenizer_dir = os.path.join(output_dir, 'tokenizer')
    tokenizer.save_pretrained(tokenizer_dir)
    print(f"Saved tokenizer to: {tokenizer_dir}")

    # Create a metadata file with model information
    # This helps document what model is deployed and its training config
    metadata = {
        'model_name': model_name,
        'num_labels': num_labels,
        'task': hparams.get('task_name', 'mrpc'),
        'checkpoint': checkpoint_path,
    }

    metadata_path = os.path.join(output_dir, 'metadata.txt')
    with open(metadata_path, 'w') as f:
        for key, value in metadata.items():
            f.write(f"{key}: {value}\n")
    print(f"Saved metadata to: {metadata_path}")

    print(f"\n✓ Model exported successfully to: {output_dir}")
    print(f"  - Model weights: model.pt")
    print(f"  - Configuration: config.json")
    print(f"  - Tokenizer: tokenizer/")
    print(f"  - Metadata: metadata.txt")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Export trained model for Seldon Core deployment"
    )
    parser.add_argument(
        "--checkpoint",
        type=str,
        required=True,
        help="Path to PyTorch Lightning checkpoint file (.ckpt)"
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default="exported_model",
        help="Directory to save exported model (default: exported_model)"
    )

    args = parser.parse_args()

    # Validate checkpoint exists
    if not os.path.exists(args.checkpoint):
        raise FileNotFoundError(f"Checkpoint not found: {args.checkpoint}")

    export_model(args.checkpoint, args.output_dir)
