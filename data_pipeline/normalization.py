#!/usr/bin/env python3
"""
Latin Text Normalization Utilities

This module provides bidirectional mappings and normalization functions
for Latin text. These mappings are canonical and should be mirrored in
the Swift implementation for the iOS keyboard.

Key principles:
1. Model training uses macron-free, ligature-free text
2. User input is normalized before model queries
3. User-entered macrons are preserved in the visible buffer
4. Completions extend user text without removing macrons
"""

from typing import Dict, Set, Tuple

# === MACRON MAPPINGS ===
# Vowels with macrons (long vowels) → base vowels
# Used for normalizing training data and user input for model queries

MACRON_TO_BASE: Dict[str, str] = {
    # Lowercase with macron
    'ā': 'a',
    'ē': 'e',
    'ī': 'i',
    'ō': 'o',
    'ū': 'u',
    'ȳ': 'y',
    # Uppercase with macron
    'Ā': 'A',
    'Ē': 'E',
    'Ī': 'I',
    'Ō': 'O',
    'Ū': 'U',
    'Ȳ': 'Y',
}

# Reverse mapping: base vowel → macronized vowel
# Used for providing macron suggestions in the keyboard
BASE_TO_MACRON_LOWER: Dict[str, str] = {
    'a': 'ā', 'e': 'ē', 'i': 'ī', 'o': 'ō', 'u': 'ū', 'y': 'ȳ',
}
BASE_TO_MACRON_UPPER: Dict[str, str] = {
    'A': 'Ā', 'E': 'Ē', 'I': 'Ī', 'O': 'Ō', 'U': 'Ū', 'Y': 'Ȳ',
}

# Breve mappings (short vowel markers, less common)
BREVE_TO_BASE: Dict[str, str] = {
    'ă': 'a', 'ĕ': 'e', 'ĭ': 'i', 'ŏ': 'o', 'ŭ': 'u',
    'Ă': 'A', 'Ĕ': 'E', 'Ĭ': 'I', 'Ŏ': 'O', 'Ŭ': 'U',
}

# === LIGATURE MAPPINGS ===
# Latin ligatures → expanded form
# Used for normalizing training data and user input

LIGATURE_TO_EXPANDED: Dict[str, str] = {
    # Latin ligatures
    'æ': 'ae',
    'Æ': 'Ae',  # Title case for consistency
    'œ': 'oe',
    'Œ': 'Oe',
    # Typographic ligatures (may appear in digitized texts)
    'ﬁ': 'fi',
    'ﬂ': 'fl',
    'ﬀ': 'ff',
    'ﬃ': 'ffi',
    'ﬄ': 'ffl',
}

# Reverse mapping for keyboard long-press options
EXPANDED_TO_LIGATURE_LOWER: Dict[str, str] = {
    'ae': 'æ',
    'oe': 'œ',
}
EXPANDED_TO_LIGATURE_UPPER: Dict[str, str] = {
    'AE': 'Æ',
    'OE': 'Œ',
}

# === VOWEL SETS ===
# Used for validation and special handling

LATIN_VOWELS_BASE: Set[str] = {'a', 'e', 'i', 'o', 'u', 'y',
                                'A', 'E', 'I', 'O', 'U', 'Y'}
LATIN_VOWELS_MACRON: Set[str] = set(MACRON_TO_BASE.keys())
LATIN_VOWELS_ALL: Set[str] = LATIN_VOWELS_BASE | LATIN_VOWELS_MACRON

# === ENCLITICS ===
# Common Latin enclitics that attach to words
# The model should learn these, but they're useful for heuristics

LATIN_ENCLITICS: Tuple[str, ...] = (
    '-que',  # "and" (most common)
    '-ve',   # "or"
    '-ne',   # question marker
    '-ce',   # demonstrative intensifier (hīc → hīcce)
    '-met',  # emphatic (egomet)
    '-pte',  # emphatic (suāpte)
    '-cum',  # "with" in some forms (mēcum, tēcum)
)


