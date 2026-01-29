#!/usr/bin/env python3
"""
Simplified Core ML Export for Latin Language Model

This version creates a Core ML-friendly model by:
1. Using fixed positional embeddings (not sinusoidal)
2. Pre-computing the causal attention mask
3. Avoiding dynamic shape operations
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
except ImportError:
    print("Error: PyTorch is required.")
    sys.exit(1)

try:
    import coremltools as ct
except ImportError:
    print("Error: coremltools is required.")
    sys.exit(1)

import json


class SimplifiedTransformerBlock(nn.Module):
    """Transformer block without dynamic mask creation."""

    def __init__(self, d_model: int, n_heads: int, d_ff: int, dropout: float = 0.1):
        super().__init__()
        self.d_model = d_model
        self.n_heads = n_heads

        # Self-attention components (manual implementation for better tracing)
        self.q_proj = nn.Linear(d_model, d_model)
        self.k_proj = nn.Linear(d_model, d_model)
        self.v_proj = nn.Linear(d_model, d_model)
        self.o_proj = nn.Linear(d_model, d_model)

        self.ln1 = nn.LayerNorm(d_model)

        self.ff = nn.Sequential(
            nn.Linear(d_model, d_ff),
            nn.GELU(),
            nn.Linear(d_ff, d_model),
        )
        self.ln2 = nn.LayerNorm(d_model)

    def forward(self, x: torch.Tensor, mask: torch.Tensor) -> torch.Tensor:
        batch, seq_len, _ = x.shape
        head_dim = self.d_model // self.n_heads

        # Self-attention
        q = self.q_proj(x).view(batch, seq_len, self.n_heads, head_dim).transpose(1, 2)
        k = self.k_proj(x).view(batch, seq_len, self.n_heads, head_dim).transpose(1, 2)
        v = self.v_proj(x).view(batch, seq_len, self.n_heads, head_dim).transpose(1, 2)

        # Scaled dot-product attention
        scores = torch.matmul(q, k.transpose(-2, -1)) / (head_dim ** 0.5)
        scores = scores + mask  # Add causal mask
        attn = F.softmax(scores, dim=-1)

        out = torch.matmul(attn, v)
        out = out.transpose(1, 2).contiguous().view(batch, seq_len, self.d_model)
        out = self.o_proj(out)

        x = self.ln1(x + out)
        x = self.ln2(x + self.ff(x))

        return x


class SimplifiedLatinLM(nn.Module):
    """Simplified model for Core ML export."""

    def __init__(
        self,
        vocab_size: int = 78,
        d_model: int = 128,
        n_heads: int = 4,
        n_layers: int = 4,
        d_ff: int = 512,
        max_seq_len: int = 32,
    ):
        super().__init__()
        self.vocab_size = vocab_size
        self.d_model = d_model
        self.max_seq_len = max_seq_len

        # Token embedding
        self.token_embedding = nn.Embedding(vocab_size, d_model)

        # Learned positional embedding (instead of sinusoidal)
        self.pos_embedding = nn.Embedding(max_seq_len, d_model)

        # Register position indices
        self.register_buffer('positions', torch.arange(max_seq_len))

        # Transformer blocks
        self.blocks = nn.ModuleList([
            SimplifiedTransformerBlock(d_model, n_heads, d_ff)
            for _ in range(n_layers)
        ])

        # Output
        self.ln_out = nn.LayerNorm(d_model)
        self.lm_head = nn.Linear(d_model, vocab_size, bias=False)

        # Pre-computed causal mask
        mask = torch.triu(torch.ones(max_seq_len, max_seq_len) * float('-inf'), diagonal=1)
        self.register_buffer('causal_mask', mask)

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        batch, seq_len = input_ids.shape

        # Token embeddings
        x = self.token_embedding(input_ids)

        # Add positional embeddings
        positions = self.positions[:seq_len]
        x = x + self.pos_embedding(positions)

        # Get causal mask for this sequence length
        mask = self.causal_mask[:seq_len, :seq_len]

        # Transformer blocks
        for block in self.blocks:
            x = block(x, mask)

        # Output
        x = self.ln_out(x)
        logits = self.lm_head(x)

        # Return last position only for prediction
        return logits[:, -1, :]


def transfer_weights(src_model, dst_model):
    """Transfer weights from trained model to simplified model."""
    src_state = src_model.state_dict()
    dst_state = dst_model.state_dict()

    # Map weights
    for name, param in dst_state.items():
        if name in src_state and src_state[name].shape == param.shape:
            dst_state[name] = src_state[name]
            print(f"  Copied: {name}")
        elif 'token_embedding' in name and 'token_embedding.weight' in src_state:
            dst_state[name] = src_state['token_embedding.weight']
            print(f"  Copied: {name} <- token_embedding.weight")
        elif 'pos_embedding' in name:
            # Initialize from sinusoidal or random
            print(f"  Initialized: {name} (learned)")
        elif 'blocks' in name:
            # Map attention weights
            src_name = name.replace('q_proj', 'attention.in_proj_weight').replace(
                'k_proj', 'attention.in_proj_weight').replace(
                'v_proj', 'attention.in_proj_weight')
            if 'attention' in name:
                # Handle multi-head attention conversion
                block_idx = name.split('.')[1]
                if 'q_proj.weight' in name:
                    src_key = f'blocks.{block_idx}.attention.in_proj_weight'
                    if src_key in src_state:
                        d = src_state[src_key].shape[0] // 3
                        dst_state[name] = src_state[src_key][:d]
                        print(f"  Copied: {name} <- {src_key}[:d]")
                elif 'k_proj.weight' in name:
                    src_key = f'blocks.{block_idx}.attention.in_proj_weight'
                    if src_key in src_state:
                        d = src_state[src_key].shape[0] // 3
                        dst_state[name] = src_state[src_key][d:2*d]
                        print(f"  Copied: {name} <- {src_key}[d:2d]")
                elif 'v_proj.weight' in name:
                    src_key = f'blocks.{block_idx}.attention.in_proj_weight'
                    if src_key in src_state:
                        d = src_state[src_key].shape[0] // 3
                        dst_state[name] = src_state[src_key][2*d:]
                        print(f"  Copied: {name} <- {src_key}[2d:]")
                elif 'q_proj.bias' in name:
                    src_key = f'blocks.{block_idx}.attention.in_proj_bias'
                    if src_key in src_state:
                        d = src_state[src_key].shape[0] // 3
                        dst_state[name] = src_state[src_key][:d]
                elif 'k_proj.bias' in name:
                    src_key = f'blocks.{block_idx}.attention.in_proj_bias'
                    if src_key in src_state:
                        d = src_state[src_key].shape[0] // 3
                        dst_state[name] = src_state[src_key][d:2*d]
                elif 'v_proj.bias' in name:
                    src_key = f'blocks.{block_idx}.attention.in_proj_bias'
                    if src_key in src_state:
                        d = src_state[src_key].shape[0] // 3
                        dst_state[name] = src_state[src_key][2*d:]
                elif 'o_proj' in name:
                    src_key = name.replace('o_proj', 'attention.out_proj')
                    if src_key in src_state:
                        dst_state[name] = src_state[src_key]
                        print(f"  Copied: {name} <- {src_key}")
            else:
                # Direct copy for non-attention layers
                if name in src_state:
                    dst_state[name] = src_state[name]
        else:
            print(f"  Skipped: {name}")

    dst_model.load_state_dict(dst_state, strict=False)
    return dst_model


def main():
    project_dir = Path(__file__).parent.parent
    model_dir = project_dir / 'model'
    model_path = model_dir / 'latin_lm_final.pt'
    output_path = model_dir / 'LatinLM.mlpackage'

    print(f"Loading trained model from {model_path}...")
    checkpoint = torch.load(model_path, map_location='cpu', weights_only=False)
    config = checkpoint['config']

    print("\nCreating simplified model for export...")
    simple_model = SimplifiedLatinLM(
        vocab_size=config['vocab_size'],
        d_model=config['d_model'],
        n_heads=config['n_heads'],
        n_layers=config['n_layers'],
        d_ff=config['d_ff'],
        max_seq_len=32,  # Fixed for keyboard
    )

    # Try to load weights directly first
    print("\nLoading weights...")
    try:
        # Load just the compatible weights
        src_state = checkpoint['model_state_dict']
        dst_state = simple_model.state_dict()

        # Copy token embedding
        if 'token_embedding.weight' in src_state:
            dst_state['token_embedding.weight'] = src_state['token_embedding.weight']

        # Copy output layers
        if 'ln_out.weight' in src_state:
            dst_state['ln_out.weight'] = src_state['ln_out.weight']
            dst_state['ln_out.bias'] = src_state['ln_out.bias']
        if 'lm_head.weight' in src_state:
            dst_state['lm_head.weight'] = src_state['lm_head.weight']

        # Copy transformer blocks (where shapes match)
        for i in range(config['n_layers']):
            # Layer norms
            ln1_w = f'blocks.{i}.ln1.weight'
            ln1_b = f'blocks.{i}.ln1.bias'
            ln2_w = f'blocks.{i}.ln2.weight'
            ln2_b = f'blocks.{i}.ln2.bias'

            for key in [ln1_w, ln1_b, ln2_w, ln2_b]:
                if key in src_state:
                    dst_state[key] = src_state[key]

            # Feed-forward
            ff_keys = [
                f'blocks.{i}.ff.0.weight', f'blocks.{i}.ff.0.bias',
                f'blocks.{i}.ff.2.weight', f'blocks.{i}.ff.2.bias',
            ]
            for key in ff_keys:
                if key in src_state:
                    dst_state[key] = src_state[key]

            # Attention - need to split in_proj into q, k, v
            in_proj_w = f'blocks.{i}.attention.in_proj_weight'
            in_proj_b = f'blocks.{i}.attention.in_proj_bias'
            out_proj_w = f'blocks.{i}.attention.out_proj.weight'
            out_proj_b = f'blocks.{i}.attention.out_proj.bias'

            if in_proj_w in src_state:
                d = config['d_model']
                dst_state[f'blocks.{i}.q_proj.weight'] = src_state[in_proj_w][:d]
                dst_state[f'blocks.{i}.k_proj.weight'] = src_state[in_proj_w][d:2*d]
                dst_state[f'blocks.{i}.v_proj.weight'] = src_state[in_proj_w][2*d:]

            if in_proj_b in src_state:
                d = config['d_model']
                dst_state[f'blocks.{i}.q_proj.bias'] = src_state[in_proj_b][:d]
                dst_state[f'blocks.{i}.k_proj.bias'] = src_state[in_proj_b][d:2*d]
                dst_state[f'blocks.{i}.v_proj.bias'] = src_state[in_proj_b][2*d:]

            if out_proj_w in src_state:
                dst_state[f'blocks.{i}.o_proj.weight'] = src_state[out_proj_w]
            if out_proj_b in src_state:
                dst_state[f'blocks.{i}.o_proj.bias'] = src_state[out_proj_b]

        simple_model.load_state_dict(dst_state)
        print("Weights loaded successfully!")

    except Exception as e:
        print(f"Warning: Could not load all weights: {e}")
        print("Using initialized weights...")

    # Prepare for tracing
    simple_model.eval()
    example_input = torch.randint(0, config['vocab_size'], (1, 32))

    print("\nTracing model...")
    with torch.no_grad():
        traced_model = torch.jit.trace(simple_model, example_input)

    print("Converting to Core ML...")
    try:
        mlmodel = ct.convert(
            traced_model,
            inputs=[ct.TensorType(name="input_ids", shape=(1, 32), dtype=int)],
            outputs=[ct.TensorType(name="logits")],
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS15,
            compute_precision=ct.precision.FLOAT16,
        )

        # Set metadata
        mlmodel.author = "Latinum Keyboard"
        mlmodel.short_description = "Latin character prediction model"
        mlmodel.version = "1.0.0"

        print(f"Saving to {output_path}...")
        mlmodel.save(str(output_path))

        print("\n=== Export Successful! ===")
        print(f"Model saved to: {output_path}")

        # Check size
        import subprocess
        result = subprocess.run(['du', '-sh', str(output_path)], capture_output=True, text=True)
        print(f"Model size: {result.stdout.strip().split()[0]}")

    except Exception as e:
        print(f"\nCore ML conversion failed: {e}")
        print("\nTrying ONNX intermediate format...")

        # Try ONNX route
        try:
            onnx_path = model_dir / 'latin_lm.onnx'
            torch.onnx.export(
                simple_model,
                example_input,
                str(onnx_path),
                input_names=['input_ids'],
                output_names=['logits'],
                dynamic_axes=None,
                opset_version=17,
            )
            print(f"ONNX model saved to {onnx_path}")
            print("You can convert ONNX to Core ML manually if needed.")
        except Exception as onnx_error:
            print(f"ONNX export also failed: {onnx_error}")


if __name__ == '__main__':
    main()
