#!/usr/bin/env python3
"""
Training Script for Latin Language Model

Run with:
    python3 model/train.py

Requirements:
    pip3 install torch

This script:
1. Loads the training data from data_pipeline/
2. Trains the character-level language model
3. Saves checkpoints to model/checkpoints/
4. Exports the final model for Core ML conversion
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    import torch
    from torch.utils.data import DataLoader, random_split
except ImportError:
    print("Error: PyTorch is required for training.")
    print("Install with: pip3 install torch")
    sys.exit(1)

from model.latin_lm import (
    ModelConfig, LatinLanguageModel, LatinDataset,
    train_model, print_model_info
)


def main():
    # Paths
    project_dir = Path(__file__).parent.parent
    data_dir = project_dir / 'data_pipeline'
    model_dir = project_dir / 'model'
    checkpoint_dir = model_dir / 'checkpoints'

    sequences_path = data_dir / 'training_sequences.txt'
    config_path = model_dir / 'config.json'

    # Check for training data
    if not sequences_path.exists():
        print(f"Error: Training sequences not found at {sequences_path}")
        print("Run data_pipeline/char_tokenizer.py first.")
        sys.exit(1)

    # Device selection
    if torch.cuda.is_available():
        device = 'cuda'
    elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
        device = 'mps'  # Apple Silicon
    else:
        device = 'cpu'
    print(f"Using device: {device}")

    # Model configuration
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

    # Load dataset
    print(f"\nLoading training data from {sequences_path}...")
    dataset = LatinDataset(sequences_path, seq_length=64)
    print(f"  Loaded {len(dataset):,} sequences")

    # Split into train/validation
    train_size = int(0.95 * len(dataset))
    val_size = len(dataset) - train_size
    train_dataset, val_dataset = random_split(dataset, [train_size, val_size])
    print(f"  Train: {len(train_dataset):,}, Val: {len(val_dataset):,}")

    # Data loaders
    train_loader = DataLoader(
        train_dataset,
        batch_size=64,
        shuffle=True,
        num_workers=0,  # Set to 0 for compatibility
        pin_memory=(device != 'cpu'),
    )
    val_loader = DataLoader(
        val_dataset,
        batch_size=64,
        shuffle=False,
        num_workers=0,
    )

    # Create model
    print("\nCreating model...")
    model = LatinLanguageModel(config)
    total_params = sum(p.numel() for p in model.parameters())
    print(f"  Total parameters: {total_params:,}")

    # Train
    print("\nStarting training...")
    stats = train_model(
        model=model,
        train_loader=train_loader,
        val_loader=val_loader,
        epochs=10,
        lr=3e-4,
        device=device,
        checkpoint_dir=checkpoint_dir,
    )

    # Save final model
    final_path = model_dir / 'latin_lm_final.pt'
    torch.save({
        'model_state_dict': model.state_dict(),
        'config': config.to_dict(),
    }, final_path)
    print(f"\nSaved final model to {final_path}")

    # Save config
    config.save(config_path)
    print(f"Saved config to {config_path}")

    # Training summary
    print("\n=== Training Summary ===")
    print(f"  Final train loss: {stats['train_loss'][-1]:.4f}")
    if stats['val_loss']:
        print(f"  Final val loss: {stats['val_loss'][-1]:.4f}")
    print(f"  Checkpoints saved to: {checkpoint_dir}")
    print(f"  Final model: {final_path}")

    print("\nNext steps:")
    print("  1. Run model/export_coreml.py to convert to Core ML")
    print("  2. Copy the .mlpackage to the iOS project")


if __name__ == '__main__':
    main()
