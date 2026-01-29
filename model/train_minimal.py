#!/usr/bin/env python3
"""
Train the minimal model that's Core ML compatible.

This model doesn't have attention but can still learn character patterns.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader, random_split
import coremltools as ct


class MinimalLM(nn.Module):
    """Minimal model that converts to Core ML reliably."""

    def __init__(self, vocab_size=78, d_model=256, n_layers=6, seq_len=32, dropout=0.1):
        super().__init__()
        self.vocab_size = vocab_size
        self.d_model = d_model
        self.seq_len = seq_len

        # Embeddings
        self.token_embedding = nn.Embedding(vocab_size, d_model)
        self.pos_embedding = nn.Parameter(torch.randn(1, seq_len, d_model) * 0.02)

        # Deep feed-forward layers with residual connections
        self.layers = nn.ModuleList()
        for _ in range(n_layers):
            self.layers.append(nn.Sequential(
                nn.LayerNorm(d_model),
                nn.Linear(d_model, d_model * 4),
                nn.GELU(),
                nn.Dropout(dropout),
                nn.Linear(d_model * 4, d_model),
                nn.Dropout(dropout),
            ))

        # Output
        self.ln_out = nn.LayerNorm(d_model)
        self.output = nn.Linear(d_model, vocab_size)

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        # input_ids: [batch, seq_len]
        x = self.token_embedding(input_ids)
        x = x + self.pos_embedding[:, :self.seq_len, :]

        # Apply layers with residual connections
        for layer in self.layers:
            x = x + layer(x)

        x = self.ln_out(x)
        logits = self.output(x)
        return logits  # [batch, seq_len, vocab_size]


class LatinDataset(Dataset):
    """Dataset for training sequences."""

    def __init__(self, sequences_path: Path, seq_length: int = 32):
        self.seq_length = seq_length
        self.sequences = []

        with open(sequences_path, 'r') as f:
            for line in f:
                ids = [int(x) for x in line.strip().split()]
                # Take first seq_length+1 tokens (input + target)
                if len(ids) >= seq_length + 1:
                    self.sequences.append(ids[:seq_length + 1])

    def __len__(self):
        return len(self.sequences)

    def __getitem__(self, idx):
        seq = self.sequences[idx]
        input_ids = torch.tensor(seq[:-1], dtype=torch.long)
        target_ids = torch.tensor(seq[1:], dtype=torch.long)
        return input_ids, target_ids


def train():
    project_dir = Path(__file__).parent.parent
    data_dir = project_dir / 'data_pipeline'
    model_dir = project_dir / 'model'

    sequences_path = data_dir / 'training_sequences.txt'

    # Device
    if torch.cuda.is_available():
        device = 'cuda'
    elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
        device = 'mps'
    else:
        device = 'cpu'
    print(f"Using device: {device}")

    # Model
    model = MinimalLM(
        vocab_size=78,
        d_model=256,
        n_layers=6,
        seq_len=32,
        dropout=0.1,
    )
    model = model.to(device)

    total_params = sum(p.numel() for p in model.parameters())
    print(f"Total parameters: {total_params:,}")

    # Dataset
    print(f"\nLoading data from {sequences_path}...")
    full_dataset = LatinDataset(sequences_path, seq_length=32)
    print(f"  Total sequences: {len(full_dataset):,}")

    # Use a subset for faster training
    subset_size = min(200000, len(full_dataset))
    indices = torch.randperm(len(full_dataset))[:subset_size].tolist()
    dataset = torch.utils.data.Subset(full_dataset, indices)
    print(f"  Using subset: {len(dataset):,}")

    train_size = int(0.95 * len(dataset))
    val_size = len(dataset) - train_size
    train_dataset, val_dataset = random_split(dataset, [train_size, val_size])

    train_loader = DataLoader(train_dataset, batch_size=128, shuffle=True, num_workers=0)
    val_loader = DataLoader(val_dataset, batch_size=128, shuffle=False, num_workers=0)

    # Training
    optimizer = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=0.01)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=5 * len(train_loader))
    criterion = nn.CrossEntropyLoss()

    print("\nTraining...")
    for epoch in range(5):
        model.train()
        train_loss = 0
        for batch_idx, (input_ids, target_ids) in enumerate(train_loader):
            input_ids = input_ids.to(device)
            target_ids = target_ids.to(device)

            optimizer.zero_grad()
            logits = model(input_ids)
            loss = criterion(logits.view(-1, 78), target_ids.view(-1))
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            scheduler.step()

            train_loss += loss.item()

            if batch_idx % 500 == 0:
                print(f"  Epoch {epoch+1}, Batch {batch_idx}, Loss: {loss.item():.4f}")

        avg_train_loss = train_loss / len(train_loader)

        # Validation
        model.eval()
        val_loss = 0
        with torch.no_grad():
            for input_ids, target_ids in val_loader:
                input_ids = input_ids.to(device)
                target_ids = target_ids.to(device)
                logits = model(input_ids)
                loss = criterion(logits.view(-1, 78), target_ids.view(-1))
                val_loss += loss.item()

        avg_val_loss = val_loss / len(val_loader)
        print(f"Epoch {epoch+1}/5, Train Loss: {avg_train_loss:.4f}, Val Loss: {avg_val_loss:.4f}")

    # Save
    model_path = model_dir / 'minimal_lm.pt'
    torch.save({
        'model_state_dict': model.state_dict(),
        'vocab_size': 78,
        'd_model': 256,
        'n_layers': 6,
        'seq_len': 32,
    }, model_path)
    print(f"\nSaved model to {model_path}")

    # Export to Core ML
    print("\nExporting to Core ML...")
    model.eval()
    model = model.to('cpu')

    example_input = torch.randint(0, 78, (1, 32))

    # Wrapper to return only last position
    class ExportWrapper(nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model

        def forward(self, x):
            return self.model(x)[:, -1, :]

    wrapper = ExportWrapper(model)
    wrapper.eval()

    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example_input)

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

    output_path = model_dir / 'LatinLM.mlpackage'
    mlmodel.save(str(output_path))
    print(f"Saved Core ML model to {output_path}")

    # Check size
    import subprocess
    result = subprocess.run(['du', '-sh', str(output_path)], capture_output=True, text=True)
    print(f"Model size: {result.stdout.strip().split()[0]}")

    print("\nDone!")


if __name__ == '__main__':
    train()
