# Tool Manifest

This file tracks external tools required by the Latinum project.

## Required Tools

### Available
- [x] `python3` (3.14.2) - Data processing and model training
- [x] `xcodegen` - iOS project generation
- [x] `torch` (PyTorch 2.7.0) - Deep learning framework
- [x] `coremltools` (9.0) - Core ML model conversion

### Optional
- [ ] `sentencepiece` - Alternative tokenization (optional)
  - Install: `pip3 install sentencepiece`

## Virtual Environment

A virtual environment is set up at `.venv/` with all required packages:

```bash
# Activate the virtual environment
source .venv/bin/activate

# Or run scripts directly with .venv/bin/python
.venv/bin/python model/train.py
```

## Installation Instructions

To recreate the virtual environment:
```bash
uv venv .venv
uv pip install torch==2.7.0 coremltools
```

Note: PyTorch 2.7.0 is required for coremltools compatibility.
