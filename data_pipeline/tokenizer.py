#!/usr/bin/env python3
"""
BPE Tokenizer for Latin Keyboard

This tokenizer uses Byte-Pair Encoding (BPE) optimized for Latin:
- Character-level base vocabulary (allows any position completion)
- Learns common morphological patterns (inflections, enclitics)
- Small vocabulary suitable for on-device inference
- Supports incremental encoding for keystroke-by-keystroke prediction

Design rationale:
- Latin has ~26 base letters + punctuation = small character vocab
- BPE merges learn frequent patterns like "-que", "-orum", "-ibus"
- Subword approach handles unseen words via decomposition
- Vocabulary size ~2000-4000 is optimal for keyboard use
"""

import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple


class LatinBPETokenizer:
    """
    BPE tokenizer optimized for Latin text prediction.

    Special tokens:
        <pad>: Padding token (id=0)
        <unk>: Unknown token (id=1)
        <bos>: Beginning of sequence (id=2)
        <eos>: End of sequence (id=3)
        <space>: Explicit space marker (id=4)
    """

    # Special token constants
    PAD_TOKEN = "<pad>"
    UNK_TOKEN = "<unk>"
    BOS_TOKEN = "<bos>"
    EOS_TOKEN = "<eos>"
    SPACE_TOKEN = "<space>"

    # Base Latin characters (what the keyboard can produce)
    BASE_CHARS = set(
        "abcdefghijklmnopqrstuvwxyz"
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        "0123456789"
        ".,;:!?'-\"()"
    )

    def __init__(self, vocab_size: int = 2000):
        """
        Initialize tokenizer.

        Args:
            vocab_size: Target vocabulary size (including special tokens)
        """
        self.vocab_size = vocab_size

        # Token to ID mapping
        self.token_to_id: Dict[str, int] = {}
        self.id_to_token: Dict[int, str] = {}

        # BPE merge rules (pair -> merged token)
        self.merges: List[Tuple[str, str]] = []

        # Initialize with special tokens
        self._init_special_tokens()

    def _init_special_tokens(self):
        """Initialize special tokens at fixed positions."""
        special = [
            self.PAD_TOKEN,
            self.UNK_TOKEN,
            self.BOS_TOKEN,
            self.EOS_TOKEN,
            self.SPACE_TOKEN,
        ]
        for i, token in enumerate(special):
            self.token_to_id[token] = i
            self.id_to_token[i] = token

    def _get_word_freqs(self, corpus_path: Path) -> Counter:
        """
        Count word frequencies in corpus.

        Words are split by whitespace and stored with explicit
        end-of-word marker for proper BPE learning.
        """
        word_freqs = Counter()

        with open(corpus_path, 'r', encoding='utf-8') as f:
            for line in f:
                # Split on whitespace
                words = line.strip().split()
                for word in words:
                    # Filter to Latin characters only
                    word = ''.join(c for c in word if c in self.BASE_CHARS)
                    if word:
                        # Add end-of-word marker
                        word_freqs[word + '</w>'] += 1

        return word_freqs

    def _get_pair_freqs(
        self, word_freqs: Dict[str, int], word_splits: Dict[str, List[str]]
    ) -> Counter:
        """Count frequencies of adjacent token pairs."""
        pair_freqs = Counter()

        for word, freq in word_freqs.items():
            symbols = word_splits[word]
            for i in range(len(symbols) - 1):
                pair = (symbols[i], symbols[i + 1])
                pair_freqs[pair] += freq

        return pair_freqs

    def _merge_pair(
        self,
        pair: Tuple[str, str],
        word_splits: Dict[str, List[str]]
    ) -> Dict[str, List[str]]:
        """Merge a pair of tokens in all word splits."""
        new_token = pair[0] + pair[1]
        new_splits = {}

        for word, symbols in word_splits.items():
            new_symbols = []
            i = 0
            while i < len(symbols):
                if (i < len(symbols) - 1 and
                        symbols[i] == pair[0] and
                        symbols[i + 1] == pair[1]):
                    new_symbols.append(new_token)
                    i += 2
                else:
                    new_symbols.append(symbols[i])
                    i += 1
            new_splits[word] = new_symbols

        return new_splits

    def train(self, corpus_path: Path, min_freq: int = 2) -> Dict:
        """
        Train BPE tokenizer on corpus.

        Args:
            corpus_path: Path to cleaned corpus file
            min_freq: Minimum pair frequency to merge

        Returns:
            Training statistics dictionary
        """
        print(f"Training BPE tokenizer (vocab_size={self.vocab_size})...")

        # Get word frequencies
        print("  Counting word frequencies...")
        word_freqs = self._get_word_freqs(corpus_path)
        print(f"  Found {len(word_freqs):,} unique words")

        # Initialize word splits as characters
        word_splits = {}
        for word in word_freqs:
            word_splits[word] = list(word)

        # Build initial character vocabulary
        print("  Building character vocabulary...")
        char_vocab = set()
        for word in word_freqs:
            char_vocab.update(word)

        # Add characters to vocabulary
        next_id = len(self.token_to_id)
        for char in sorted(char_vocab):
            if char not in self.token_to_id:
                self.token_to_id[char] = next_id
                self.id_to_token[next_id] = char
                next_id += 1

        initial_vocab_size = next_id
        print(f"  Initial vocabulary: {initial_vocab_size} tokens")

        # Learn BPE merges
        print("  Learning BPE merges...")
        num_merges = self.vocab_size - initial_vocab_size
        merge_count = 0

        while merge_count < num_merges:
            # Get pair frequencies
            pair_freqs = self._get_pair_freqs(word_freqs, word_splits)

            if not pair_freqs:
                break

            # Find most frequent pair
            best_pair = pair_freqs.most_common(1)[0]
            pair, freq = best_pair

            if freq < min_freq:
                break

            # Merge the pair
            new_token = pair[0] + pair[1]
            word_splits = self._merge_pair(pair, word_splits)

            # Add to vocabulary and merges
            self.merges.append(pair)
            if new_token not in self.token_to_id:
                self.token_to_id[new_token] = next_id
                self.id_to_token[next_id] = new_token
                next_id += 1
                merge_count += 1

            if merge_count % 100 == 0:
                print(f"    Merge {merge_count}: {pair[0]}+{pair[1]} "
                      f"-> {new_token} (freq={freq})")

        print(f"  Final vocabulary: {len(self.token_to_id)} tokens")
        print(f"  Learned {len(self.merges)} merges")

        return {
            'vocab_size': len(self.token_to_id),
            'num_merges': len(self.merges),
            'unique_words': len(word_freqs),
        }

    def encode(self, text: str) -> List[int]:
        """
        Encode text to token IDs.

        Args:
            text: Input text to encode

        Returns:
            List of token IDs
        """
        if not text:
            return []

        ids = []

        # Split into words
        words = text.split(' ')

        for i, word in enumerate(words):
            if not word:
                continue

            # Add space before word (except first)
            if i > 0:
                ids.append(self.token_to_id[self.SPACE_TOKEN])

            # Tokenize word
            word_ids = self._encode_word(word)
            ids.extend(word_ids)

        return ids

    def _encode_word(self, word: str) -> List[int]:
        """Encode a single word using BPE."""
        # Filter to known characters
        word = ''.join(c for c in word if c in self.BASE_CHARS)
        if not word:
            return [self.token_to_id[self.UNK_TOKEN]]

        # Add end-of-word marker
        word = word + '</w>'

        # Start with characters
        symbols = list(word)

        # Apply merges in order
        for pair in self.merges:
            i = 0
            while i < len(symbols) - 1:
                if symbols[i] == pair[0] and symbols[i + 1] == pair[1]:
                    symbols = symbols[:i] + [pair[0] + pair[1]] + symbols[i + 2:]
                else:
                    i += 1

        # Convert to IDs
        ids = []
        for symbol in symbols:
            if symbol in self.token_to_id:
                ids.append(self.token_to_id[symbol])
            else:
                # Unknown subword - encode char by char
                for char in symbol:
                    if char in self.token_to_id:
                        ids.append(self.token_to_id[char])
                    else:
                        ids.append(self.token_to_id[self.UNK_TOKEN])

        return ids

    def encode_for_completion(self, prefix: str) -> List[int]:
        """
        Encode text prefix for completion prediction.

        Unlike regular encoding, this doesn't add end-of-word markers
        since we're predicting the continuation.
        """
        if not prefix:
            return [self.token_to_id[self.BOS_TOKEN]]

        # Split into complete words and current word being typed
        parts = prefix.split(' ')
        ids = [self.token_to_id[self.BOS_TOKEN]]

        for i, part in enumerate(parts):
            if not part:
                continue

            # Add space before word (except first)
            if i > 0 or prefix.startswith(' '):
                ids.append(self.token_to_id[self.SPACE_TOKEN])

            if i < len(parts) - 1:
                # Complete word - encode normally
                word_ids = self._encode_word(part)
                ids.extend(word_ids)
            else:
                # Partial word - encode without end marker
                word_ids = self._encode_partial_word(part)
                ids.extend(word_ids)

        return ids

    def _encode_partial_word(self, word: str) -> List[int]:
        """Encode a partial word (no end-of-word marker)."""
        # Filter to known characters
        word = ''.join(c for c in word if c in self.BASE_CHARS)
        if not word:
            return []

        # Start with characters (no </w>)
        symbols = list(word)

        # Apply merges that don't involve </w>
        for pair in self.merges:
            if '</w>' in pair[0] or '</w>' in pair[1]:
                continue
            i = 0
            while i < len(symbols) - 1:
                if symbols[i] == pair[0] and symbols[i + 1] == pair[1]:
                    symbols = symbols[:i] + [pair[0] + pair[1]] + symbols[i + 2:]
                else:
                    i += 1

        # Convert to IDs
        ids = []
        for symbol in symbols:
            if symbol in self.token_to_id:
                ids.append(self.token_to_id[symbol])
            else:
                for char in symbol:
                    if char in self.token_to_id:
                        ids.append(self.token_to_id[char])
                    else:
                        ids.append(self.token_to_id[self.UNK_TOKEN])

        return ids

    def decode(self, ids: List[int]) -> str:
        """
        Decode token IDs back to text.

        Args:
            ids: List of token IDs

        Returns:
            Decoded text string
        """
        tokens = []
        for id_ in ids:
            if id_ in self.id_to_token:
                token = self.id_to_token[id_]
                if token == self.SPACE_TOKEN:
                    tokens.append(' ')
                elif token not in (self.PAD_TOKEN, self.BOS_TOKEN,
                                   self.EOS_TOKEN, self.UNK_TOKEN):
                    tokens.append(token)

        # Join and remove end-of-word markers
        text = ''.join(tokens)
        text = text.replace('</w>', '')

        return text

    def get_vocab_for_prefix(self, prefix_ids: List[int]) -> List[Tuple[int, str]]:
        """
        Get vocabulary items that could follow a prefix.

        This is used for efficient beam search during completion.

        Returns:
            List of (token_id, token_string) tuples
        """
        # For now, return all non-special tokens
        # A more sophisticated implementation would use a trie
        valid = []
        for id_, token in self.id_to_token.items():
            if token not in (self.PAD_TOKEN, self.BOS_TOKEN):
                valid.append((id_, token))
        return valid

    def save(self, path: Path):
        """Save tokenizer to file."""
        data = {
            'vocab_size': self.vocab_size,
            'token_to_id': self.token_to_id,
            'merges': self.merges,
        }

        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        print(f"Saved tokenizer to {path}")

    @classmethod
    def load(cls, path: Path) -> 'LatinBPETokenizer':
        """Load tokenizer from file."""
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        tokenizer = cls(vocab_size=data['vocab_size'])
        tokenizer.token_to_id = data['token_to_id']
        tokenizer.id_to_token = {int(k): v for k, v in
                                  {v: k for k, v in data['token_to_id'].items()}.items()}
        # Rebuild id_to_token properly
        tokenizer.id_to_token = {v: k for k, v in tokenizer.token_to_id.items()}
        tokenizer.merges = [tuple(m) for m in data['merges']]

        return tokenizer

    def export_for_swift(self, path: Path):
        """Export tokenizer data for Swift implementation."""
        # Create compact format for iOS
        swift_data = {
            'vocab': list(self.token_to_id.items()),
            'merges': [[p[0], p[1]] for p in self.merges],
        }

        with open(path, 'w', encoding='utf-8') as f:
            json.dump(swift_data, f, ensure_ascii=False)

        print(f"Exported Swift tokenizer data to {path}")


