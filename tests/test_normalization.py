#!/usr/bin/env python3
"""
Unit tests for Latin text normalization.

Run with:
    python3 -m pytest tests/ -v

Or without pytest:
    python3 tests/test_normalization.py
"""

import sys
from pathlib import Path

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from data_pipeline.normalization import (
    strip_macrons,
    expand_ligatures,
    normalize_for_model,
    apply_completion_preserving_diacritics,
    get_long_press_options,
    get_macron_positions,
    get_ligature_positions,
)


class TestMacronStripping:
    """Tests for macron stripping functionality."""

    def test_strip_lowercase_macrons(self):
        assert strip_macrons("amāre") == "amare"

    def test_strip_uppercase_macrons(self):
        assert strip_macrons("RŌMA") == "ROMA"

    def test_strip_mixed_case_macrons(self):
        assert strip_macrons("Rōmānī") == "Romani"

    def test_no_macrons_unchanged(self):
        assert strip_macrons("caelum") == "caelum"

    def test_all_vowels_with_macrons(self):
        assert strip_macrons("āēīōūȳ") == "aeiouy"
        assert strip_macrons("ĀĒĪŌŪȲ") == "AEIOUY"

    def test_empty_string(self):
        assert strip_macrons("") == ""

    def test_mixed_text(self):
        assert strip_macrons("Cīcerō dīxit") == "Cicero dixit"


class TestLigatureExpansion:
    """Tests for ligature expansion functionality."""

    def test_expand_ae_ligature(self):
        assert expand_ligatures("ætas") == "aetas"

    def test_expand_oe_ligature(self):
        assert expand_ligatures("cœlum") == "coelum"

    def test_expand_uppercase_ligatures(self):
        assert expand_ligatures("Ætas") == "Aetas"
        assert expand_ligatures("Œdipus") == "Oedipus"

    def test_no_ligatures_unchanged(self):
        assert expand_ligatures("caelum") == "caelum"

    def test_empty_string(self):
        assert expand_ligatures("") == ""


class TestFullNormalization:
    """Tests for complete text normalization."""

    def test_normalize_combined(self):
        assert normalize_for_model("Rōmæ") == "romae"

    def test_normalize_complex(self):
        assert normalize_for_model("Cæsār ēst in Galliā") == "caesar est in gallia"

    def test_normalize_simple(self):
        assert normalize_for_model("ROMA") == "roma"

    def test_normalize_empty(self):
        assert normalize_for_model("") == ""


class TestCompletionPreservation:
    """Tests for macron-preserving completion."""

    def test_preserve_single_macron(self):
        result = apply_completion_preserving_diacritics("amā", "amare")
        assert result == "amāre"

    def test_preserve_multiple_macrons(self):
        result = apply_completion_preserving_diacritics("Rōm", "roma")
        assert result == "Rōma"

    def test_no_macrons(self):
        result = apply_completion_preserving_diacritics("am", "amare")
        assert result == "amare"

    def test_empty_user_text(self):
        result = apply_completion_preserving_diacritics("", "amare")
        assert result == "amare"

    def test_non_matching_completion(self):
        result = apply_completion_preserving_diacritics("am", "bellum")
        assert result == "bellum"

    def test_preserve_ligature(self):
        result = apply_completion_preserving_diacritics("æt", "aetas")
        assert result == "ætas"

    def test_exact_match(self):
        result = apply_completion_preserving_diacritics("amāre", "amare")
        assert result == "amāre"


class TestLongPressOptions:
    """Tests for keyboard long-press options."""

    def test_lowercase_a_options(self):
        options = get_long_press_options('a')
        assert 'ā' in options
        assert 'æ' in options

    def test_uppercase_a_options(self):
        options = get_long_press_options('A')
        assert 'Ā' in options
        assert 'Æ' in options

    def test_lowercase_o_options(self):
        options = get_long_press_options('o')
        assert 'ō' in options
        assert 'œ' in options

    def test_other_vowels(self):
        assert 'ē' in get_long_press_options('e')
        assert 'ī' in get_long_press_options('i')
        assert 'ū' in get_long_press_options('u')

    def test_consonant_no_options(self):
        options = get_long_press_options('b')
        assert len(options) == 0


class TestPositionTracking:
    """Tests for macron/ligature position tracking."""

    def test_get_macron_positions(self):
        positions = get_macron_positions("amāre")
        assert len(positions) == 1
        assert positions[0] == (2, 'ā')

    def test_get_multiple_macron_positions(self):
        positions = get_macron_positions("Rōmānī")
        assert len(positions) == 3  # ō, ā, ī

    def test_get_ligature_positions(self):
        positions = get_ligature_positions("ætas")
        assert len(positions) == 1
        assert positions[0][0] == 0  # Position 0
        assert positions[0][1] == 'æ'  # Character


def run_tests():
    """Run all tests without pytest."""
    test_classes = [
        TestMacronStripping,
        TestLigatureExpansion,
        TestFullNormalization,
        TestCompletionPreservation,
        TestLongPressOptions,
        TestPositionTracking,
    ]

    total = 0
    passed = 0
    failed = 0

    for cls in test_classes:
        print(f"\n{cls.__name__}")
        instance = cls()

        for method_name in dir(instance):
            if method_name.startswith('test_'):
                total += 1
                try:
                    getattr(instance, method_name)()
                    print(f"  [PASS] {method_name}")
                    passed += 1
                except AssertionError as e:
                    print(f"  [FAIL] {method_name}: {e}")
                    failed += 1
                except Exception as e:
                    print(f"  [ERROR] {method_name}: {e}")
                    failed += 1

    print(f"\n{'='*50}")
    print(f"Total: {total}, Passed: {passed}, Failed: {failed}")

    return failed == 0


if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
