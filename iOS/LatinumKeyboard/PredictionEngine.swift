import Foundation

/// Protocol for pluggable prediction sources.
/// Each source provides completions and/or next-word predictions independently.
/// The PredictionEngine merges results from all registered sources.
///
/// Future sources: UILexicon (system autocorrection lexicon), user-trained n-gram model,
/// domain-specific dictionaries (ecclesiastical Latin, classical Latin, etc.)
protocol PredictionSource: AnyObject {
    /// Unique identifier for this source (for deduplication and priority)
    var identifier: String { get }

    /// Return word completions for the given prefix, ordered by confidence.
    func completions(context: String, prefix: String) -> [String]

    /// Return next-word predictions when no prefix is being typed.
    func nextWordPredictions(context: String) -> [String]
}

/// Engine for generating Latin word predictions.
///
/// Coordinates one or more `PredictionSource` instances, merging and
/// deduplicating results across sources while preserving macrons/diacritics.
class PredictionEngine {

    // MARK: - Properties

    private var sources: [PredictionSource] = []

    /// Serial queue for loading data and running prediction lookups off the main thread.
    private let predictionQueue = DispatchQueue(label: "org.walkerbrown.latinum.prediction", qos: .userInitiated)

    var onDataLoaded: (() -> Void)?

    var isDataLoaded: Bool {
        return frequencySource.isLoaded || ngramSource.isLoaded
    }

    private let frequencySource = FrequencyCompletionSource()
    private let ngramSource = NGramPredictionSource()
    private let fallbackSource = FallbackPredictionSource()

    // MARK: - Initialization

    init() {
        sources = [frequencySource, ngramSource, fallbackSource]
    }

    // MARK: - Source Management

    /// Insert a prediction source before the fallback (or at a specific index).
    func addSource(_ source: PredictionSource, at index: Int? = nil) {
        let insertIndex = index ?? max(sources.count - 1, 0)
        sources.insert(source, at: min(insertIndex, sources.count))
    }

    // MARK: - Data Loading

    /// Load JSON data files asynchronously. Fallback predictions are used until ready.
    func load() {
        predictionQueue.async { [weak self] in
            guard let self = self else { return }
            self.frequencySource.loadData()
            self.ngramSource.loadData()

            DispatchQueue.main.async {
                self.onDataLoaded?()
            }
        }
    }

    // MARK: - Prediction

    /// Generate up to 3 predictions synchronously.
    func predict(context: String, currentWord: String) -> [String] {
        if currentWord.isEmpty {
            return mergedNextWordPredictions(context: context)
        } else {
            return mergedCompletions(context: context, prefix: currentWord)
        }
    }

    /// Generate predictions asynchronously on the prediction queue, delivering results on the main thread.
    /// Returns a `DispatchWorkItem` that the caller can cancel to discard stale results.
    @discardableResult
    func predictAsync(context: String, currentWord: String, completion: @escaping ([String]) -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let results = self.predict(context: context, currentWord: currentWord)
            DispatchQueue.main.async {
                completion(results)
            }
        }
        predictionQueue.async(execute: work)
        return work
    }

    // MARK: - Source Merging

    private func mergedCompletions(context: String, prefix: String) -> [String] {
        let normalizedPrefix = LatinNormalization.stripMacrons(prefix)
        var seen = Set<String>()
        var merged: [String] = []

        for source in sources {
            let completions = source.completions(context: context, prefix: normalizedPrefix)
            for completion in completions {
                let preserved = LatinNormalization.applyCompletionPreservingDiacritics(
                    userText: prefix,
                    completion: completion
                )
                let key = preserved.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    merged.append(preserved)
                }
                if merged.count >= 3 { break }
            }
            if merged.count >= 3 { break }
        }

        return Array(merged.prefix(3))
    }

    private func mergedNextWordPredictions(context: String) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        for source in sources {
            let predictions = source.nextWordPredictions(context: context)
            for prediction in predictions {
                let key = prediction.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    merged.append(prediction)
                }
                if merged.count >= 3 { break }
            }
            if merged.count >= 3 { break }
        }

        return Array(merged.prefix(3))
    }
}

// MARK: - Fallback Prediction Source

/// Low-priority source using a hardcoded list of common Latin words.
/// Always available, used when JSON data has not yet loaded or returns no results.
class FallbackPredictionSource: PredictionSource {

    let identifier = "fallback"

    private let words: [String] = [
        // Function words (most frequent in any Latin text)
        "et", "in", "est", "non", "cum", "ad", "ut", "qui", "quod", "sed",
        "ex", "de", "ab", "per", "pro", "hoc", "aut", "nec", "ac", "si",
        "iam", "tamen", "enim", "autem", "nam", "quidem", "atque", "nunc",
        "ergo", "ita", "sic", "quam", "tam", "ubi", "unde", "ibi", "hinc",
        "ante", "post", "inter", "super", "sub", "apud", "contra", "propter",
        // Common verbs
        "esse", "sunt", "erat", "fuit", "habet", "dicit", "facit", "videt",
        "amare", "habere", "dicere", "facere", "videre", "scire", "posse",
        "venit", "fecit", "dixit", "dedit", "cepit", "misit", "posuit",
        "ait", "inquit", "iussit", "voluit", "potuit", "debuit",
        // Common nouns
        "homo", "deus", "rex", "terra", "aqua", "caelum", "bellum", "verbum",
        "animus", "corpus", "tempus", "nomen", "genus", "opus", "ius",
        "res", "dies", "manus", "domus", "urbs", "gens", "pars", "vox",
        "vita", "mors", "pax", "lux", "vis", "lex", "fides", "spes",
        // Common adjectives
        "magnus", "bonus", "malus", "novus", "primus", "omnis", "totus",
        "alius", "alter", "nullus", "ullus", "multus", "parvus", "longus",
        // Pronouns and demonstratives
        "ego", "tu", "nos", "vos", "se", "ille", "ipse", "hic", "is",
        "quis", "quae", "meus", "tuus", "suus", "noster", "vester",
        // Proper nouns
        "Roma", "Caesar", "Marcus", "Cicero", "Seneca",
    ]

    func completions(context: String, prefix: String) -> [String] {
        guard !prefix.isEmpty else { return [] }
        let lowercasePrefix = prefix.lowercased()
        let matches = words
            .filter { $0.lowercased().hasPrefix(lowercasePrefix) && $0.lowercased() != lowercasePrefix }
            .sorted { $0.count < $1.count }

        return matches.map { word in
            if let first = prefix.first, first.isUppercase {
                return word.prefix(1).uppercased() + word.dropFirst()
            }
            return word
        }
    }

    func nextWordPredictions(context: String) -> [String] {
        return Array(words.prefix(20).shuffled().prefix(3))
    }
}
