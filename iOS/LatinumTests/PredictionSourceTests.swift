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
        let expectation = XCTestExpectation(description: "Prediction completes")
        engine.predictAsync(context: "", currentWord: "mag") { results in
            XCTAssertFalse(results.isEmpty, "Fallback should provide completions")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testEngine_nextWordPredictions_fallback() {
        let engine = PredictionEngine()
        let expectation = XCTestExpectation(description: "Next-word prediction completes")
        engine.predictAsync(context: "in", currentWord: "") { results in
            XCTAssertEqual(results.count, 3, "Should return 3 predictions from fallback")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testEngine_maxThreePredictions() {
        let engine = PredictionEngine()
        let expectation = XCTestExpectation(description: "Prediction completes")
        engine.predictAsync(context: "", currentWord: "a") { results in
            XCTAssertLessThanOrEqual(results.count, 3,
                                     "Should return at most 3 predictions")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testEngine_noMatchReturnsEmpty() {
        let engine = PredictionEngine()
        let expectation = XCTestExpectation(description: "Prediction completes")
        engine.predictAsync(context: "", currentWord: "xyzzy") { results in
            XCTAssertTrue(results.isEmpty,
                          "Should return empty for a prefix with no matches")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testEngine_deduplicatesAcrossSources() {
        let engine = PredictionEngine()
        let expectation = XCTestExpectation(description: "Prediction completes")
        // "mag" matches "magnus" in fallback; results should have no duplicates
        engine.predictAsync(context: "", currentWord: "mag") { results in
            let lowered = results.map { $0.lowercased() }
            XCTAssertEqual(lowered.count, Set(lowered).count,
                           "Results should contain no duplicates")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testEngine_emptyCurrentWord_triggersNextWord() {
        let engine = PredictionEngine()
        let expectation = XCTestExpectation(description: "Prediction completes")
        engine.predictAsync(context: "Roma", currentWord: "") { results in
            // With fallback only, we get shuffled common words — just verify we get some
            XCTAssertFalse(results.isEmpty,
                           "Empty currentWord should trigger next-word prediction")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testEngine_predictionsAreNotEmpty_strings() {
        let engine = PredictionEngine()
        let expectation = XCTestExpectation(description: "Prediction completes")
        engine.predictAsync(context: "", currentWord: "e") { results in
            for result in results {
                XCTAssertFalse(result.isEmpty, "Each prediction should be non-empty")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }
}
