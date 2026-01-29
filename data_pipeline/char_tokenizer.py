#!/usr/bin/env python3
"""
Character-Level Tokenizer for Latin Keyboard

For a predictive keyboard, character-level modeling is ideal because:
1. Allows prediction at any character position
2. Small vocabulary (~50-100 tokens) enables efficient inference
3. Perfect for word completion (primary use case)
4. Simple and fast encoding/decoding

The model predicts P(next_char | previous_chars), which directly maps
to the keyboard's completion suggestions.
"""

import json
from collections import Counter
from pathlib import Path
from typing import Dict, List, Optional, Set


class CharacterTokenizer:
    """
    Character-level tokenizer for Latin text.

    Vocabulary:
        - Special tokens: <pad>, <unk>, <bos>, <eos>, <space>
        - Latin letters: a-z, A-Z
        - Common punctuation: .,;:!?'-"()
        - Digits: 0-9 (rare in Latin, but included)

    This tokenizer is extremely simple and fast, making it ideal
    for real-time keyboard prediction.
    """

    # Special tokens
    PAD = "<pad>"
    UNK = "<unk>"
    BOS = "<bos>"
    EOS = "<eos>"
    SPACE = " "

    # Character sets
    LOWERCASE = "abcdefghijklmnopqrstuvwxyz"
    UPPERCASE = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    DIGITS = "0123456789"
    PUNCTUATION = ".,;:!?'-\"()"

    def __init__(self):
        """Initialize tokenizer with fixed vocabulary."""
        self.char_to_id: Dict[str, int] = {}
        self.id_to_char: Dict[int, str] = {}
        self._build_vocab()

    def _build_vocab(self):
        """Build the character vocabulary."""
        vocab_items = [
            self.PAD,    # 0: padding
            self.UNK,    # 1: unknown
            self.BOS,    # 2: start of sequence
            self.EOS,    # 3: end of sequence
            self.SPACE,  # 4: space
        ]

        # Add lowercase letters (most common in Latin)
        vocab_items.extend(list(self.LOWERCASE))

        # Add uppercase letters
        vocab_items.extend(list(self.UPPERCASE))

        # Add punctuation
        vocab_items.extend(list(self.PUNCTUATION))

        # Add digits
        vocab_items.extend(list(self.DIGITS))

        # Build mappings
        for i, char in enumerate(vocab_items):
            self.char_to_id[char] = i
            self.id_to_char[i] = char

    @property
    def vocab_size(self) -> int:
        """Return vocabulary size."""
        return len(self.char_to_id)

    @property
    def pad_id(self) -> int:
        return self.char_to_id[self.PAD]

    @property
    def unk_id(self) -> int:
        return self.char_to_id[self.UNK]

    @property
    def bos_id(self) -> int:
        return self.char_to_id[self.BOS]

    @property
    def eos_id(self) -> int:
        return self.char_to_id[self.EOS]

    @property
    def space_id(self) -> int:
        return self.char_to_id[self.SPACE]

    def encode(self, text: str, add_bos: bool = False,
               add_eos: bool = False) -> List[int]:
        """
        Encode text to token IDs.

        Args:
            text: Input text string
            add_bos: Add beginning-of-sequence token
            add_eos: Add end-of-sequence token

        Returns:
            List of token IDs
        """
        ids = []

        if add_bos:
            ids.append(self.bos_id)

        for char in text:
            if char in self.char_to_id:
                ids.append(self.char_to_id[char])
            else:
                ids.append(self.unk_id)

        if add_eos:
            ids.append(self.eos_id)

        return ids

    def decode(self, ids: List[int], skip_special: bool = True) -> str:
        """
        Decode token IDs back to text.

        Args:
            ids: List of token IDs
            skip_special: Skip special tokens (pad, bos, eos, unk)

        Returns:
            Decoded text string
        """
        chars = []
        special_ids = {self.pad_id, self.bos_id, self.eos_id}
        if skip_special:
            special_ids.add(self.unk_id)

        for id_ in ids:
            if id_ in special_ids:
                continue
            if id_ in self.id_to_char:
                chars.append(self.id_to_char[id_])

        return ''.join(chars)

    def get_valid_next_chars(self) -> List[int]:
        """
        Get IDs of all valid next characters for prediction.

        Returns all characters except PAD, BOS (UNK and EOS are valid outputs).
        """
        invalid = {self.pad_id, self.bos_id}
        return [i for i in range(self.vocab_size) if i not in invalid]

    def save(self, path: Path):
        """Save tokenizer configuration."""
        data = {
            'char_to_id': self.char_to_id,
            'vocab_size': self.vocab_size,
        }
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    @classmethod
    def load(cls, path: Path) -> 'CharacterTokenizer':
        """Load tokenizer from file."""
        tokenizer = cls()
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        tokenizer.char_to_id = data['char_to_id']
        tokenizer.id_to_char = {int(v): k for k, v in data['char_to_id'].items()}
        return tokenizer

    def export_for_swift(self) -> str:
        """Generate Swift code for the tokenizer."""
        swift = '''// Auto-generated character tokenizer for Latinum keyboard
import Foundation

/// Character-level tokenizer for Latin text prediction
struct CharacterTokenizer {

    // MARK: - Special Token IDs

    static let padId = 0
    static let unkId = 1
    static let bosId = 2
    static let eosId = 3
    static let spaceId = 4

    // MARK: - Vocabulary

    static let vocabSize = ''' + str(self.vocab_size) + '''

    /// Character to ID mapping
    static let charToId: [Character: Int] = [
'''
        for char, id_ in sorted(self.char_to_id.items(), key=lambda x: x[1]):
            if char == self.PAD:
                continue  # Skip special tokens in char map
            elif char == self.UNK:
                continue
            elif char == self.BOS:
                continue
            elif char == self.EOS:
                continue
            elif char == '"':
                swift += f'        "\\"": {id_},\n'
            elif char == '\\':
                swift += f'        "\\\\": {id_},\n'
            else:
                swift += f'        "{char}": {id_},\n'

        swift += '''    ]

    /// ID to character mapping
    static let idToChar: [Int: Character] = [
'''
        for id_, char in sorted(self.id_to_char.items()):
            if char in (self.PAD, self.UNK, self.BOS, self.EOS):
                continue
            elif char == '"':
                swift += f'        {id_}: "\\"",\n'
            elif char == '\\':
                swift += f'        {id_}: "\\\\",\n'
            else:
                swift += f'        {id_}: "{char}",\n'

        swift += '''    ]

    // MARK: - Encoding

    /// Encode text to token IDs
    static func encode(_ text: String, addBos: Bool = false, addEos: Bool = false) -> [Int] {
        var ids: [Int] = []

        if addBos {
            ids.append(bosId)
        }

        for char in text {
            if let id = charToId[char] {
                ids.append(id)
            } else {
                ids.append(unkId)
            }
        }

        if addEos {
            ids.append(eosId)
        }

        return ids
    }

    // MARK: - Decoding

    /// Decode token IDs back to text
    static func decode(_ ids: [Int], skipSpecial: Bool = true) -> String {
        var chars: [Character] = []
        let specialIds: Set<Int> = skipSpecial
            ? [padId, bosId, eosId, unkId]
            : [padId, bosId, eosId]

        for id in ids {
            guard !specialIds.contains(id),
                  let char = idToChar[id] else {
                continue
            }
            chars.append(char)
        }

        return String(chars)
    }
}
'''
        return swift


