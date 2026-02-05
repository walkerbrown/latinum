import XCTest

/// Tests for prediction sources and the PredictionEngine.
final class PredictionSourceTests: XCTestCase {

    // MARK: - FallbackPredictionSource — Completions

    func testFallback_completions_matchesPrefix() {
        let source = FallbackPredictionSource()
        let results = source.completions(context: "", prefix: "mag")
        XCTAssertTrue(results.contains("magnus"), "Should complete 'mag' to 'magnus'")
    }

    func testFallback_completions_multipleResults() {
        let source = FallbackPredictionSource()
        let results = source.completions(context: "", prefix: "e")
        XCTAssertGreaterThan(results.count, 1,
                             "Common prefix should yield multiple completions")
    }

    func testFallback_completions_excludesExactMatch() {
        let source = FallbackPredictionSource()
        let results = source.completions(context: "", prefix: "et")
        XCTAssertFalse(results.contains("et"), "Should not include exact match")
    }

    func testFallback_completions_capitalizesWhenPrefixCapitalized() {
        let source = FallbackPredictionSource()
        let results = source.completions(context: "", prefix: "Mag")
        for result in results {
            XCTAssertTrue(result.first?.isUppercase == true,
                          "Results should be capitalized when prefix is capitalized")
        }
    }

    func testFallback_completions_lowercaseWhenPrefixLowercase() {
        let source = FallbackPredictionSource()
        let results = source.completions(context: "", prefix: "mag")
        for result in results {
            XCTAssertTrue(result.first?.isLowercase == true,
                          "Results should be lowercase when prefix is lowercase")
        }
    }

    func testFallback_completions_emptyPrefix() {
        let source = FallbackPredictionSource()
        let results = source.completions(context: "", prefix: "")
        XCTAssertTrue(results.isEmpty, "Empty prefix should return no completions")
    }

    func testFallback_completions_noMatch() {
        let source = FallbackPredictionSource()
        let results = source.completions(context: "", prefix: "zzz")
        XCTAssertTrue(results.isEmpty, "Non-matching prefix should return no results")
    }

    func testFallback_completions_caseInsensitiveMatching() {
        let source = FallbackPredictionSource()
        let lower = source.completions(context: "", prefix: "rom")
        let upper = source.completions(context: "", prefix: "Rom")
        // Both should find Roma-related completions (content may differ in case)
        XCTAssertFalse(lower.isEmpty, "Lowercase prefix should find matches")
        XCTAssertFalse(upper.isEmpty, "Capitalized prefix should find matches")
    }

    // MARK: - FallbackPredictionSource — Next Word

    func testFallback_nextWordPredictions_returnsThree() {
        let source = FallbackPredictionSource()
        let results = source.nextWordPredictions(context: "")
        XCTAssertEqual(results.count, 3, "Should return exactly 3 next-word predictions")
    }

    func testFallback_nextWordPredictions_returnsStrings() {
        let source = FallbackPredictionSource()
        let results = source.nextWordPredictions(context: "in")
        for word in results {
            XCTAssertFalse(word.isEmpty, "Predictions should be non-empty strings")
        }
    }

    // MARK: - FrequencyCompletionSource

    func testFrequency_isLoaded_falseByDefault() {
        let source = FrequencyCompletionSource()
        XCTAssertFalse(source.isLoaded, "Should not be loaded by default")
    }

    func testFrequency_completions_emptyWhenNotLoaded() {
        let source = FrequencyCompletionSource()
        let results = source.completions(context: "", prefix: "mag")
        XCTAssertTrue(results.isEmpty, "Should return empty before data is loaded")
    }

    func testFrequency_completions_emptyForEmptyPrefix() {
        let source = FrequencyCompletionSource()
        let results = source.completions(context: "", prefix: "")
        XCTAssertTrue(results.isEmpty,
                      "Should return empty for empty prefix even when not loaded")
    }

