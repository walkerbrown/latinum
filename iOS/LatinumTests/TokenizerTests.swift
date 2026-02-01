import XCTest

/// Tests for the character tokenizer
final class TokenizerTests: XCTestCase {

    // MARK: - Encoding Tests

    func testEncode_basicText() {
        let ids = CharacterTokenizer.encode("Roma")
        XCTAssertEqual(ids.count, 4, "Should encode 4 characters")
        XCTAssertEqual(ids[0], CharacterTokenizer.charToId["R"], "First char should be R")
    }

    func testEncode_withSpace() {
        let ids = CharacterTokenizer.encode("et tu")
        XCTAssertEqual(ids.count, 5, "Should encode 5 characters including space")
        XCTAssertEqual(ids[2], CharacterTokenizer.spaceId, "Middle char should be space")
    }

    func testEncode_withBos() {
        let ids = CharacterTokenizer.encode("a", addBos: true)
        XCTAssertEqual(ids.count, 2, "Should include BOS token")
        XCTAssertEqual(ids[0], CharacterTokenizer.bosId, "First token should be BOS")
    }

    func testEncode_withEos() {
        let ids = CharacterTokenizer.encode("a", addEos: true)
        XCTAssertEqual(ids.count, 2, "Should include EOS token")
        XCTAssertEqual(ids[1], CharacterTokenizer.eosId, "Last token should be EOS")
    }

    func testEncode_unknownChar() {
        let ids = CharacterTokenizer.encode("@")  // Not in vocab
        XCTAssertEqual(ids.count, 1, "Should encode unknown char")
        XCTAssertEqual(ids[0], CharacterTokenizer.unkId, "Unknown char should be UNK")
    }

    // MARK: - Decoding Tests

    func testDecode_basicIds() {
        let ids = [48, 19, 17, 5]  // R, o, m, a
        let text = CharacterTokenizer.decode(ids)
        XCTAssertEqual(text, "Roma", "Should decode to Roma")
    }

    func testDecode_withSpace() {
        let ids = [9, 24, 4, 24, 25]  // e, t, space, t, u
        let text = CharacterTokenizer.decode(ids)
        XCTAssertEqual(text, "et tu", "Should decode with space")
    }

    func testDecode_skipSpecialTokens() {
        let ids = [CharacterTokenizer.bosId, 5, CharacterTokenizer.eosId]  // BOS, a, EOS
        let text = CharacterTokenizer.decode(ids, skipSpecial: true)
        XCTAssertEqual(text, "a", "Should skip special tokens")
    }

    // MARK: - Roundtrip Tests

    func testRoundtrip_simple() {
        let original = "Gallia"
        let encoded = CharacterTokenizer.encode(original)
        let decoded = CharacterTokenizer.decode(encoded)
        XCTAssertEqual(decoded, original, "Should roundtrip correctly")
    }

    func testRoundtrip_sentence() {
        let original = "Gallia est omnis divisa in partes tres"
        let encoded = CharacterTokenizer.encode(original)
        let decoded = CharacterTokenizer.decode(encoded)
        XCTAssertEqual(decoded, original, "Should roundtrip sentence correctly")
    }

    func testRoundtrip_punctuation() {
        let original = "Quo usque tandem, Catilina?"
        let encoded = CharacterTokenizer.encode(original)
        let decoded = CharacterTokenizer.decode(encoded)
        XCTAssertEqual(decoded, original, "Should roundtrip punctuation correctly")
    }

    // MARK: - Vocabulary Tests

    func testVocabSize() {
        XCTAssertEqual(
            CharacterTokenizer.vocabSize,
            78,
            "Vocabulary size should be 78"
        )
    }

    func testCharToIdConsistency() {
        for (char, id) in CharacterTokenizer.charToId {
            XCTAssertEqual(
                CharacterTokenizer.idToChar[id],
                char,
                "charToId and idToChar should be consistent for \(char)"
            )
        }
    }

    func testSpecialTokensInRange() {
        XCTAssertLessThan(CharacterTokenizer.padId, 5)
        XCTAssertLessThan(CharacterTokenizer.unkId, 5)
        XCTAssertLessThan(CharacterTokenizer.bosId, 5)
        XCTAssertLessThan(CharacterTokenizer.eosId, 5)
        XCTAssertEqual(CharacterTokenizer.spaceId, 4)
    }