def analyze_corpus_chars(corpus_path: Path) -> Dict:
    """Analyze character distribution in corpus."""
    char_freq = Counter()
    total_chars = 0

    with open(corpus_path, 'r', encoding='utf-8') as f:
        for line in f:
            char_freq.update(line.strip())
            total_chars += len(line.strip())

    return {
        'total_chars': total_chars,
        'unique_chars': len(char_freq),
        'frequencies': char_freq,
    }


def create_training_sequences(
    corpus_path: Path,
    output_path: Path,
    tokenizer: CharacterTokenizer,
    seq_length: int = 64,
    stride: int = 32,
) -> Dict:
    """
    Create training sequences from corpus.

    Uses a sliding window approach to create overlapping sequences
    for language model training.

    Args:
        corpus_path: Path to cleaned corpus
        output_path: Path to write sequences (one per line, space-separated IDs)
        tokenizer: Character tokenizer
        seq_length: Length of each sequence
        stride: Step size between sequences

    Returns:
        Statistics dictionary
    """
    stats = {
        'sequences': 0,
        'total_tokens': 0,
    }

    with open(corpus_path, 'r', encoding='utf-8') as f_in, \
         open(output_path, 'w', encoding='utf-8') as f_out:

        buffer = []

        for line in f_in:
            # Encode line with space at end (word boundary)
            ids = tokenizer.encode(line.strip() + ' ')
            buffer.extend(ids)

            # Extract sequences when buffer is large enough
            while len(buffer) >= seq_length + 1:  # +1 for target
                seq = buffer[:seq_length + 1]
                # Write as space-separated IDs
                f_out.write(' '.join(map(str, seq)) + '\n')
                stats['sequences'] += 1
                stats['total_tokens'] += len(seq)

                # Slide window
                buffer = buffer[stride:]

    return stats


