# Latinum - Predictive Latin Keyboard for iOS

A fully offline, privacy-preserving Latin keyboard with intelligent word and inflection completion.

## Features

- **Native iOS keyboard layout** - Familiar QWERTY layout matching the system keyboard
- **Predictive completion** - Character-level language model trained on Latin corpus
- **Macron support** - Long-press vowels for macronized characters (ā, ē, ī, ō, ū)
- **Ligature support** - Long-press for Latin ligatures (æ, œ)
- **Macron preservation** - User-entered macrons are preserved in completions
- **Fully offline** - No network access, all inference on-device
- **Privacy first** - No data collection, no keystroke logging

## Project Structure

```
latinum-claude/
├── data_pipeline/          # Python scripts for corpus processing
│   ├── clean_corpus.py     # Corpus cleaning and normalization
│   ├── char_tokenizer.py   # Character-level tokenizer
│   ├── normalization.py    # Text normalization utilities
│   └── cleaned_corpus.txt  # Processed training data
├── model/                  # PyTorch model definition and training
│   ├── latin_lm.py         # Transformer language model
│   ├── train.py            # Training script
│   ├── export_coreml.py    # Core ML conversion
│   └── config.json         # Model configuration
├── iOS/                    # iOS application
│   ├── Latinum/            # Main app (setup instructions)
│   ├── LatinumKeyboard/    # Keyboard extension
│   ├── LatinumTests/       # Unit tests
│   └── project.yml         # XcodeGen configuration
├── tests/                  # Python unit tests
├── docs/                   # Documentation
├── latincorpus.txt        # Raw Latin corpus
└── tool_manifest.md       # Required tools
```

## Requirements

### For Training (macOS/Linux)
- Python 3.10+
- PyTorch 2.0+
- coremltools 7.0+

### For iOS Development
- macOS 13+
- Xcode 15+
- iOS 15+ deployment target

## Quick Start

### 1. Install Dependencies

```bash
# Python dependencies for training
pip3 install torch coremltools

# XcodeGen for project generation (if not installed)
brew install xcodegen
```

### 2. Process the Corpus

```bash
# Clean and tokenize the corpus
python3 data_pipeline/clean_corpus.py
python3 data_pipeline/char_tokenizer.py
```

### 3. Train the Model

```bash
# Train the language model (requires PyTorch)
python3 model/train.py

# Export to Core ML (requires coremltools)
python3 model/export_coreml.py
```

### 4. Build the iOS App

```bash
cd iOS

# Generate Xcode project
xcodegen generate

# Open in Xcode
open Latinum.xcodeproj
```

### 5. Install on Device

1. Build and run on your iOS device
2. Open Settings → General → Keyboard → Keyboards
3. Add New Keyboard → Latinum
4. Enable "Allow Full Access" for predictions

## Running Tests

### Python Tests

```bash
python3 tests/test_normalization.py
```

### iOS Tests

Open `iOS/Latinum.xcodeproj` in Xcode and run tests (⌘+U).

## Privacy

Latinum is designed with privacy as a core principle:

- **No network access**: The app has network access disabled at the Info.plist level
- **No data persistence**: Keystrokes are processed in memory only
- **No analytics**: No telemetry or usage tracking
- **Fully local**: All predictions run on-device using Core ML

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed technical documentation.

### Key Design Decisions

1. **Character-level modeling**: Enables completion at any position, handles Latin morphology naturally
2. **Small transformer**: ~816K parameters fits comfortably in keyboard extension memory limits
3. **Macron-free training**: Model operates on normalized text; user macrons preserved via post-processing
4. **Fallback word list**: Ensures functionality even if model fails to load

## Model Details

| Property | Value |
|----------|-------|
| Architecture | Transformer decoder |
| Parameters | ~816,000 |
| Vocabulary | 78 characters |
| Context length | 64 characters |
| Model size (FP16) | ~1.6 MB |

## License

This project is provided for educational purposes. The Latin corpus is in the public domain.

## Acknowledgments

- Latin corpus sourced from public domain texts
- Trained and optimized for Apple Neural Engine (ANE)
