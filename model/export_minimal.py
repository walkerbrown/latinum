#!/usr/bin/env python3
"""
Minimal Core ML Export - Ultra-simple model for debugging
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import torch
import torch.nn as nn
import torch.nn.functional as F
import coremltools as ct


class MinimalLM(nn.Module):
    """Ultra-minimal model for Core ML export testing."""

    def __init__(self, vocab_size=78, d_model=128, seq_len=32):
        super().__init__()
        self.vocab_size = vocab_size
        self.d_model = d_model
        self.seq_len = seq_len

        # Simple embeddings
        self.token_embedding = nn.Embedding(vocab_size, d_model)
        self.pos_embedding = nn.Parameter(torch.randn(1, seq_len, d_model) * 0.02)

        # Simple transformer-like layers (no attention for testing)
        self.layers = nn.Sequential(
            nn.Linear(d_model, d_model * 4),
            nn.GELU(),
            nn.Linear(d_model * 4, d_model),
            nn.LayerNorm(d_model),
            nn.Linear(d_model, d_model * 4),
            nn.GELU(),
            nn.Linear(d_model * 4, d_model),
            nn.LayerNorm(d_model),
        )

        # Output
        self.output = nn.Linear(d_model, vocab_size)

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        # input_ids: [1, seq_len]
        x = self.token_embedding(input_ids)  # [1, seq_len, d_model]
        x = x + self.pos_embedding[:, :self.seq_len, :]
        x = self.layers(x)
        logits = self.output(x)
        return logits[:, -1, :]  # [1, vocab_size]


def test_minimal():
    """Test minimal model conversion."""
    print("Creating minimal model...")
    model = MinimalLM(vocab_size=78, d_model=128, seq_len=32)
    model.eval()

    print("Testing forward pass...")
    example_input = torch.randint(0, 78, (1, 32))
    with torch.no_grad():
        output = model(example_input)
    print(f"  Input shape: {example_input.shape}")
    print(f"  Output shape: {output.shape}")

    print("\nTracing model...")
    with torch.no_grad():
        traced = torch.jit.trace(model, example_input)

    print("Converting to Core ML...")
    try:
        mlmodel = ct.convert(
            traced,
            inputs=[ct.TensorType(name="input_ids", shape=(1, 32), dtype=int)],
            outputs=[ct.TensorType(name="logits")],
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS15,
            compute_precision=ct.precision.FLOAT16,
        )
        print("SUCCESS! Minimal model converts.")
        return True
    except Exception as e:
        print(f"FAILED: {e}")
        return False


class SimpleSelfAttention(nn.Module):
    """Simple self-attention using einsum for Core ML compatibility."""

    def __init__(self, d_model, n_heads, seq_len):
        super().__init__()
        self.d_model = d_model
        self.n_heads = n_heads
        self.head_dim = d_model // n_heads
        self.seq_len = seq_len

        # Using separate weight matrices for each head to avoid reshapes
        self.q_weights = nn.Parameter(torch.randn(n_heads, d_model, self.head_dim) * 0.02)
        self.k_weights = nn.Parameter(torch.randn(n_heads, d_model, self.head_dim) * 0.02)
        self.v_weights = nn.Parameter(torch.randn(n_heads, d_model, self.head_dim) * 0.02)
        self.out_proj = nn.Linear(d_model, d_model)

        # Pre-computed causal mask with -inf values
        mask = torch.triu(torch.full((seq_len, seq_len), float('-inf')), diagonal=1)
        self.register_buffer('mask', mask)

        # Scale as constant
        self.scale = self.head_dim ** -0.5

    def forward(self, x):
        # x: [1, seq_len, d_model]

        # Project to Q, K, V using einsum (avoids reshape)
        # [1, L, D] x [H, D, d] -> [1, H, L, d]
        q = torch.einsum('bld,hdk->bhlk', x, self.q_weights)
        k = torch.einsum('bld,hdk->bhlk', x, self.k_weights)
        v = torch.einsum('bld,hdk->bhlk', x, self.v_weights)

        # Attention scores: [1, H, L, L]
        scores = torch.einsum('bhik,bhjk->bhij', q, k) * self.scale

        # Apply causal mask
        scores = scores + self.mask

        # Softmax
        attn = F.softmax(scores, dim=-1)

        # Weighted sum: [1, H, L, d]
        out = torch.einsum('bhij,bhjk->bhik', attn, v)

        # Concatenate heads: [1, L, H*d] = [1, L, D]
        out = torch.einsum('bhlk->blhk', out)
        # Flatten last two dims - use reshape with concrete values
        out = out.reshape(1, self.seq_len, self.d_model)

        # Output projection
        out = self.out_proj(out)

        return out


class TransformerLM(nn.Module):
    """Simple transformer LM for Core ML export."""

    def __init__(self, vocab_size=78, d_model=128, n_heads=4, n_layers=4, d_ff=512, seq_len=32):
        super().__init__()
        self.vocab_size = vocab_size
        self.d_model = d_model
        self.seq_len = seq_len

        # Embeddings
        self.token_emb = nn.Embedding(vocab_size, d_model)
        self.pos_emb = nn.Embedding(seq_len, d_model)

        # Pre-computed position indices
        self.register_buffer('positions', torch.arange(seq_len))

        # Transformer layers
        self.layers = nn.ModuleList()
        for _ in range(n_layers):
            self.layers.append(nn.ModuleDict({
                'attn': SimpleSelfAttention(d_model, n_heads, seq_len),
                'ln1': nn.LayerNorm(d_model),
                'ff': nn.Sequential(
                    nn.Linear(d_model, d_ff),
                    nn.GELU(),
                    nn.Linear(d_ff, d_model),
                ),
                'ln2': nn.LayerNorm(d_model),
            }))

        self.ln_out = nn.LayerNorm(d_model)
        self.head = nn.Linear(d_model, vocab_size, bias=False)

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        B, L = input_ids.shape

        # Embeddings
        tok_emb = self.token_emb(input_ids)
        pos_emb = self.pos_emb(self.positions[:L])
        x = tok_emb + pos_emb

        # Transformer layers
        for layer in self.layers:
            x = x + layer['attn'](layer['ln1'](x))
            x = x + layer['ff'](layer['ln2'](x))

        # Output
        x = self.ln_out(x)
        logits = self.head(x)

        return logits[:, -1, :]


def test_transformer():
    """Test transformer model conversion."""
    print("\nCreating transformer model...")
    model = TransformerLM(vocab_size=78, d_model=128, n_heads=4, n_layers=4, d_ff=512, seq_len=32)
    model.eval()

    print("Testing forward pass...")
    example_input = torch.randint(0, 78, (1, 32))
    with torch.no_grad():
        output = model(example_input)
    print(f"  Input shape: {example_input.shape}")
    print(f"  Output shape: {output.shape}")

    print("\nConverting model...")

    # Try scripting first (better for dynamic ops), then fall back to trace
    try:
        print("  Trying torch.jit.script...")
        with torch.no_grad():
            scripted = torch.jit.script(model)
        jit_model = scripted
    except Exception as e:
        print(f"  Script failed ({e}), using trace...")
        with torch.no_grad():
            jit_model = torch.jit.trace(model, example_input)

    print("Converting to Core ML...")
    try:
        mlmodel = ct.convert(
            jit_model,
            inputs=[ct.TensorType(name="input_ids", shape=(1, 32), dtype=int)],
            outputs=[ct.TensorType(name="logits")],
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS15,
            compute_precision=ct.precision.FLOAT16,
        )
        print("SUCCESS! Transformer model converts.")

        # Save it
        output_path = Path(__file__).parent / 'LatinLM.mlpackage'
        mlmodel.save(str(output_path))
        print(f"Saved to {output_path}")

        # Load trained weights if possible
        model_path = Path(__file__).parent / 'latin_lm_final.pt'
        if model_path.exists():
            print("\nLoading trained weights...")
            checkpoint = torch.load(model_path, map_location='cpu', weights_only=False)
            src = checkpoint['model_state_dict']

            # Transfer compatible weights
            dst = model.state_dict()
            transferred = 0
            for key in dst:
                if key in src and src[key].shape == dst[key].shape:
                    dst[key] = src[key]
                    transferred += 1
                elif 'token_emb' in key and 'token_embedding' in str(src.keys()):
                    src_key = key.replace('token_emb', 'token_embedding')
                    if src_key in src and src[src_key].shape == dst[key].shape:
                        dst[key] = src[src_key]
                        transferred += 1

            model.load_state_dict(dst)
            print(f"  Transferred {transferred} weight tensors")

            # Re-export with trained weights
            model.eval()
            with torch.no_grad():
                traced = torch.jit.trace(model, example_input)

            mlmodel = ct.convert(
                traced,
                inputs=[ct.TensorType(name="input_ids", shape=(1, 32), dtype=int)],
                outputs=[ct.TensorType(name="logits")],
                convert_to="mlprogram",
                minimum_deployment_target=ct.target.iOS15,
                compute_precision=ct.precision.FLOAT16,
            )
            mlmodel.author = "Latinum Keyboard"
            mlmodel.short_description = "Latin character prediction model"
            mlmodel.version = "1.0.0"
            mlmodel.save(str(output_path))
            print(f"Re-saved with trained weights to {output_path}")

        return True
    except Exception as e:
        print(f"FAILED: {e}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == '__main__':
    print("=" * 50)
    print("Testing minimal model...")
    print("=" * 50)
    minimal_ok = test_minimal()

    print("\n" + "=" * 50)
    print("Testing transformer model...")
    print("=" * 50)
    transformer_ok = test_transformer()

    print("\n" + "=" * 50)
    print("Summary:")
    print(f"  Minimal model: {'OK' if minimal_ok else 'FAILED'}")
    print(f"  Transformer model: {'OK' if transformer_ok else 'FAILED'}")