if __name__ == '__main__':
    script_dir = Path(__file__).parent

    # Create tokenizer
    tokenizer = CharacterTokenizer()
    print(f"Character Tokenizer")
    print(f"  Vocabulary size: {tokenizer.vocab_size}")
    print(f"  Special tokens: PAD={tokenizer.pad_id}, UNK={tokenizer.unk_id}, "
          f"BOS={tokenizer.bos_id}, EOS={tokenizer.eos_id}, SPACE={tokenizer.space_id}")

    # Test encoding/decoding
    test_texts = [
        "Roma",
        "amare",
        "Gallia est omnis divisa in partes tres",
        "quo usque tandem abutere, Catilina, patientia nostra?",
    ]

    print("\nEncoding tests:")
    for text in test_texts:
        ids = tokenizer.encode(text)
        decoded = tokenizer.decode(ids)
        print(f"  '{text}'")
        print(f"    -> {ids}")
        print(f"    -> '{decoded}'")
        assert decoded == text, f"Mismatch: {decoded} != {text}"

    # Save tokenizer
    tokenizer_path = script_dir / 'char_tokenizer.json'
    tokenizer.save(tokenizer_path)
    print(f"\nSaved tokenizer to {tokenizer_path}")

    # Export Swift code
    swift_code = tokenizer.export_for_swift()
    swift_path = script_dir / 'CharacterTokenizer.swift'
    with open(swift_path, 'w') as f:
        f.write(swift_code)
    print(f"Exported Swift tokenizer to {swift_path}")

    # Analyze corpus
    corpus_path = script_dir / 'cleaned_corpus.txt'
    if corpus_path.exists():
        print("\nAnalyzing corpus...")
        analysis = analyze_corpus_chars(corpus_path)
        print(f"  Total characters: {analysis['total_chars']:,}")
        print(f"  Unique characters: {analysis['unique_chars']}")

        print("\n  Top 20 characters:")
        for char, freq in analysis['frequencies'].most_common(20):
            pct = 100 * freq / analysis['total_chars']
            char_repr = repr(char) if char.strip() else "'SPACE'"
            print(f"    {char_repr}: {freq:,} ({pct:.2f}%)")

        # Create training sequences
        print("\nCreating training sequences...")
        seq_path = script_dir / 'training_sequences.txt'
        seq_stats = create_training_sequences(
            corpus_path, seq_path, tokenizer,
            seq_length=64, stride=32
        )
        print(f"  Sequences: {seq_stats['sequences']:,}")
        print(f"  Total tokens: {seq_stats['total_tokens']:,}")
        print(f"  Saved to {seq_path}")
