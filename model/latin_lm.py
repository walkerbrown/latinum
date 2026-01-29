#!/usr/bin/env python3
"""
Latin Language Model for Keyboard Prediction

A small transformer-based character language model optimized for:
- Real-time keystroke prediction (low latency)
- On-device inference (small memory footprint)
- Word and inflection completion (Latin morphology)

Architecture:
- Character-level input/output
- Small transformer decoder (causal self-attention)
- ~1-3M parameters for ~5MB Core ML model

The model predicts P(next_char | context) which directly maps to
keyboard completion suggestions.
"""

try:
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
    from torch.utils.data import Dataset, DataLoader
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False
    print("Warning: PyTorch not available. Model code will not run.")
    print("Install with: pip3 install torch")

import json
import math
from pathlib import Path
from typing import Dict, List, Optional, Tuple


# Model hyperparameters optimized for keyboard use
class ModelConfig:
    """Configuration for the Latin language model."""

    def __init__(
        self,
        vocab_size: int = 78,        # Character vocabulary size
        d_model: int = 128,          # Embedding dimension
        n_heads: int = 4,            # Number of attention heads
        n_layers: int = 4,           # Number of transformer layers
        d_ff: int = 512,             # Feed-forward dimension
        max_seq_len: int = 64,       # Maximum sequence length
        dropout: float = 0.1,        # Dropout rate
        pad_id: int = 0,             # Padding token ID
    ):
        self.vocab_size = vocab_size
        self.d_model = d_model
        self.n_heads = n_heads
        self.n_layers = n_layers
        self.d_ff = d_ff
        self.max_seq_len = max_seq_len
        self.dropout = dropout
        self.pad_id = pad_id

    def to_dict(self) -> dict:
        return self.__dict__.copy()

    @classmethod
    def from_dict(cls, d: dict) -> 'ModelConfig':
        return cls(**d)

    def save(self, path: Path):
        with open(path, 'w') as f:
            json.dump(self.to_dict(), f, indent=2)

    @classmethod
    def load(cls, path: Path) -> 'ModelConfig':
        with open(path, 'r') as f:
            return cls.from_dict(json.load(f))

    @property
    def num_parameters(self) -> int:
        """Estimate number of parameters."""
        # Embeddings
        params = self.vocab_size * self.d_model  # Token embedding
        params += self.max_seq_len * self.d_model  # Position embedding

        # Transformer layers
        per_layer = (
            4 * self.d_model * self.d_model +  # Q, K, V, O projections
            2 * self.d_model * self.d_ff +     # FF up and down
            4 * self.d_model                    # Layer norms
        )
        params += self.n_layers * per_layer

        # Output projection
        params += self.d_model * self.vocab_size

        return params