def strip_macrons(text: str) -> str:
    """
    Remove macrons from all vowels, returning macron-free text.

    This is used to normalize text for model training and queries.
    The model operates entirely on macron-free text.
    """
    result = []
    for char in text:
        if char in MACRON_TO_BASE:
            result.append(MACRON_TO_BASE[char])
        elif char in BREVE_TO_BASE:
            result.append(BREVE_TO_BASE[char])
        else:
            result.append(char)
    return ''.join(result)


def expand_ligatures(text: str) -> str:
    """
    Expand ligatures to their component letters.

    This is used to normalize text for model training and queries.
    The model operates on expanded ligatures.
    """
    for ligature, expanded in LIGATURE_TO_EXPANDED.items():
        text = text.replace(ligature, expanded)
    return text


def normalize_for_model(text: str) -> str:
    """
    Fully normalize text for model input.

    Applies:
    1. Macron stripping
    2. Ligature expansion
    3. Lowercase conversion

    This produces the canonical form used by the prediction model.
    """
    text = strip_macrons(text)
    text = expand_ligatures(text)
    text = text.lower()
    return text


def get_macron_positions(text: str) -> list:
    """
    Find positions of macronized vowels in text.

    Returns list of (position, original_char) tuples.
    Used to preserve user-entered macrons when applying completions.
    """
    positions = []
    for i, char in enumerate(text):
        if char in MACRON_TO_BASE:
            positions.append((i, char))
    return positions


def get_ligature_positions(text: str) -> list:
    """
    Find positions of ligatures in text.

    Returns list of (position, ligature, expansion_length) tuples.
    Used to preserve user-entered ligatures when applying completions.
    """
    positions = []
    for i, char in enumerate(text):
        if char in LIGATURE_TO_EXPANDED:
            expansion = LIGATURE_TO_EXPANDED[char]
            positions.append((i, char, len(expansion)))
    return positions


def apply_completion_preserving_diacritics(
    user_text: str,
    completion: str
) -> str:
    """
    Apply a model completion while preserving user-entered macrons/ligatures.

    The model returns completions in normalized (macron-free) form.
    This function merges the completion with the user's text, preserving
    any macrons or ligatures the user has already typed.

    Example:
        user_text = "amā"  (user typed macron)
        completion = "amare"  (model suggests)
        result = "amāre"  (macron preserved, completion extended)
    """
    if not user_text:
        return completion

    # Normalize user text to compare with completion
    user_normalized = normalize_for_model(user_text)

    # The completion should start with the normalized user text
    if not completion.lower().startswith(user_normalized):
        # Completion doesn't match - just return it as-is
        return completion

    # Get the extension part (what the model is adding)
    extension = completion[len(user_normalized):]

    # Return user's original text (with macrons) + extension
    return user_text + extension


def get_long_press_options(char: str) -> list:
    """
    Get long-press options for a character on the keyboard.

    For vowels, returns macronized version.
    For 'a'/'A', also returns ligature æ/Æ.
    For 'o'/'O', also returns ligature œ/Œ.
    """
    options = []

    # Check for macron option
    if char in BASE_TO_MACRON_LOWER:
        options.append(BASE_TO_MACRON_LOWER[char])
    elif char in BASE_TO_MACRON_UPPER:
        options.append(BASE_TO_MACRON_UPPER[char])

    # Check for ligature options
    if char == 'a':
        options.append('æ')
    elif char == 'A':
        options.append('Æ')
    elif char == 'o':
        options.append('œ')
    elif char == 'O':
        options.append('Œ')

    return options


# === SWIFT CODE GENERATION ===
# Generate equivalent Swift code for the iOS app

