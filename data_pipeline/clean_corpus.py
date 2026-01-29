#!/usr/bin/env python3
"""
Latin Corpus Cleaner for Latinum Keyboard

This module cleans and normalizes the Latin corpus for training:
- Strips non-printable characters
- Normalizes macrons (ā → a) for model training
- Normalizes ligatures (æ → ae) for model training
- Removes metadata artifacts
- Handles punctuation and casing
- Segments into sentences
"""

import re
import unicodedata
from pathlib import Path
from typing import Iterator

# Macron mappings (vowels with macrons → base vowels)
MACRON_MAP = {
    'ā': 'a', 'ē': 'e', 'ī': 'i', 'ō': 'o', 'ū': 'u', 'ȳ': 'y',
    'Ā': 'A', 'Ē': 'E', 'Ī': 'I', 'Ō': 'O', 'Ū': 'U', 'Ȳ': 'Y',
    # Breve variants (sometimes found in Latin texts)
    'ă': 'a', 'ĕ': 'e', 'ĭ': 'i', 'ŏ': 'o', 'ŭ': 'u',
    'Ă': 'A', 'Ĕ': 'E', 'Ĭ': 'I', 'Ŏ': 'O', 'Ŭ': 'U',
}

# Ligature mappings
LIGATURE_MAP = {
    'æ': 'ae', 'Æ': 'Ae',
    'œ': 'oe', 'Œ': 'Oe',
    'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬀ': 'ff', 'ﬃ': 'ffi', 'ﬄ': 'ffl',
}

# Metadata patterns to remove (common in Latin corpora)
METADATA_PATTERNS = [
    r'^The Latin Library\s*$',
    r'^The Classics Page\s*$',
    r'^Christian Latin\s*$',
    r'^The Miscellany\s*$',
    r'^\s*\[?\d+\]?\s*$',  # Line numbers like [1] or just numbers
    r'^[IVXLCDMivxlcdm]+\.\s*$',  # Roman numerals alone (section markers)
    r'^\s*$',  # Empty lines
]

# Characters valid in Latin text (expanded for classical and medieval Latin)
LATIN_CHARS = set('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ')
PUNCTUATION = set('.,;:!?\'"-()[]{}')
WHITESPACE = set(' \t\n')


def strip_macrons(text: str) -> str:
    """Remove macrons from vowels, preserving base characters."""
    for macron, base in MACRON_MAP.items():
        text = text.replace(macron, base)
    return text


def normalize_ligatures(text: str) -> str:
    """Expand ligatures to their component letters."""
    for ligature, expansion in LIGATURE_MAP.items():
        text = text.replace(ligature, expansion)
    return text


def remove_non_printable(text: str) -> str:
    """Remove non-printable and control characters."""
    # Keep only printable characters and common whitespace
    result = []
    for char in text:
        if char in WHITESPACE:
            result.append(char)
        elif unicodedata.category(char)[0] not in ('C', 'Z') or char == ' ':
            # C = control, Z = separator (except space)
            result.append(char)
    return ''.join(result)


def normalize_whitespace(text: str) -> str:
    """Normalize whitespace: collapse multiple spaces, trim lines."""
    # Replace tabs with spaces
    text = text.replace('\t', ' ')
    # Collapse multiple spaces
    text = re.sub(r' +', ' ', text)
    # Trim each line
    lines = [line.strip() for line in text.split('\n')]
    return '\n'.join(lines)


def is_metadata_line(line: str) -> bool:
    """Check if a line is metadata to be removed."""
    for pattern in METADATA_PATTERNS:
        if re.match(pattern, line, re.IGNORECASE):
            return True
    return False


def normalize_unicode(text: str) -> str:
    """Normalize Unicode to NFC form and handle special characters."""
    text = unicodedata.normalize('NFC', text)

    # Replace various quote styles with standard ASCII
    text = re.sub(r'[""„‟]', '"', text)
    text = re.sub(r"[''‚‛]", "'", text)

    # Replace various dashes with standard hyphen
    text = re.sub(r'[–—―]', '-', text)

    # Replace ellipsis
    text = text.replace('…', '...')

    return text


def filter_latin_content(text: str, min_latin_ratio: float = 0.5) -> str:
    """Filter out lines that don't appear to be Latin."""
    lines = text.split('\n')
    filtered = []

    for line in lines:
        if not line.strip():
            continue

        # Count Latin letters vs total letters
        letters = [c for c in line.lower() if c.isalpha()]
        if not letters:
            continue

        latin_count = sum(1 for c in letters if c in LATIN_CHARS or c in 'jw')
        ratio = latin_count / len(letters) if letters else 0

        if ratio >= min_latin_ratio:
            filtered.append(line)

    return '\n'.join(filtered)


def clean_line(line: str) -> str:
    """Apply all cleaning steps to a single line."""
    # Skip metadata
    if is_metadata_line(line):
        return ''

    # Remove non-printable characters
    line = remove_non_printable(line)

    # Normalize Unicode
    line = normalize_unicode(line)

    # Strip macrons (for model training)
    line = strip_macrons(line)

    # Normalize ligatures (for model training)
    line = normalize_ligatures(line)

    # Normalize whitespace
    line = normalize_whitespace(line)

    return line.strip()


