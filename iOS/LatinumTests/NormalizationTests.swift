import XCTest

/// Tests for Latin text normalization
final class NormalizationTests: XCTestCase {

    // MARK: - Macron Stripping Tests

    func testStripMacrons_lowercase() {
        XCTAssertEqual(
            LatinNormalization.stripMacrons("amāre"),
            "amare",
            "Should strip macrons from lowercase text"
        )
    }

    func testStripMacrons_uppercase() {
        XCTAssertEqual(
            LatinNormalization.stripMacrons("RŌMA"),
            "ROMA",
            "Should strip macrons from uppercase text"
        )
    }

    func testStripMacrons_mixed() {
        XCTAssertEqual(
            LatinNormalization.stripMacrons("Rōmānī"),
            "Romani",
            "Should strip macrons from mixed case text"
        )
    }

    func testStripMacrons_noMacrons() {
        XCTAssertEqual(
            LatinNormalization.stripMacrons("caelum"),
            "caelum",
            "Should return unchanged text when no macrons present"
        )
    }

    func testStripMacrons_allVowels() {
        XCTAssertEqual(
            LatinNormalization.stripMacrons("āēīōūȳ"),
            "aeiouy",
            "Should strip macrons from all vowels"
        )
    }

    // MARK: - Ligature Expansion Tests

    func testExpandLigatures_ae() {
        XCTAssertEqual(
            LatinNormalization.expandLigatures("ætas"),
            "aetas",
            "Should expand æ to ae"
        )
    }

    func testExpandLigatures_oe() {
        XCTAssertEqual(
            LatinNormalization.expandLigatures("cœlum"),
            "coelum",
            "Should expand œ to oe"
        )
    }

    func testExpandLigatures_uppercase() {
        XCTAssertEqual(
            LatinNormalization.expandLigatures("Ætas"),
            "Aetas",
            "Should expand uppercase ligatures"
        )
    }

    func testExpandLigatures_noLigatures() {
        XCTAssertEqual(
            LatinNormalization.expandLigatures("caelum"),
            "caelum",
            "Should return unchanged text when no ligatures present"
        )
    }

    // MARK: - Full Normalization Tests

    func testNormalizeForModel_combined() {
        XCTAssertEqual(
            LatinNormalization.normalizeForModel("Rōmæ"),
            "romae",
            "Should strip macrons, expand ligatures, and lowercase"
        )
    }

    func testNormalizeForModel_complex() {
        XCTAssertEqual(
            LatinNormalization.normalizeForModel("Cæsār ēst in Galliā"),
            "caesar est in gallia",
            "Should normalize complex text correctly"
        )
    }

    // MARK: - Completion Preservation Tests

    func testApplyCompletionPreservingDiacritics_macronPreserved() {
        let result = LatinNormalization.applyCompletionPreservingDiacritics(
            userText: "amā",
            completion: "amare"
        )
        XCTAssertEqual(
            result,
            "amāre",
            "Should preserve user's macron and extend with completion"
        )
    }

    func testApplyCompletionPreservingDiacritics_multipleMacrons() {
        let result = LatinNormalization.applyCompletionPreservingDiacritics(
            userText: "Rōm",
            completion: "roma"
        )
        XCTAssertEqual(
            result,
            "Rōma",
            "Should preserve all user macrons"
        )
    }

    func testApplyCompletionPreservingDiacritics_noMacrons() {
        let result = LatinNormalization.applyCompletionPreservingDiacritics(
            userText: "am",
            completion: "amare"
        )
        XCTAssertEqual(
            result,
            "amare",
            "Should work correctly without macrons"
        )
    }

    func testApplyCompletionPreservingDiacritics_emptyUser() {
        let result = LatinNormalization.applyCompletionPreservingDiacritics(
            userText: "",
            completion: "amare"
        )
        XCTAssertEqual(
            result,
            "amare",
            "Should return completion unchanged when user text is empty"
        )
    }

    func testApplyCompletionPreservingDiacritics_nonMatchingCompletion() {
        let result = LatinNormalization.applyCompletionPreservingDiacritics(
            userText: "am",
            completion: "bellum"
        )
        XCTAssertEqual(
            result,
            "bellum",
            "Should return completion unchanged when it doesn't match prefix"
        )
    }

    func testApplyCompletionPreservingDiacritics_ligaturePreserved() {
        let result = LatinNormalization.applyCompletionPreservingDiacritics(
            userText: "æt",
            completion: "aetas"
        )
        XCTAssertEqual(
            result,
            "ætas",
            "Should preserve user's ligature"
        )
    }

    // MARK: - Long Press Options Tests

