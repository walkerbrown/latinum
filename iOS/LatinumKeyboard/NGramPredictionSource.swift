import Foundation

/// Next-word prediction source backed by n-gram frequency tables.
///
/// Loads `ngrams.json` containing unigram, bigram, and trigram counts.
/// Predicts the most likely next word given the preceding 1-2 words,
/// falling back through trigram → bigram → unigram.
class NGramPredictionSource: PredictionSource {

    let identifier = "ngram"

    private var bigramIndex: [String: [(String, Int)]] = [:]
    private var trigramIndex: [String: [(String, Int)]] = [:]
    private var topUnigrams: [String] = []
    private(set) var isLoaded = false

    // MARK: - Loading

    func loadData(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "ngrams", withExtension: "json") else {
            // JSON resource not found in bundle
            return
        }
        do {
            let data = try Data(contentsOf: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            if let uni = root["unigrams"] as? [String: Int] {
                let sorted = uni.sorted { $0.value > $1.value }
                topUnigrams = sorted.prefix(20).map { $0.key }
            }

            if let bi = root["bigrams"] as? [String: Int] {
                var index: [String: [(String, Int)]] = [:]
                for (key, count) in bi {
                    let parts = key.split(separator: " ", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let w1 = String(parts[0])
                    let w2 = String(parts[1])
                    index[w1, default: []].append((w2, count))
                }
                for key in index.keys {
                    index[key]?.sort { $0.1 > $1.1 }
                }
                bigramIndex = index
            }

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
        }
    }

    // MARK: - PredictionSource

    func completions(context: String, prefix: String) -> [String] {
        return []
    }

    func nextWordPredictions(context: String) -> [String] {
        guard isLoaded else { return [] }

        let words = lastWords(from: context, count: 2)

        var candidates: [String] = []
        var seen = Set<String>()

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

    private func lastWords(from context: String, count: Int) -> [String] {
        let normalized = LatinNormalization.normalizeForModel(context)
        let tokens = normalized.split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        return Array(tokens.suffix(count))
    }
}