def analyze_tokenizer(tokenizer: LatinBPETokenizer, corpus_path: Path):
    """Analyze tokenizer quality on corpus."""
    print("\n=== Tokenizer Analysis ===")

    # Sample some lines
    with open(corpus_path, 'r', encoding='utf-8') as f:
        lines = [next(f).strip() for _ in range(10)]

    print("\nSample tokenizations:")
    for line in lines[:5]:
        if len(line) > 60:
            line = line[:60] + "..."
        ids = tokenizer.encode(line[:60])
        tokens = [tokenizer.id_to_token.get(i, '?') for i in ids]
        print(f"  Input: {line}")
        print(f"  Tokens: {tokens}")
        print(f"  IDs: {ids}")
        print()

    # Analyze compression
    total_chars = 0
    total_tokens = 0

    with open(corpus_path, 'r', encoding='utf-8') as f:
        for i, line in enumerate(f):
            if i >= 1000:
                break
            line = line.strip()
            total_chars += len(line)
            total_tokens += len(tokenizer.encode(line))

    print(f"Compression ratio: {total_chars / total_tokens:.2f} chars/token")

    # Show common learned patterns
    print("\nTop learned merges (morphological patterns):")
    for i, (a, b) in enumerate(tokenizer.merges[:20]):
        merged = a + b
        print(f"  {i+1}. {a!r} + {b!r} -> {merged!r}")


if __name__ == '__main__':
    import sys

    script_dir = Path(__file__).parent
    corpus_path = script_dir / 'cleaned_corpus.txt'
    tokenizer_path = script_dir / 'tokenizer.json'
    swift_path = script_dir / 'tokenizer_swift.json'

    # Train tokenizer
    tokenizer = LatinBPETokenizer(vocab_size=2000)
    stats = tokenizer.train(corpus_path, min_freq=5)

    print("\n=== Training Statistics ===")
    for key, value in stats.items():
        print(f"  {key}: {value:,}")

    # Save tokenizer
    tokenizer.save(tokenizer_path)
    tokenizer.export_for_swift(swift_path)

    # Analyze
    analyze_tokenizer(tokenizer, corpus_path)

    # Test completion encoding
    print("\n=== Completion Encoding Test ===")
    test_prefixes = ["am", "ama", "amar", "amare", "Roma", "domin"]
    for prefix in test_prefixes:
        ids = tokenizer.encode_for_completion(prefix)
        print(f"  '{prefix}' -> {ids}")
