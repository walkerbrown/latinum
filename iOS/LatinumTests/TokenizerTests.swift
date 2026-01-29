import XCTest
@testable import LatinumKeyboard

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
}
