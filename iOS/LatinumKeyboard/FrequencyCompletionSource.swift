import Foundation

/// Word-completion source backed by a frequency-sorted word list.
///
/// Loads `word_frequencies.json` (an array of `[word, count]` pairs sorted by
/// descending frequency) and provides prefix-based completions.  The list is
/// pre-sorted alphabetically at load time so binary search can locate the
/// prefix range efficiently.
class FrequencyCompletionSource: PredictionSource {

    let identifier = "frequency"

    /// Alphabetically sorted entries for binary-search prefix lookup.
    /// Each entry is (word, frequency).
    private var entries: [(word: String, freq: Int)] = []

    /// Whether the data has been loaded.
    private(set) var isLoaded = false

    // MARK: - Loading

    /// Load `word_frequencies.json` synchronously (called from the inference queue).
    func loadData(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "word_frequencies", withExtension: "json") else {
            // JSON resource not found in bundle
            return
        }
        do {
            let data = try Data(contentsOf: url)
            // The file is a JSON array of [word, count] pairs.
            if let pairs = try JSONSerialization.jsonObject(with: data) as? [[Any]] {
                var loaded: [(String, Int)] = []
                loaded.reserveCapacity(pairs.count)
                for pair in pairs {
                    guard pair.count == 2,
                          let word = pair[0] as? String,
                          let count = pair[1] as? Int else { continue }
                    loaded.append((word, count))
                }
                // Sort alphabetically for binary search
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

        // Binary search for the first entry >= prefix
        let startIndex = lowerBound(for: lowPrefix)

        // Collect all entries that share the prefix, then pick top-N by frequency
        var candidates: [(String, Int)] = []
        for i in startIndex..<entries.count {
            let entry = entries[i]
            if entry.word.hasPrefix(lowPrefix) {
                // Skip exact match (user already typed the full word)
                if entry.word != lowPrefix {
                    candidates.append(entry)
                }
            } else {
                break  // Past the prefix range
            }
        }

        // Sort candidates by frequency (descending) and return top 5
        candidates.sort { $0.1 > $1.1 }
        return candidates.prefix(5).map { $0.0 }
    }

    func nextWordPredictions(context: String) -> [String] {
        // Frequency source only handles prefix completion, not next-word.
        return []
    }

    // MARK: - Binary Search

    /// Return the index of the first entry whose word is >= `prefix`.
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