def segment_into_sentences(text: str) -> Iterator[str]:
    """Segment text into sentences for training."""
    # Split on sentence-ending punctuation followed by space or newline
    # Keep the punctuation with the sentence
    sentence_pattern = re.compile(r'([.!?]+)\s+')

    current = []
    for line in text.split('\n'):
        if not line.strip():
            if current:
                yield ' '.join(current)
                current = []
            continue

        # Split line into potential sentences
        parts = sentence_pattern.split(line)

        i = 0
        while i < len(parts):
            part = parts[i].strip()
            if part:
                current.append(part)
                # If next part is punctuation, append it
                if i + 1 < len(parts) and re.match(r'^[.!?]+$', parts[i + 1]):
                    current[-1] += parts[i + 1]
                    i += 1
                    # Yield complete sentence
                    yield ' '.join(current)
                    current = []
            i += 1

    # Yield any remaining content
    if current:
        yield ' '.join(current)


def clean_corpus(input_path: Path, output_path: Path,
                 min_line_length: int = 10,
                 min_latin_ratio: float = 0.7) -> dict:
    """
    Clean the entire corpus file.

    Args:
        input_path: Path to raw corpus file
        output_path: Path to write cleaned output
        min_line_length: Minimum characters per line to keep
        min_latin_ratio: Minimum ratio of Latin characters

    Returns:
        Statistics dictionary
    """
    stats = {
        'lines_read': 0,
        'lines_written': 0,
        'chars_input': 0,
        'chars_output': 0,
        'sentences': 0,
    }

    with open(input_path, 'r', encoding='utf-8', errors='replace') as f:
        raw_text = f.read()

    stats['chars_input'] = len(raw_text)
    stats['lines_read'] = raw_text.count('\n') + 1

    # Clean line by line
    cleaned_lines = []
    for line in raw_text.split('\n'):
        cleaned = clean_line(line)
        if cleaned and len(cleaned) >= min_line_length:
            cleaned_lines.append(cleaned)

    # Join and filter for Latin content
    cleaned_text = '\n'.join(cleaned_lines)
    cleaned_text = filter_latin_content(cleaned_text, min_latin_ratio)

    # Segment into sentences
    sentences = list(segment_into_sentences(cleaned_text))
    stats['sentences'] = len(sentences)

    # Write output
    with open(output_path, 'w', encoding='utf-8') as f:
        for sentence in sentences:
            if sentence.strip():
                f.write(sentence + '\n')
                stats['lines_written'] += 1

    stats['chars_output'] = sum(len(s) for s in sentences)

    return stats


def create_vocabulary(corpus_path: Path, output_path: Path,
                      min_freq: int = 5) -> dict:
    """
    Create character and word frequency vocabularies.

    Args:
        corpus_path: Path to cleaned corpus
        output_path: Path to write vocabulary file
        min_freq: Minimum frequency to include

    Returns:
        Vocabulary statistics
    """
    from collections import Counter

    char_freq = Counter()
    word_freq = Counter()

    with open(corpus_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            char_freq.update(line)
            # Simple word tokenization
            words = re.findall(r"[a-zA-Z]+(?:[''-][a-zA-Z]+)*", line.lower())
            word_freq.update(words)

    # Filter by frequency
    chars = [(c, f) for c, f in char_freq.most_common() if f >= min_freq]
    words = [(w, f) for w, f in word_freq.most_common() if f >= min_freq]

    # Write vocabulary file
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write("# Character Vocabulary\n")
        for char, freq in chars:
            if char.strip():
                f.write(f"CHAR\t{repr(char)}\t{freq}\n")

        f.write("\n# Word Vocabulary (top 10000)\n")
        for word, freq in words[:10000]:
            f.write(f"WORD\t{word}\t{freq}\n")

    return {
        'unique_chars': len(chars),
        'unique_words': len(words),
        'total_chars': sum(f for _, f in chars),
        'total_words': sum(f for _, f in words),
    }


if __name__ == '__main__':
    import sys

    # Default paths
    script_dir = Path(__file__).parent
    project_dir = script_dir.parent

    input_path = project_dir / 'latincorpus.txt'
    output_path = project_dir / 'data_pipeline' / 'cleaned_corpus.txt'
    vocab_path = project_dir / 'data_pipeline' / 'vocabulary.txt'

    if len(sys.argv) > 1:
        input_path = Path(sys.argv[1])
    if len(sys.argv) > 2:
        output_path = Path(sys.argv[2])

    print(f"Cleaning corpus: {input_path}")
    print(f"Output: {output_path}")

    # Clean the corpus
    stats = clean_corpus(input_path, output_path)

    print("\n=== Cleaning Statistics ===")
    print(f"Lines read:    {stats['lines_read']:,}")
    print(f"Lines written: {stats['lines_written']:,}")
    print(f"Chars input:   {stats['chars_input']:,}")
    print(f"Chars output:  {stats['chars_output']:,}")
    print(f"Sentences:     {stats['sentences']:,}")
    print(f"Compression:   {100 * (1 - stats['chars_output']/stats['chars_input']):.1f}%")

    # Create vocabulary
    print(f"\nCreating vocabulary: {vocab_path}")
    vocab_stats = create_vocabulary(output_path, vocab_path)

    print("\n=== Vocabulary Statistics ===")
    print(f"Unique chars: {vocab_stats['unique_chars']:,}")
    print(f"Unique words: {vocab_stats['unique_words']:,}")
    print(f"Total chars:  {vocab_stats['total_chars']:,}")
    print(f"Total words:  {vocab_stats['total_words']:,}")