def generate_swift_constants() -> str:
    """Generate Swift code with equivalent mappings."""
    swift_code = '''// Auto-generated from normalization.py
// DO NOT EDIT - regenerate with: python3 normalization.py --swift

import Foundation

/// Latin text normalization utilities for the Latinum keyboard.
/// Mirrors the Python normalization module for consistency.
enum LatinNormalization {

    // MARK: - Macron Mappings

    /// Maps macronized vowels to their base form
    static let macronToBase: [Character: Character] = [
'''

    for macron, base in sorted(MACRON_TO_BASE.items()):
        swift_code += f'        "{macron}": "{base}",\n'

    swift_code += '''    ]

    /// Maps base vowels to macronized form (lowercase)
    static let baseToMacronLower: [Character: Character] = [
'''

    for base, macron in sorted(BASE_TO_MACRON_LOWER.items()):
        swift_code += f'        "{base}": "{macron}",\n'

    swift_code += '''    ]

    /// Maps base vowels to macronized form (uppercase)
    static let baseToMacronUpper: [Character: Character] = [
'''

    for base, macron in sorted(BASE_TO_MACRON_UPPER.items()):
        swift_code += f'        "{base}": "{macron}",\n'

    swift_code += '''    ]

    // MARK: - Ligature Mappings

    /// Maps ligatures to their expanded form
    static let ligatureToExpanded: [Character: String] = [
'''

    for lig, exp in sorted(LIGATURE_TO_EXPANDED.items()):
        swift_code += f'        "{lig}": "{exp}",\n'

    swift_code += '''    ]

    // MARK: - Normalization Functions

    /// Strip macrons from text for model input
    static func stripMacrons(_ text: String) -> String {
        var result = ""
        for char in text {
            if let base = macronToBase[char] {
                result.append(base)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Expand ligatures for model input
    static func expandLigatures(_ text: String) -> String {
        var result = ""
        for char in text {
            if let expanded = ligatureToExpanded[char] {
                result.append(expanded)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Fully normalize text for model queries
    static func normalizeForModel(_ text: String) -> String {
        return expandLigatures(stripMacrons(text)).lowercased()
    }

    /// Get long-press options for a character
    static func getLongPressOptions(_ char: Character) -> [Character] {
        var options: [Character] = []

        // Macron options
        if let macron = baseToMacronLower[char] {
            options.append(macron)
        } else if let macron = baseToMacronUpper[char] {
            options.append(macron)
        }

        // Ligature options
        switch char {
        case "a": options.append("\\u{00E6}")  // æ
        case "A": options.append("\\u{00C6}")  // Æ
        case "o": options.append("\\u{0153}")  // œ
        case "O": options.append("\\u{0152}")  // Œ
        default: break
        }

        return options
    }

    /// Apply completion while preserving user's macrons
    static func applyCompletionPreservingDiacritics(
        userText: String,
        completion: String
    ) -> String {
        guard !userText.isEmpty else { return completion }

        let userNormalized = normalizeForModel(userText)

        guard completion.lowercased().hasPrefix(userNormalized) else {
            return completion
        }

        let extensionStart = completion.index(
            completion.startIndex,
            offsetBy: userNormalized.count
        )
        let extensionPart = String(completion[extensionStart...])

        return userText + extensionPart
    }
}
'''
    return swift_code


if __name__ == '__main__':
    import sys

    if '--swift' in sys.argv:
        print(generate_swift_constants())
    else:
        # Run tests
        print("Testing normalization functions...")

        # Test macron stripping
        assert strip_macrons("amāre") == "amare"
        assert strip_macrons("Rōma") == "Roma"
        assert strip_macrons("caelum") == "caelum"
        print("  [OK] strip_macrons")

        # Test ligature expansion
        assert expand_ligatures("ætas") == "aetas"
        assert expand_ligatures("cœlum") == "coelum"
        print("  [OK] expand_ligatures")

        # Test full normalization
        assert normalize_for_model("Rōmæ") == "romae"
        print("  [OK] normalize_for_model")

        # Test completion preservation
        assert apply_completion_preserving_diacritics("amā", "amare") == "amāre"
        assert apply_completion_preserving_diacritics("Rōm", "roma") == "Rōma"
        print("  [OK] apply_completion_preserving_diacritics")

        # Test long press options
        assert 'ā' in get_long_press_options('a')
        assert 'æ' in get_long_press_options('a')
        assert 'Ā' in get_long_press_options('A')
        print("  [OK] get_long_press_options")

        print("\nAll tests passed!")
