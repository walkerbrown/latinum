import Foundation

/// Next-word prediction source backed by n-gram frequency tables.
///
/// Loads `ngrams.json` containing unigram, bigram, and trigram counts.
/// Predicts the most likely next word given the preceding 1-2 words,
/// falling back through trigram → bigram → unigram.
class NGramPredictionSource: PredictionSource {

    let identifier = "ngram"

    // Lookup tables built at load time.
    // Bigram index: previous word → [(next word, count)] sorted by count desc.
    private var bigramIndex: [String: [(String, Int)]] = [:]
    // Trigram index: "w1 w2" → [(next word, count)] sorted by count desc.
    private var trigramIndex: [String: [(String, Int)]] = [:]
    // Top unigrams for ultimate fallback, sorted by count desc.
    private var topUnigrams: [String] = []

    private(set) var isLoaded = false

    // MARK: - Loading

    /// Load `ngrams.json` synchronously (called from the inference queue).
    func loadData() {
        guard let url = Bundle.main.url(forResource: "ngrams", withExtension: "json") else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            // --- Unigrams ---
            if let uni = root["unigrams"] as? [String: Int] {
                let sorted = uni.sorted { $0.value > $1.value }
                topUnigrams = sorted.prefix(20).map { $0.key }
            }

            // --- Bigrams → index by first word ---
            if let bi = root["bigrams"] as? [String: Int] {
                var index: [String: [(String, Int)]] = [:]
                for (key, count) in bi {
                    let parts = key.split(separator: " ", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let w1 = String(parts[0])
                    let w2 = String(parts[1])
                    index[w1, default: []].append((w2, count))
                }
                // Sort each bucket by count descending
                for key in index.keys {
                    index[key]?.sort { $0.1 > $1.1 }
                }
                bigramIndex = index
            }

            // --- Trigrams → index by "w1 w2" ---
            if let tri = root["trigrams"] as? [String: Int] {
                var index: [String: [(String, Int)]] = [:]
                for (key, count) in tri {
                    let parts = key.split(separator: " ")
                    guard parts.count == 3 else { continue }
                    let prefix = "\(parts[0]) \(parts[1])"
                    let w3 = String(parts[2])
                    index[prefix, default: []].append((w3, count))
                }
                for key in index.keys {
                    index[key]?.sort { $0.1 > $1.1 }
                }
                trigramIndex = index
            }

            isLoaded = true
        } catch {
            print("NGramPredictionSource: failed to load data – \(error)")
        }
    }

    // MARK: - PredictionSource

    func completions(context: String, prefix: String) -> [String] {
        // N-gram source handles next-word prediction, not prefix completion.
        return []
    }

    func nextWordPredictions(context: String) -> [String] {
        guard isLoaded else { return [] }

        let words = lastWords(from: context, count: 2)

        var candidates: [String] = []
        var seen = Set<String>()

        // 1. Try trigram if we have 2 preceding words
        if words.count >= 2 {
            let key = "\(words[words.count - 2]) \(words[words.count - 1])"
            if let matches = trigramIndex[key] {
                for (word, _) in matches.prefix(3) {
                    if seen.insert(word).inserted {
                        candidates.append(word)
                    }
                }
            }
        }

        // 2. Fall back to bigram
        if let lastWord = words.last, candidates.count < 3 {
            if let matches = bigramIndex[lastWord] {
                for (word, _) in matches.prefix(3) {
                    if seen.insert(word).inserted {
                        candidates.append(word)
                    }
                    if candidates.count >= 3 { break }
                }
            }
        }

        // 3. Fall back to unigrams
        if candidates.count < 3 {
            for word in topUnigrams {
                if seen.insert(word).inserted {
                    candidates.append(word)
                }
                if candidates.count >= 3 { break }
            }
        }

        return Array(candidates.prefix(3))
    }

    // MARK: - Context Parsing

    /// Extract the last N words from the context, normalized.
    private func lastWords(from context: String, count: Int) -> [String] {
        let normalized = LatinNormalization.normalizeForModel(context)
        let tokens = normalized.split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        return Array(tokens.suffix(count))
    }
}