if TORCH_AVAILABLE:

    class PositionalEncoding(nn.Module):
        """Sinusoidal positional encoding."""

        def __init__(self, d_model: int, max_len: int = 512, dropout: float = 0.1):
            super().__init__()
            self.dropout = nn.Dropout(p=dropout)

            pe = torch.zeros(max_len, d_model)
            position = torch.arange(0, max_len, dtype=torch.float).unsqueeze(1)
            div_term = torch.exp(
                torch.arange(0, d_model, 2).float() * (-math.log(10000.0) / d_model)
            )
            pe[:, 0::2] = torch.sin(position * div_term)
            pe[:, 1::2] = torch.cos(position * div_term)
            pe = pe.unsqueeze(0)  # [1, max_len, d_model]

            self.register_buffer('pe', pe)

        def forward(self, x: torch.Tensor) -> torch.Tensor:
            """
            Args:
                x: [batch, seq_len, d_model]
            Returns:
                x with positional encoding added
            """
            x = x + self.pe[:, :x.size(1), :]
            return self.dropout(x)


    class TransformerBlock(nn.Module):
        """Single transformer decoder block."""

        def __init__(self, config: ModelConfig):
            super().__init__()

            self.attention = nn.MultiheadAttention(
                embed_dim=config.d_model,
                num_heads=config.n_heads,
                dropout=config.dropout,
                batch_first=True,
            )
            self.ln1 = nn.LayerNorm(config.d_model)

            self.ff = nn.Sequential(
                nn.Linear(config.d_model, config.d_ff),
                nn.GELU(),
                nn.Dropout(config.dropout),
                nn.Linear(config.d_ff, config.d_model),
                nn.Dropout(config.dropout),
            )
            self.ln2 = nn.LayerNorm(config.d_model)

        def forward(
            self,
            x: torch.Tensor,
            attn_mask: Optional[torch.Tensor] = None,
            key_padding_mask: Optional[torch.Tensor] = None,
        ) -> torch.Tensor:
            """
            Args:
                x: [batch, seq_len, d_model]
                attn_mask: Causal attention mask
                key_padding_mask: Padding mask

            Returns:
                Output tensor [batch, seq_len, d_model]
            """
            # Self-attention with residual
            attn_out, _ = self.attention(
                x, x, x,
                attn_mask=attn_mask,
                key_padding_mask=key_padding_mask,
                need_weights=False,
            )
            x = self.ln1(x + attn_out)

            # Feed-forward with residual
            ff_out = self.ff(x)
            x = self.ln2(x + ff_out)

            return x


    class LatinLanguageModel(nn.Module):
        """
        Character-level language model for Latin keyboard prediction.

        Input: Sequence of character IDs
        Output: Logits over next character for each position
        """

        def __init__(self, config: ModelConfig):
            super().__init__()
            self.config = config

            # Token embedding
            self.token_embedding = nn.Embedding(
                config.vocab_size, config.d_model, padding_idx=config.pad_id
            )

            # Positional encoding
            self.pos_encoding = PositionalEncoding(
                config.d_model, config.max_seq_len, config.dropout
            )

            # Transformer blocks
            self.blocks = nn.ModuleList([
                TransformerBlock(config) for _ in range(config.n_layers)
            ])

            # Output projection
            self.ln_out = nn.LayerNorm(config.d_model)
            self.lm_head = nn.Linear(config.d_model, config.vocab_size, bias=False)

            # Tie embedding weights with output
            self.lm_head.weight = self.token_embedding.weight

            # Initialize weights
            self.apply(self._init_weights)

            # Cache for causal mask
            self._causal_mask_cache: Dict[int, torch.Tensor] = {}

        def _init_weights(self, module):
            """Initialize weights."""
            if isinstance(module, nn.Linear):
                nn.init.normal_(module.weight, mean=0.0, std=0.02)
                if module.bias is not None:
                    nn.init.zeros_(module.bias)
            elif isinstance(module, nn.Embedding):
                nn.init.normal_(module.weight, mean=0.0, std=0.02)
                if module.padding_idx is not None:
                    module.weight.data[module.padding_idx].zero_()
            elif isinstance(module, nn.LayerNorm):
                nn.init.ones_(module.weight)
                nn.init.zeros_(module.bias)

        def _get_causal_mask(self, seq_len: int, device: torch.device) -> torch.Tensor:
            """Get or create causal attention mask."""
            if seq_len not in self._causal_mask_cache:
                mask = torch.triu(
                    torch.ones(seq_len, seq_len, device=device) * float('-inf'),
                    diagonal=1
                )
                self._causal_mask_cache[seq_len] = mask
            return self._causal_mask_cache[seq_len].to(device)

        def forward(
            self,
            input_ids: torch.Tensor,
            attention_mask: Optional[torch.Tensor] = None,
        ) -> torch.Tensor:
            """
            Forward pass.

            Args:
                input_ids: [batch, seq_len] token IDs
                attention_mask: [batch, seq_len] mask (1=valid, 0=pad)

            Returns:
                logits: [batch, seq_len, vocab_size]
            """
            batch_size, seq_len = input_ids.shape
            device = input_ids.device

            # Embeddings
            x = self.token_embedding(input_ids)  # [batch, seq_len, d_model]
            x = self.pos_encoding(x)

            # Causal mask
            causal_mask = self._get_causal_mask(seq_len, device)

            # Padding mask (convert 1=valid to True=ignore for MultiheadAttention)
            key_padding_mask = None
            if attention_mask is not None:
                key_padding_mask = (attention_mask == 0)

            # Transformer blocks
            for block in self.blocks:
                x = block(x, attn_mask=causal_mask, key_padding_mask=key_padding_mask)

            # Output
            x = self.ln_out(x)
            logits = self.lm_head(x)

            return logits

        def predict_next(
            self,
            context: torch.Tensor,
            temperature: float = 1.0,
            top_k: Optional[int] = None,
        ) -> Tuple[torch.Tensor, torch.Tensor]:
            """
            Predict next character probabilities.

            Args:
                context: [batch, seq_len] token IDs
                temperature: Sampling temperature
                top_k: Only consider top K tokens

            Returns:
                probs: [batch, vocab_size] probabilities
                top_ids: [batch, k] top token IDs
            """
            self.eval()
            with torch.no_grad():
                logits = self(context)[:, -1, :]  # Last position

                # Apply temperature
                logits = logits / temperature

                # Apply top-k filtering
                if top_k is not None:
                    v, _ = torch.topk(logits, min(top_k, logits.size(-1)))
                    logits[logits < v[:, [-1]]] = float('-inf')

                probs = F.softmax(logits, dim=-1)

                # Get top predictions
                top_probs, top_ids = torch.topk(probs, min(10, probs.size(-1)))

            return probs, top_ids

        @torch.no_grad()
        def generate(
            self,
            context: torch.Tensor,
            max_new_tokens: int = 20,
            temperature: float = 1.0,
            top_k: int = 10,
            eos_id: int = 3,
        ) -> torch.Tensor:
            """
            Generate text autoregressively.

            Args:
                context: [1, seq_len] starting context
                max_new_tokens: Maximum tokens to generate
                temperature: Sampling temperature
                top_k: Top-k sampling
                eos_id: End-of-sequence token ID

            Returns:
                Generated token IDs including context
            """
            self.eval()
            generated = context.clone()

            for _ in range(max_new_tokens):
                # Truncate to max length if needed
                ctx = generated[:, -self.config.max_seq_len:]

                # Get predictions
                probs, _ = self.predict_next(ctx, temperature, top_k)

                # Sample
                next_token = torch.multinomial(probs, num_samples=1)
                generated = torch.cat([generated, next_token], dim=1)

                # Stop at EOS
                if next_token.item() == eos_id:
                    break

            return generated


    class LatinDataset(Dataset):
        """Dataset for training sequences."""

        def __init__(self, sequences_path: Path, seq_length: int = 64):
            self.seq_length = seq_length
            self.sequences = []

            with open(sequences_path, 'r') as f:
                for line in f:
                    ids = [int(x) for x in line.strip().split()]
                    if len(ids) >= seq_length + 1:
                        self.sequences.append(ids[:seq_length + 1])

        def __len__(self) -> int:
            return len(self.sequences)

        def __getitem__(self, idx: int) -> Tuple[torch.Tensor, torch.Tensor]:
            seq = self.sequences[idx]
            input_ids = torch.tensor(seq[:-1], dtype=torch.long)
            target_ids = torch.tensor(seq[1:], dtype=torch.long)
            return input_ids, target_ids


    def train_model(
        model: LatinLanguageModel,
        train_loader: DataLoader,
        val_loader: Optional[DataLoader] = None,
        epochs: int = 10,
        lr: float = 3e-4,
        device: str = 'cpu',
        checkpoint_dir: Optional[Path] = None,
    ) -> Dict:
        """
        Train the language model.

        Returns:
            Training statistics
        """
        model = model.to(device)
        optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=0.01)
        scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
            optimizer, T_max=epochs * len(train_loader)
        )

        criterion = nn.CrossEntropyLoss(ignore_index=model.config.pad_id)

        stats = {'train_loss': [], 'val_loss': []}

        for epoch in range(epochs):
            # Training
            model.train()
            train_loss = 0
            num_batches = 0

            for batch_idx, (input_ids, target_ids) in enumerate(train_loader):
                input_ids = input_ids.to(device)
                target_ids = target_ids.to(device)

                optimizer.zero_grad()
                logits = model(input_ids)
                loss = criterion(logits.view(-1, logits.size(-1)), target_ids.view(-1))
                loss.backward()

                # Gradient clipping
                torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)

                optimizer.step()
                scheduler.step()

                train_loss += loss.item()
                num_batches += 1

                if batch_idx % 1000 == 0:
                    print(f"  Epoch {epoch+1}, Batch {batch_idx}, "
                          f"Loss: {loss.item():.4f}")

            avg_train_loss = train_loss / num_batches
            stats['train_loss'].append(avg_train_loss)
            print(f"Epoch {epoch+1}/{epochs}, Train Loss: {avg_train_loss:.4f}")

            # Validation
            if val_loader is not None:
                model.eval()
                val_loss = 0
                num_val = 0

                with torch.no_grad():
                    for input_ids, target_ids in val_loader:
                        input_ids = input_ids.to(device)
                        target_ids = target_ids.to(device)

                        logits = model(input_ids)
                        loss = criterion(
                            logits.view(-1, logits.size(-1)),
                            target_ids.view(-1)
                        )
                        val_loss += loss.item()
                        num_val += 1

                avg_val_loss = val_loss / num_val
                stats['val_loss'].append(avg_val_loss)
                print(f"  Val Loss: {avg_val_loss:.4f}")

            # Save checkpoint
            if checkpoint_dir is not None:
                checkpoint_dir.mkdir(parents=True, exist_ok=True)
                torch.save({
                    'epoch': epoch,
                    'model_state_dict': model.state_dict(),
                    'optimizer_state_dict': optimizer.state_dict(),
                    'config': model.config.to_dict(),
                }, checkpoint_dir / f'checkpoint_epoch{epoch+1}.pt')

        return stats


