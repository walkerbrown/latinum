# Latinum Keyboard Architecture

## Overview

Latinum is a predictive Latin keyboard for iOS that provides word and inflection completion. The system consists of:

1. **Data Pipeline** (Python) - Corpus cleaning, normalization, and tokenization
2. **Language Model** (PyTorch → Core ML) - Character-level transformer for prediction
3. **iOS Keyboard Extension** (Swift) - Native keyboard UI with Core ML inference

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Training Pipeline                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  latincorpus.txt                                                │
│        │                                                        │
│        ▼                                                        │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │ clean_corpus │ -> │  char_       │ -> │ training_    │      │
│  │    .py       │    │ tokenizer.py │    │ sequences.txt│      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                                                │                │
│                                                ▼                │
│                                        ┌──────────────┐         │
│                                        │  train.py    │         │
│                                        │ (PyTorch)    │         │
│                                        └──────────────┘         │
│                                                │                │
│                                                ▼                │
│                                        ┌──────────────┐         │
│                                        │ export_      │         │
│                                        │ coreml.py    │         │
│                                        └──────────────┘         │
│                                                │                │
│                                                ▼                │
│                                        LatinLM.mlpackage        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      iOS Keyboard Extension                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │              KeyboardViewController                     │     │
│  │  - Handles UIInputViewController lifecycle             │     │
│  │  - Manages text input/deletion                         │     │
│  │  - Coordinates predictions                             │     │
│  └────────────────────────────────────────────────────────┘     │
│                          │                                      │
│          ┌───────────────┴───────────────┐                     │
│          ▼                               ▼                      │
│  ┌────────────────┐             ┌─────────────────┐            │
│  │  KeyboardView  │             │ PredictionEngine│            │
│  │  - Key buttons │             │ - Core ML model │            │
│  │  - Long press  │             │ - Tokenization  │            │
│  │  - Prediction  │             │ - Normalization │            │
│  │    bar         │             │ - Fallback      │            │
│  └────────────────┘             └─────────────────┘            │
│          │                               │                      │
│          ▼                               ▼                      │
│  ┌────────────────┐             ┌─────────────────┐            │
│  │ Latin          │             │ Character       │            │
│  │ Normalization  │◄────────────│ Tokenizer       │            │
│  └────────────────┘             └─────────────────┘            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Data Pipeline

### Corpus Cleaning (`data_pipeline/clean_corpus.py`)

The corpus cleaner processes raw Latin text:

1. **Non-printable removal**: Strips control characters and escape sequences
2. **Unicode normalization**: NFC normalization, quote/dash standardization
3. **Macron stripping**: Removes all macrons (ā → a) for model training
4. **Ligature expansion**: Expands æ → ae, œ → oe
5. **Metadata filtering**: Removes "The Latin Library", page numbers, etc.
6. **Latin content validation**: Filters lines with <70% Latin characters
7. **Sentence segmentation**: Splits on sentence-ending punctuation

### Character Tokenizer (`data_pipeline/char_tokenizer.py`)

A simple character-level tokenizer optimized for keyboard prediction:

- **Vocabulary size**: 78 tokens
  - 5 special tokens: `<pad>`, `<unk>`, `<bos>`, `<eos>`, `<space>`
  - 52 letters (a-z, A-Z)
  - 11 punctuation marks
  - 10 digits

This small vocabulary enables efficient on-device inference.

### Training Data Generation

The tokenizer creates overlapping sequences for training:
- Sequence length: 64 characters
- Stride: 32 characters (50% overlap)
- Format: Space-separated token IDs, one sequence per line

## Language Model

### Architecture (`model/latin_lm.py`)

A small transformer decoder optimized for keyboard constraints:

| Hyperparameter | Value |
|---------------|-------|
| Vocabulary size | 78 |
| Embedding dimension | 128 |
| Attention heads | 4 |
| Transformer layers | 4 |
| Feed-forward dimension | 512 |
| Max sequence length | 64 |
| Dropout | 0.1 |

**Estimated size**: ~816K parameters, ~1.6MB (FP16)

### Training Objective

Standard causal language modeling (next character prediction):
- Loss: Cross-entropy
- Optimizer: AdamW with cosine LR schedule
- Gradient clipping: 1.0

### Core ML Export

The model is traced and converted to Core ML format:
- Compute precision: FP16
- Deployment target: iOS 15+
- Compute units: All (CPU/GPU/ANE selection automatic)

## iOS Keyboard Extension

### KeyboardViewController

The main input view controller:
- Inherits from `UIInputViewController`
- Manages `textDocumentProxy` for text input
- Coordinates keyboard view and prediction engine

### KeyboardView

Native iOS-style keyboard layout:
- QWERTY layout with standard key sizes
- Shift states: lowercase, uppercase, caps lock
- Long-press popups for macrons and ligatures
- Prediction bar with 3 suggestions

### Macron/Ligature Input

Long-press options for vowels:

| Key | Options |
|-----|---------|
| a/A | ā/Ā, æ/Æ |
| e/E | ē/Ē |
| i/I | ī/Ī |
| o/O | ō/Ō, œ/Œ |
| u/U | ū/Ū |
| y/Y | ȳ/Ȳ |

### Text Normalization

The `LatinNormalization` module handles:

1. **Model queries**: User input is normalized (macrons stripped, ligatures expanded) before querying the model
2. **Completion preservation**: User-entered macrons are preserved when applying completions

Example:
```
User types: "amā"
Normalized for model: "ama"
Model suggests: "amare"
Displayed to user: "amāre" (macron preserved)
```

### Prediction Engine

The prediction engine:
1. Loads the Core ML model at initialization
2. Encodes context using the character tokenizer
3. Runs inference to get next-character probabilities
4. Decodes top predictions
5. Applies macron preservation
6. Falls back to word list if model unavailable

### Fallback Strategy

When the model fails to load or memory is constrained:
- Uses a curated list of ~50 common Latin words
- Provides prefix-matching completions
- Ensures the keyboard remains functional

## Memory & Performance

### Keyboard Extension Limits

iOS keyboard extensions have strict constraints:
- Memory limit: ~30MB
- Must be responsive (<100ms per keystroke)

### Optimizations

1. **Small model**: ~1.6MB in FP16
2. **Character-level**: Small vocabulary (78) means small embedding tables
3. **Efficient tokenization**: O(n) encoding, no BPE merges at runtime
4. **Lazy loading**: Model loaded on first prediction, not at startup
5. **Caching**: Causal attention masks cached by sequence length

## Privacy Guarantees

1. **No network access**: `NSAllowsArbitraryLoads = false`
2. **No persistent storage**: No keystroke logging to disk
3. **No telemetry**: No analytics or data collection
4. **Fully offline**: All inference is local

These guarantees are enforced at the code level and documented in the app.
