#!/usr/bin/env python3
"""
Extract word frequencies and n-gram tables from the Latin corpus.

Reads latincorpus.txt, applies the existing cleaning/normalization pipeline,
and outputs two JSON files for the iOS keyboard extension:

  word_frequencies.json  - sorted list of [word, count] pairs
  ngrams.json            - unigram, bigram, and trigram frequency tables

Enclitic-aware: splits -que, -ve, -ne from host words and stores both forms.
"""

import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Dict, List, Tuple

# Import shared normalization and cleaning utilities
sys.path.insert(0, str(Path(__file__).parent))
from clean_corpus import (
    clean_line,
    strip_macrons,
    normalize_ligatures,
)
from normalization import LATIN_ENCLITICS

# Enclitics to split (without the leading hyphen, lowercased)
ENCLITICS = ("que", "ve", "ne")


def tokenize_line(line: str) -> List[str]:
    """
    Tokenize a cleaned line into lowercase words.

    Strips macrons and ligatures, lowercases, and extracts Latin word tokens.
    """
    line = strip_macrons(line)
    line = normalize_ligatures(line)
    line = line.lower()
    return re.findall(r"[a-z]+", line)


def split_enclitics(word: str) -> Tuple[str, str] | None:
    """
    If *word* ends with a known enclitic, return (base, enclitic).
    Returns None if no enclitic is detected or the base would be too short.
    """
    for enc in ENCLITICS:
        if word.endswith(enc) and len(word) > len(enc) + 1:
            base = word[: -len(enc)]
            return base, enc
    return None


def extract(
    corpus_path: Path,
    min_ngram_count: int = 3,
    max_words: int = 50000,
    max_bigrams: int = 50000,
    max_trigrams: int = 30000,
) -> Tuple[
    List[Tuple[str, int]],
    Dict[str, Dict],
]:
    """
    Read the corpus and return (word_freq_list, ngram_tables).

    word_freq_list: [(word, count), ...] sorted by descending frequency.
    ngram_tables: {
        "unigrams": {word: count},
        "bigrams":  {"w1 w2": count},
        "trigrams": {"w1 w2 w3": count},
    }
    """
    word_counter: Counter = Counter()
    unigram_counter: Counter = Counter()
    bigram_counter: Counter = Counter()
    trigram_counter: Counter = Counter()

    with open(corpus_path, "r", encoding="utf-8", errors="replace") as fh:
        for raw_line in fh:
            cleaned = clean_line(raw_line)
            if not cleaned or len(cleaned) < 5:
                continue

            tokens = tokenize_line(cleaned)
            if not tokens:
                continue

            # Expand enclitics into the token stream for n-grams,
            # but also count the combined form in word_counter.
            expanded_tokens: List[str] = []
            for tok in tokens:
                word_counter[tok] += 1
                parts = split_enclitics(tok)
                if parts:
                    base, enc = parts
                    word_counter[base] += 1
                    expanded_tokens.append(base)
                    expanded_tokens.append(enc)
                else:
                    expanded_tokens.append(tok)

            # N-gram counting on the expanded stream
            for w in expanded_tokens:
                unigram_counter[w] += 1

            for i in range(len(expanded_tokens) - 1):
                key = f"{expanded_tokens[i]} {expanded_tokens[i+1]}"
                bigram_counter[key] += 1

            for i in range(len(expanded_tokens) - 2):
                key = f"{expanded_tokens[i]} {expanded_tokens[i+1]} {expanded_tokens[i+2]}"
                trigram_counter[key] += 1

    # Sort word frequencies descending, keep top N
    word_freq_list = word_counter.most_common(max_words)

    # Prune n-grams below threshold, keep top N of each
    unigrams = {w: c for w, c in unigram_counter.most_common()
                if c >= min_ngram_count}
    bigrams = dict(
        sorted(
            ((k, c) for k, c in bigram_counter.items() if c >= min_ngram_count),
            key=lambda x: -x[1],
        )[:max_bigrams]
    )
    trigrams = dict(
        sorted(
            ((k, c) for k, c in trigram_counter.items() if c >= min_ngram_count),
            key=lambda x: -x[1],
        )[:max_trigrams]
    )

    ngram_tables = {
        "unigrams": dict(sorted(unigrams.items(), key=lambda x: -x[1])),
        "bigrams": bigrams,
        "trigrams": trigrams,
    }

    return word_freq_list, ngram_tables


def main():
    project_dir = Path(__file__).resolve().parent.parent
    corpus_path = project_dir / "latincorpus.txt"
    output_dir = project_dir / "iOS" / "LatinumKeyboard" / "Resources"

    if len(sys.argv) > 1:
        corpus_path = Path(sys.argv[1])

    if not corpus_path.exists():
        print(f"ERROR: corpus not found at {corpus_path}", file=sys.stderr)
        sys.exit(1)

    print(f"Reading corpus: {corpus_path}")
    word_freq_list, ngram_tables = extract(corpus_path)

    # --- word_frequencies.json ---
    freq_path = output_dir / "word_frequencies.json"
    with open(freq_path, "w", encoding="utf-8") as fh:
        json.dump(word_freq_list, fh, ensure_ascii=False, separators=(",", ":"))
    freq_size = freq_path.stat().st_size
    print(f"Wrote {freq_path.name}: {len(word_freq_list):,} words, {freq_size/1024/1024:.2f} MB")

    # --- ngrams.json ---
    ngram_path = output_dir / "ngrams.json"
    with open(ngram_path, "w", encoding="utf-8") as fh:
        json.dump(ngram_tables, fh, ensure_ascii=False, separators=(",", ":"))
    ngram_size = ngram_path.stat().st_size
    uni_count = len(ngram_tables["unigrams"])
    bi_count = len(ngram_tables["bigrams"])
    tri_count = len(ngram_tables["trigrams"])
    print(
        f"Wrote {ngram_path.name}: {uni_count:,} unigrams, "
        f"{bi_count:,} bigrams, {tri_count:,} trigrams, "
        f"{ngram_size/1024/1024:.2f} MB"
    )

    combined = freq_size + ngram_size
    print(f"\nCombined size: {combined/1024/1024:.2f} MB")
    if combined > 5 * 1024 * 1024:
        print("WARNING: Combined size exceeds 5 MB target. Consider pruning.")

    # Quick sanity check
    top10 = word_freq_list[:10]
    print(f"\nTop 10 words: {[w for w, _ in top10]}")


if __name__ == "__main__":
    main()