    // MARK: - Edge Cases

    func testEncode_emptyString() {
        let ids = CharacterTokenizer.encode("")
        XCTAssertEqual(ids.count, 0, "Empty string should encode to empty array")
    }

    func testEncode_emptyStringWithBos() {
        let ids = CharacterTokenizer.encode("", addBos: true)
        XCTAssertEqual(ids.count, 1, "Empty string with BOS should have 1 token")
        XCTAssertEqual(ids[0], CharacterTokenizer.bosId, "Should be BOS token")
    }

    func testEncode_emptyStringWithBosAndEos() {
        let ids = CharacterTokenizer.encode("", addBos: true, addEos: true)
        XCTAssertEqual(ids.count, 2, "Empty string with BOS+EOS should have 2 tokens")
        XCTAssertEqual(ids[0], CharacterTokenizer.bosId, "First should be BOS")
        XCTAssertEqual(ids[1], CharacterTokenizer.eosId, "Second should be EOS")
    }

    func testDecode_emptyArray() {
        let text = CharacterTokenizer.decode([])
        XCTAssertEqual(text, "", "Empty array should decode to empty string")
    }

    func testEncode_allNumbers() {
        let ids = CharacterTokenizer.encode("1234567890")
        XCTAssertEqual(ids.count, 10, "Should encode all 10 digits")
        // Verify none are UNK
        for id in ids {
            XCTAssertNotEqual(id, CharacterTokenizer.unkId, "Digits should not be UNK")
        }
    }

    func testEncode_punctuation() {
        let punctuation = ".,;:!?'\"-"
        let ids = CharacterTokenizer.encode(punctuation)
        XCTAssertEqual(ids.count, punctuation.count, "All punctuation should encode")
        for id in ids {
            XCTAssertNotEqual(id, CharacterTokenizer.unkId, "Standard punctuation should not be UNK")
        }
    }

    func testEncode_mixedCaseAndPunctuation() {
        let text = "Salve, Roma!"
        let ids = CharacterTokenizer.encode(text)
        let decoded = CharacterTokenizer.decode(ids)
        XCTAssertEqual(decoded, text, "Mixed case with punctuation should roundtrip")
    }

    func testEncode_multipleUnknownChars() {
        let ids = CharacterTokenizer.encode("@#$%^&*")
        // @ is unknown, # is unknown, $ is in vocab...
        // Let's just verify encoding doesn't crash with unknown chars
        XCTAssertEqual(ids.count, 7, "Should encode all characters including unknowns")
    }

    func testDecode_unknownIdReturnsEmpty() {
        let ids = [999]  // Invalid ID
        let text = CharacterTokenizer.decode(ids)
        XCTAssertEqual(text, "", "Invalid ID should produce empty string")
    }

    func testDecode_withUnkToken() {
        let ids = [CharacterTokenizer.unkId]
        let textSkip = CharacterTokenizer.decode(ids, skipSpecial: true)
        let textNoSkip = CharacterTokenizer.decode(ids, skipSpecial: false)
        XCTAssertEqual(textSkip, "", "UNK should be skipped when skipSpecial=true")
        XCTAssertEqual(textNoSkip, "", "UNK should still be skipped when skipSpecial=false")
    }

    // MARK: - Vocabulary Coverage

    func testVocabContainsAllLatinLetters() {
        let lowercase = "abcdefghijklmnopqrstuvwxyz"
        let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

        for char in lowercase {
            XCTAssertNotNil(
                CharacterTokenizer.charToId[char],
                "Vocab should contain lowercase \(char)"
            )
        }

        for char in uppercase {
            XCTAssertNotNil(
                CharacterTokenizer.charToId[char],
                "Vocab should contain uppercase \(char)"
            )
        }
    }

    func testIdToCharCoverage() {
        // All IDs from 4 to vocabSize-1 should map to characters
        for id in 4..<CharacterTokenizer.vocabSize {
            XCTAssertNotNil(
                CharacterTokenizer.idToChar[id],
                "ID \(id) should map to a character"
            )
        }
    }
}
