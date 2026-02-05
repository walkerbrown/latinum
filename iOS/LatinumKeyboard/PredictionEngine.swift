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
/// Coordinates one or more `PredictionSource` instances and manages:
/// - Async inference on a dedicated serial queue
/// - Merging and deduplicating results across sources
/// - Macron/diacritic preservation
class PredictionEngine {

    // MARK: - Properties

    /// Registered prediction sources, queried in order of priority
    private var sources: [PredictionSource] = []

    /// Dedicated serial queue for all inference work (keeps main thread free)
    private let inferenceQueue = DispatchQueue(label: "com.latinum.prediction", qos: .userInitiated)

    /// Callback invoked on main thread when data finishes loading
    var onDataLoaded: (() -> Void)?

    /// Whether the primary data sources have loaded
    var isDataLoaded: Bool {
        return frequencySource.isLoaded || ngramSource.isLoaded
    }

    /// Frequency-based word completion source
    private let frequencySource = FrequencyCompletionSource()

    /// N-gram next-word prediction source
    private let ngramSource = NGramPredictionSource()

    /// Hardcoded fallback source (always available)
    private let fallbackSource = FallbackPredictionSource()

    // MARK: - Initialization

    init() {
        // Source chain: frequency for completions, n-gram for next-word, fallback last.
        sources = [frequencySource, ngramSource, fallbackSource]
    }

    // MARK: - Source Management

    /// Insert a prediction source at the given priority index.
    /// Lower index = higher priority. Sources are queried in order.
    func addSource(_ source: PredictionSource, at index: Int? = nil) {
        let insertIndex = index ?? max(sources.count - 1, 0) // before fallback by default
        sources.insert(source, at: min(insertIndex, sources.count))
    }

    // MARK: - Data Loading

    /// Load JSON data files asynchronously to avoid blocking keyboard launch.
    /// Fallback predictions are used until the data is ready.
    func load() {
        inferenceQueue.async { [weak self] in
            guard let self = self else { return }
            self.frequencySource.loadData()
            self.ngramSource.loadData()

            DispatchQueue.main.async {
                self.onDataLoaded?()
            }
        }
    }

    // MARK: - Async Prediction

    /// Generate predictions asynchronously on the inference queue.
    /// Results are delivered on the main thread via the completion handler.
    ///
    /// - Parameters:
    ///   - context: Full text context before cursor
    ///   - currentWord: The word currently being typed (empty for next-word prediction)
    ///   - completion: Called on main thread with prediction results (max 3)
    func predictAsync(context: String, currentWord: String, completion: @escaping ([String]) -> Void) {
        inferenceQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let results: [String]
            if currentWord.isEmpty {
                results = self.mergedNextWordPredictions(context: context)
            } else {
                results = self.mergedCompletions(context: context, prefix: currentWord)
            }

            DispatchQueue.main.async {
                completion(results)
            }
        }
    }

    // MARK: - Source Merging

    /// Merge completions from all sources, preserving diacritics and deduplicating.
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

    /// Merge next-word predictions from all sources, deduplicating.
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