    func testFrequency_nextWordPredictions_alwaysEmpty() {
        let source = FrequencyCompletionSource()
        let results = source.nextWordPredictions(context: "Roma")
        XCTAssertTrue(results.isEmpty,
                      "Frequency source should never provide next-word predictions")
    }

    // MARK: - NGramPredictionSource

    func testNGram_isLoaded_falseByDefault() {
        let source = NGramPredictionSource()
        XCTAssertFalse(source.isLoaded, "Should not be loaded by default")
    }

    func testNGram_completions_alwaysEmpty() {
        let source = NGramPredictionSource()
        let results = source.completions(context: "", prefix: "mag")
        XCTAssertTrue(results.isEmpty,
                      "NGram source should never provide prefix completions")
    }

    func testNGram_nextWordPredictions_emptyWhenNotLoaded() {
        let source = NGramPredictionSource()
        let results = source.nextWordPredictions(context: "in")
        XCTAssertTrue(results.isEmpty, "Should return empty before data is loaded")
    }

    func testNGram_nextWordPredictions_emptyForEmptyContext() {
        let source = NGramPredictionSource()
        let results = source.nextWordPredictions(context: "")
        XCTAssertTrue(results.isEmpty,
                      "Should return empty for empty context when not loaded")
    }

    // MARK: - Source Responsibility Boundaries

    func testFrequency_onlyDoesCompletions() {
        let source = FrequencyCompletionSource()
        // Completions: returns empty because not loaded, but the method exists
        _ = source.completions(context: "context", prefix: "test")
        // Next-word: must always be empty regardless of state
        let next = source.nextWordPredictions(context: "some context here")
        XCTAssertTrue(next.isEmpty,
                      "FrequencyCompletionSource must never return next-word predictions")
    }

    func testNGram_onlyDoesNextWord() {
        let source = NGramPredictionSource()
        // Completions: must always be empty regardless of state
        let comp = source.completions(context: "context", prefix: "test")
        XCTAssertTrue(comp.isEmpty,
                      "NGramPredictionSource must never return prefix completions")
    }

    // MARK: - PredictionEngine — Integration

    func testEngine_isDataLoaded_falseBeforeLoad() {
        let engine = PredictionEngine()
        XCTAssertFalse(engine.isDataLoaded,
                       "isDataLoaded should be false before load() is called")
    }

    func testEngine_predictsWithFallback_beforeDataLoad() {
        let engine = PredictionEngine()
        let results = engine.predict(context: "", currentWord: "mag")
        XCTAssertFalse(results.isEmpty, "Fallback should provide completions")
    }

    func testEngine_nextWordPredictions_fallback() {
        let engine = PredictionEngine()
        let results = engine.predict(context: "in", currentWord: "")
        XCTAssertEqual(results.count, 3, "Should return 3 predictions from fallback")
    }

    func testEngine_maxThreePredictions() {
        let engine = PredictionEngine()
        let results = engine.predict(context: "", currentWord: "a")
        XCTAssertLessThanOrEqual(results.count, 3,
                                 "Should return at most 3 predictions")
    }

    func testEngine_noMatchReturnsEmpty() {
        let engine = PredictionEngine()
        let results = engine.predict(context: "", currentWord: "xyzzy")
        XCTAssertTrue(results.isEmpty,
                      "Should return empty for a prefix with no matches")
    }

    func testEngine_deduplicatesAcrossSources() {
        let engine = PredictionEngine()
        // "mag" matches "magnus" in fallback; results should have no duplicates
        let results = engine.predict(context: "", currentWord: "mag")
        let lowered = results.map { $0.lowercased() }
        XCTAssertEqual(lowered.count, Set(lowered).count,
                       "Results should contain no duplicates")
    }

    func testEngine_emptyCurrentWord_triggersNextWord() {
        let engine = PredictionEngine()
        // With fallback only, we get shuffled common words — just verify we get some
        let results = engine.predict(context: "Roma", currentWord: "")
        XCTAssertFalse(results.isEmpty,
                       "Empty currentWord should trigger next-word prediction")
    }

