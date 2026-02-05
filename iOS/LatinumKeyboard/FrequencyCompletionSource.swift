import Foundation

/// Word-completion source backed by a frequency-sorted word list.
///
/// Loads `word_frequencies.json` (an array of `[word, count]` pairs sorted by
/// descending frequency) and provides prefix-based completions.  The list is
/// pre-sorted alphabetically at load time so binary search can locate the
/// prefix range efficiently.
class FrequencyCompletionSource: PredictionSource {

    let identifier = "frequency"

    private var entries: [(word: String, freq: Int)] = []
    private(set) var isLoaded = false

    // MARK: - Loading

    func loadData(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "word_frequencies", withExtension: "json") else {
            // JSON resource not found in bundle
            return
        }
        do {
            let data = try Data(contentsOf: url)
            if let pairs = try JSONSerialization.jsonObject(with: data) as? [[Any]] {
                var loaded: [(String, Int)] = []
                loaded.reserveCapacity(pairs.count)
                for pair in pairs {
                    guard pair.count == 2,
                          let word = pair[0] as? String,
                          let count = pair[1] as? Int else { continue }
                    loaded.append((word, count))
                }
                loaded.sort { $0.0 < $1.0 }
                entries = loaded
                isLoaded = true
            }
        } catch {
        }
    }

    // MARK: - PredictionSource

    func completions(context: String, prefix: String) -> [String] {
        guard isLoaded, !prefix.isEmpty else { return [] }
        let lowPrefix = prefix.lowercased()

        let startIndex = lowerBound(for: lowPrefix)

        var candidates: [(String, Int)] = []
        for i in startIndex..<entries.count {
            let entry = entries[i]
            if entry.word.hasPrefix(lowPrefix) {
                if entry.word != lowPrefix {
                    candidates.append(entry)
                }
            } else {
                break
            }
        }

        candidates.sort { $0.1 > $1.1 }
        return candidates.prefix(5).map { $0.0 }
    }

    func nextWordPredictions(context: String) -> [String] {
        return []
    }

    // MARK: - Binary Search

    private func lowerBound(for prefix: String) -> Int {
        var lo = 0
        var hi = entries.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if entries[mid].word < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }
}
