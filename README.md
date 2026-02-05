# Latinum — Predictive Latin Keyboard for iOS

A fully offline Latin keyboard with word completion and next-word prediction, built on n-gram frequency data extracted from a classical Latin corpus.

## Features

- **Word completion** — frequency-ranked suggestions as you type (binary search on 50K-word list)
- **Next-word prediction** — trigram → bigram → unigram fallback chain
- **Macron & ligature input** — long-press vowels for ā ē ī ō ū, or æ œ
- **Diacritic preservation** — user-typed macrons carry through into completions
- **Word highlight correction** — select a word to see alternative completions
- **Fully offline** — no network access, no data collection, all inference on-device

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  KeyboardViewController                              │
│    ├─ input handling, shift/caps, debounced updates   │
│    └─ word-highlight trigger (selectedText)           │
├──────────────────────────────────────────────────────┤
│  PredictionEngine                                    │
│    ├─ async dispatch on serial inference queue        │
│    ├─ merges & deduplicates across sources            │
│    └─ macron/ligature preservation via LatinNorm.     │
├──────────────────────────────────────────────────────┤
│  PredictionSource chain (queried in order):          │
│    1. FrequencyCompletionSource  (prefix completion) │
│    2. NGramPredictionSource      (next-word)         │
│    3. FallbackPredictionSource   (hardcoded ~120 w.) │
└──────────────────────────────────────────────────────┘
```

**Data files** (bundled as JSON, ~3.3 MB combined):

| File | Contents | Lookup |
|---|---|---|
| `word_frequencies.json` | 50K words sorted by corpus frequency | Binary search on alphabetically sorted array |
| `ngrams.json` | 94K unigrams, 50K bigrams, 30K trigrams | Dictionary indexed by preceding word(s) |

Runtime memory: ~8–14 MB, well within the 30 MB keyboard extension limit.

## Project Structure

```
latinum/
├── data_pipeline/
│   ├── clean_corpus.py       # Corpus cleaning & sentence segmentation
│   ├── normalization.py      # Macron/ligature mappings (canonical source)
│   └── extract_ngrams.py     # Generates word_frequencies.json & ngrams.json
├── iOS/
│   ├── Latinum/              # Host app (setup instructions)
│   ├── LatinumKeyboard/      # Keyboard extension
│   │   ├── KeyboardViewController.swift
│   │   ├── PredictionEngine.swift
│   │   ├── FrequencyCompletionSource.swift
│   │   ├── NGramPredictionSource.swift
│   │   ├── LatinNormalization.swift
│   │   └── Resources/       # word_frequencies.json, ngrams.json
│   ├── LatinumTests/         # Unit tests
│   └── project.yml           # XcodeGen project spec
├── latincorpus.txt           # Raw Latin corpus (~29 MB)
└── tests/                    # Python tests
```

## Requirements

- macOS 14+, Xcode 15+
- iOS 17+ deployment target
- Python 3.10+ (data pipeline only)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Quick Start

```bash
# 1. Generate prediction data from the corpus
python3 data_pipeline/extract_ngrams.py

# 2. Generate the Xcode project
cd iOS && xcodegen generate

# 3. Build & run
open Latinum.xcodeproj   # Build to device, then:
# Settings → General → Keyboard → Keyboards → Add "Latinum"
```

## Running Tests

```bash
# iOS (Xcode)
xcodebuild -project iOS/Latinum.xcodeproj -scheme Latinum \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# Python
python3 data_pipeline/normalization.py
```

## License

Copyright 2026 Dylan Walker Brown<br>
Licensed under the Apache License, Version 2.0.

The works in the Latin corpus are in the public domain.<br>
Thanks to William L. Carey for making these works available at [The Latin Library](https://www.thelatinlibrary.com).<br>
Thanks to [Mathis Van Eetvelde](https://github.com/mathisve) for compiling these works into `latincorpus.txt`.