    func testGetLongPressOptions_lowercase_a() {
        let options = LatinNormalization.getLongPressOptions("a")
        XCTAssertTrue(options.contains("\u{0101}"), "Should include ā")
        XCTAssertTrue(options.contains("\u{00E6}"), "Should include æ")
    }

    func testGetLongPressOptions_uppercase_A() {
        let options = LatinNormalization.getLongPressOptions("A")
        XCTAssertTrue(options.contains("\u{0100}"), "Should include Ā")
        XCTAssertTrue(options.contains("\u{00C6}"), "Should include Æ")
    }

    func testGetLongPressOptions_lowercase_o() {
        let options = LatinNormalization.getLongPressOptions("o")
        XCTAssertTrue(options.contains("\u{014D}"), "Should include ō")
        XCTAssertTrue(options.contains("\u{0153}"), "Should include œ")
    }

    func testGetLongPressOptions_consonant() {
        let options = LatinNormalization.getLongPressOptions("b")
        XCTAssertTrue(options.isEmpty, "Consonants should have no long press options")
    }

    // MARK: - Edge Cases

    func testStripMacrons_emptyString() {
        XCTAssertEqual(
            LatinNormalization.stripMacrons(""),
            "",
            "Empty string should return empty string"
        )
    }

    func testExpandLigatures_emptyString() {
        XCTAssertEqual(
            LatinNormalization.expandLigatures(""),
            "",
            "Empty string should return empty string"
        )
    }

    func testNormalizeForModel_emptyString() {
        XCTAssertEqual(
            LatinNormalization.normalizeForModel(""),
            "",
            "Empty string should return empty string"
        )
    }

    func testNormalizeForModel_onlyPunctuation() {
        XCTAssertEqual(
            LatinNormalization.normalizeForModel("... !!!"),
            "... !!!",
            "Punctuation should pass through unchanged"
        )
    }

    func testApplyCompletionPreservingDiacritics_casePreserved() {
        let result = LatinNormalization.applyCompletionPreservingDiacritics(
            userText: "Rōm",
            completion: "Roma"
        )
        XCTAssertEqual(
            result,
            "Rōma",
            "Should preserve user case and macrons"
        )
    }

    func testGetLongPressOptions_e() {
        let options = LatinNormalization.getLongPressOptions("e")
        XCTAssertEqual(options.count, 1, "e should have 1 option (ē)")
        XCTAssertTrue(options.contains("\u{0113}"), "Should include ē")
    }

    func testGetLongPressOptions_uppercase_E() {
        let options = LatinNormalization.getLongPressOptions("E")
        XCTAssertEqual(options.count, 1, "E should have 1 option (Ē)")
        XCTAssertTrue(options.contains("\u{0112}"), "Should include Ē")
    }

    func testGetLongPressOptions_i() {
        let options = LatinNormalization.getLongPressOptions("i")
        XCTAssertEqual(options.count, 1, "i should have 1 option (ī)")
        XCTAssertTrue(options.contains("\u{012B}"), "Should include ī")
    }

    func testGetLongPressOptions_u() {
        let options = LatinNormalization.getLongPressOptions("u")
        XCTAssertEqual(options.count, 1, "u should have 1 option (ū)")
        XCTAssertTrue(options.contains("\u{016B}"), "Should include ū")
    }

    func testGetLongPressOptions_y() {
        let options = LatinNormalization.getLongPressOptions("y")
        XCTAssertEqual(options.count, 1, "y should have 1 option (ȳ)")
        XCTAssertTrue(options.contains("\u{0233}"), "Should include ȳ")
    }

    // MARK: - Consistency Tests

    func testAllMacronVowelsRoundtrip() {
        // Test that all macron vowels can be stripped and restored
        let macronVowels = "āēīōūȳ"
        let stripped = LatinNormalization.stripMacrons(macronVowels)
        XCTAssertEqual(stripped, "aeiouy", "All lowercase macrons should strip")

        let upperMacronVowels = "ĀĒĪŌŪȲ"
        let upperStripped = LatinNormalization.stripMacrons(upperMacronVowels)
        XCTAssertEqual(upperStripped, "AEIOUY", "All uppercase macrons should strip")
    }

    func testAllLigaturesRoundtrip() {
        let ligatures = "æœÆŒ"
        let expanded = LatinNormalization.expandLigatures(ligatures)
        XCTAssertEqual(expanded, "aeoeAeOe", "All ligatures should expand correctly")
    }

    func testApplyCompletionPreservingDiacritics_lengthMismatch() {
        // User text longer than completion shouldn't crash
        let result = LatinNormalization.applyCompletionPreservingDiacritics(
            userText: "amare",
            completion: "am"
        )
        XCTAssertEqual(
            result,
            "am",
            "Should return completion when user text doesn't match"
        )
    }
}