    func testEngine_predictionsAreNotEmpty_strings() {
        let engine = PredictionEngine()
        let results = engine.predict(context: "", currentWord: "e")
        for result in results {
            XCTAssertFalse(result.isEmpty, "Each prediction should be non-empty")
        }
    }

    // MARK: - FrequencyCompletionSource — With Real Data

    private var testBundle: Bundle { Bundle(for: type(of: self)) }

    func testFrequency_loadData_succeeds() {
        let source = FrequencyCompletionSource()
        source.loadData(bundle: testBundle)
        XCTAssertTrue(source.isLoaded, "Should successfully load word_frequencies.json")
    }

    func testFrequency_completions_returnsResults() {
        let source = FrequencyCompletionSource()
        source.loadData(bundle: testBundle)
        let results = source.completions(context: "", prefix: "mag")
        XCTAssertFalse(results.isEmpty, "Should return completions for 'mag'")
    }

    func testFrequency_completions_topResultsByFrequency() {
        let source = FrequencyCompletionSource()
        source.loadData(bundle: testBundle)
        let results = source.completions(context: "", prefix: "mag")
        // "magnus" and "magis" should be among the top results for "mag"
        let hasHighFreqWord = results.contains { $0 == "magnus" || $0 == "magis" || $0 == "magno" || $0 == "magna" }
        XCTAssertTrue(hasHighFreqWord,
                      "Top completions for 'mag' should include common Latin words, got: \(results)")
    }

    func testFrequency_completions_singleCharPrefix() {
        let source = FrequencyCompletionSource()
        source.loadData(bundle: testBundle)
        let results = source.completions(context: "", prefix: "a")
        XCTAssertFalse(results.isEmpty, "Should return completions for single-char prefix 'a'")
    }

    func testFrequency_completions_maxFiveResults() {
        let source = FrequencyCompletionSource()
        source.loadData(bundle: testBundle)
        let results = source.completions(context: "", prefix: "a")
        XCTAssertLessThanOrEqual(results.count, 5, "Should return at most 5 results")
    }

    // MARK: - NGramPredictionSource — With Real Data

    func testNGram_loadData_succeeds() {
        let source = NGramPredictionSource()
        source.loadData(bundle: testBundle)
        XCTAssertTrue(source.isLoaded, "Should successfully load ngrams.json")
    }

    func testNGram_nextWordPredictions_returnsResults() {
        let source = NGramPredictionSource()
        source.loadData(bundle: testBundle)
        let results = source.nextWordPredictions(context: "in")
        XCTAssertFalse(results.isEmpty,
                       "Should return next-word predictions after 'in'")
    }

    func testNGram_nextWordPredictions_contextualResults() {
        let source = NGramPredictionSource()
        source.loadData(bundle: testBundle)
        // After "et" (and), common continuations should be real Latin words
        let results = source.nextWordPredictions(context: "et")
        XCTAssertFalse(results.isEmpty,
                       "Should return next-word predictions after 'et'")
    }

    // MARK: - PredictionEngine — With Loaded Data

    func testEngine_completions_withLoadedData() {
        let engine = PredictionEngine()
        engine.load()

        // Wait for data to load
        let loadExpectation = XCTestExpectation(description: "Data loads")
        engine.onDataLoaded = { loadExpectation.fulfill() }
        wait(for: [loadExpectation], timeout: 5.0)

        let results = engine.predict(context: "", currentWord: "mag")
        XCTAssertFalse(results.isEmpty, "Should return completions with loaded data")
    }

    func testEngine_nextWord_withLoadedData() {
        let engine = PredictionEngine()
        engine.load()

        let loadExpectation = XCTestExpectation(description: "Data loads")
        engine.onDataLoaded = { loadExpectation.fulfill() }
        wait(for: [loadExpectation], timeout: 5.0)

        let results = engine.predict(context: "in", currentWord: "")
        XCTAssertFalse(results.isEmpty, "Should return next-word predictions with loaded data")
    }
}
