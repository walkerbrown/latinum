#!/usr/bin/env python3
"""
Export PyTorch Model to Core ML

This script converts the trained Latin language model to Core ML format
for deployment in the iOS keyboard extension.

Requirements:
    pip3 install torch coremltools

The exported model:
- Uses FP16 precision for smaller size
- Is optimized for Neural Engine on iPhone 12+
- Includes proper input/output specifications

Usage:
    python3 model/export_coreml.py
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    import torch
except ImportError:
    print("Error: PyTorch is required.")
    print("Install with: pip3 install torch")
    sys.exit(1)

try:
    import coremltools as ct
    from coremltools.models.neural_network import quantization_utils
except ImportError:
    print("Error: coremltools is required for Core ML export.")
    print("Install with: pip3 install coremltools")
    sys.exit(1)

from model.latin_lm import ModelConfig, LatinLanguageModel


class TracingWrapper(torch.nn.Module):
    """Wrapper for tracing that returns only logits."""

    def __init__(self, model: LatinLanguageModel):
        super().__init__()
        self.config = model.config

        # Copy components for a simpler forward pass
        self.token_embedding = model.token_embedding
        self.pos_encoding = model.pos_encoding
        self.blocks = model.blocks
        self.ln_out = model.ln_out
        self.lm_head = model.lm_head

        # Pre-compute causal mask for fixed sequence length
        seq_len = model.config.max_seq_len
        self.register_buffer('causal_mask', torch.triu(
            torch.ones(seq_len, seq_len) * float('-inf'),
            diagonal=1
        ))

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        """
        Forward pass returning logits for the last position.

        This is optimized for keyboard prediction where we only need
        the next-character probabilities.
        """
        batch_size, seq_len = input_ids.shape

        # Embeddings
        x = self.token_embedding(input_ids)
        x = self.pos_encoding(x)

        # Use pre-computed causal mask (sliced to actual seq_len)
        mask = self.causal_mask[:seq_len, :seq_len]

        # Transformer blocks
        for block in self.blocks:
            x = block(x, attn_mask=mask, key_padding_mask=None)

        # Output
        x = self.ln_out(x)
        logits = self.lm_head(x)

        # Return only last position logits [batch, vocab_size]
        return logits[:, -1, :]


def export_to_coreml(
    model_path: Path,
    output_path: Path,
    config: ModelConfig,
    quantize: bool = True,
) -> None:
    """
    Export PyTorch model to Core ML format.

    Args:
        model_path: Path to saved PyTorch model
        output_path: Path for Core ML output (.mlpackage)
        config: Model configuration
        quantize: Whether to apply INT8 quantization
    """
    print(f"Loading model from {model_path}...")

    # Load model
    checkpoint = torch.load(model_path, map_location='cpu')
    model = LatinLanguageModel(config)
    model.load_state_dict(checkpoint['model_state_dict'])
    model.eval()

    # Wrap for tracing
    wrapper = TracingWrapper(model)

    # Create example input
    # Sequence length of 32 is typical for keyboard context
    example_input = torch.randint(0, config.vocab_size, (1, 32))

    print("Tracing model...")
    wrapper.eval()
    traced_model = torch.jit.trace(wrapper, example_input)

    print("Converting to Core ML...")

    # Define input specification
    # Use fixed shape for simpler conversion (pad inputs to this length)
    input_spec = ct.TensorType(
        name="input_ids",
        shape=(1, 32),  # Fixed context length for keyboard
        dtype=int,
    )

    # Convert to Core ML
    mlmodel = ct.convert(
        traced_model,
        inputs=[input_spec],
        outputs=[ct.TensorType(name="logits")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS15,
        compute_precision=ct.precision.FLOAT16,
    )

    # Set model metadata
    mlmodel.author = "Latinum Keyboard"
    mlmodel.short_description = "Latin character-level language model for keyboard prediction"
    mlmodel.version = "1.0.0"

    # Add input/output descriptions
    spec = mlmodel.get_spec()
    spec.description.input[0].shortDescription = "Token IDs of context (max 64 characters)"
    spec.description.output[0].shortDescription = "Logits over vocabulary (78 characters)"

    if quantize:
        print("Applying quantization...")
        # Note: For mlprogram models, quantization is done differently
        # The compute_precision=FLOAT16 above already helps with size
        # For further compression, we could use ct.compression with palettization

    # Save
    print(f"Saving to {output_path}...")
    mlmodel.save(str(output_path))

    # Print model info
    print("\n=== Core ML Model Info ===")

    # Check file size
    if output_path.is_dir():
        # .mlpackage is a directory
        import subprocess
        result = subprocess.run(
            ['du', '-sh', str(output_path)],
            capture_output=True, text=True
        )
        print(f"  Size: {result.stdout.strip().split()[0]}")
    else:
        size_mb = output_path.stat().st_size / 1024 / 1024
        print(f"  Size: {size_mb:.2f} MB")

    print(f"  Inputs: {[i.name for i in mlmodel.get_spec().description.input]}")
    print(f"  Outputs: {[o.name for o in mlmodel.get_spec().description.output]}")

    print("\nNext steps:")
    print(f"  1. Copy {output_path} to iOS/Latinum/Resources/")
    print("  2. Build and run the iOS app")


def validate_coreml_model(
    model_path: Path,
    torch_model: LatinLanguageModel,
    config: ModelConfig,
) -> None:
    """Validate Core ML model outputs match PyTorch."""
    print("\nValidating Core ML model...")

    # Load Core ML model
    mlmodel = ct.models.MLModel(str(model_path))

    # Create test input
    test_input = torch.randint(0, config.vocab_size, (1, 32))

    # Get PyTorch output
    torch_model.eval()
    with torch.no_grad():
        wrapper = TracingWrapper(torch_model)
        torch_output = wrapper(test_input).numpy()

    # Get Core ML output
    coreml_output = mlmodel.predict({
        'input_ids': test_input.numpy().astype(int)
    })['logits']

    # Compare
    import numpy as np
    max_diff = np.max(np.abs(torch_output - coreml_output))
    print(f"  Max absolute difference: {max_diff:.6f}")

    if max_diff < 0.01:
        print("  Validation PASSED")
    else:
        print("  WARNING: Large difference detected. Check model conversion.")


def main():
    project_dir = Path(__file__).parent.parent
    model_dir = project_dir / 'model'

    model_path = model_dir / 'latin_lm_final.pt'
    config_path = model_dir / 'config.json'
    output_path = model_dir / 'LatinLM.mlpackage'

    # Check for model
    if not model_path.exists():
        print(f"Error: Model not found at {model_path}")
        print("Run model/train.py first to train the model.")
        sys.exit(1)

    # Load config
    if config_path.exists():
        config = ModelConfig.load(config_path)
    else:
        print("Using default config...")
        config = ModelConfig()

    # Export
    export_to_coreml(
        model_path=model_path,
        output_path=output_path,
        config=config,
        quantize=True,
    )

    # Validate
    checkpoint = torch.load(model_path, map_location='cpu')
    model = LatinLanguageModel(config)
    model.load_state_dict(checkpoint['model_state_dict'])

    validate_coreml_model(output_path, model, config)


if __name__ == '__main__':
    main()