def print_model_info(config: ModelConfig):
    """Print model configuration and size estimates."""
    print("\n=== Model Configuration ===")
    print(f"  Vocabulary size: {config.vocab_size}")
    print(f"  Embedding dim: {config.d_model}")
    print(f"  Attention heads: {config.n_heads}")
    print(f"  Transformer layers: {config.n_layers}")
    print(f"  Feed-forward dim: {config.d_ff}")
    print(f"  Max sequence length: {config.max_seq_len}")
    print(f"  Dropout: {config.dropout}")

    num_params = config.num_parameters
    print(f"\n  Estimated parameters: {num_params:,}")
    print(f"  Estimated model size (FP32): {num_params * 4 / 1024 / 1024:.1f} MB")
    print(f"  Estimated model size (FP16): {num_params * 2 / 1024 / 1024:.1f} MB")
    print(f"  Estimated model size (INT8): {num_params / 1024 / 1024:.1f} MB")


if __name__ == '__main__':
    # Configuration for keyboard model
    config = ModelConfig(
        vocab_size=78,
        d_model=128,
        n_heads=4,
        n_layers=4,
        d_ff=512,
        max_seq_len=64,
        dropout=0.1,
    )

    print_model_info(config)

    # Save config
    config_path = Path(__file__).parent / 'config.json'
    config.save(config_path)
    print(f"\nSaved config to {config_path}")

    if TORCH_AVAILABLE:
        # Create model
        model = LatinLanguageModel(config)

        # Count actual parameters
        total_params = sum(p.numel() for p in model.parameters())
        trainable_params = sum(p.numel() for p in model.parameters() if p.requires_grad)

        print(f"\n  Actual parameters: {total_params:,}")
        print(f"  Trainable parameters: {trainable_params:,}")

        # Test forward pass
        print("\nTesting forward pass...")
        test_input = torch.randint(0, config.vocab_size, (2, 32))
        test_output = model(test_input)
        print(f"  Input shape: {test_input.shape}")
        print(f"  Output shape: {test_output.shape}")

        # Test prediction
        print("\nTesting prediction...")
        probs, top_ids = model.predict_next(test_input[:1])
        print(f"  Probability shape: {probs.shape}")
        print(f"  Top IDs: {top_ids[0].tolist()}")
    else:
        print("\nNote: PyTorch not available. Install to test model.")
        print("  pip3 install torch")
