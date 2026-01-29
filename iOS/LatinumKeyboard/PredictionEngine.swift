import Foundation
import CoreML

/// Engine for generating Latin word predictions using Core ML model
///
/// This class handles:
/// - Loading the Core ML model
/// - Normalizing input text (stripping macrons for model queries)
/// - Generating completions based on context
/// - Preserving user-entered macrons in suggestions
class PredictionEngine {

    // MARK: - Properties

    /// The Core ML model for predictions
    private var model: MLModel?

    /// Tokenizer for encoding/decoding text
    private let tokenizer = CharacterTokenizer()

    /// Maximum context length for the model
    private let maxContextLength = 64

    /// Whether the model loaded successfully
    private(set) var isLoaded = false

    /// Fallback word list for when model is unavailable
    private var fallbackWords: [String] = []

    // MARK: - Initialization

    init() {
        loadFallbackWords()
    }

    // MARK: - Model Loading

    /// Load the Core ML model
    func load() {
        // Try to load the ML model
        do {
            // Look for model in the extension bundle
            if let modelURL = Bundle.main.url(forResource: "LatinLM", withExtension: "mlmodelc") {
                let config = MLModelConfiguration()
                config.computeUnits = .all  // Let Core ML decide CPU/GPU/ANE
                model = try MLModel(contentsOf: modelURL, configuration: config)
                isLoaded = true
                print("Loaded Core ML model successfully")
            } else {
                print("Core ML model not found, using fallback")
            }
        } catch {
            print("Failed to load Core ML model: \(error)")
        }
    }

    /// Load fallback word list
    private func loadFallbackWords() {
        // Common Latin words for fallback predictions
        fallbackWords = [
            "et", "in", "est", "non", "cum", "ad", "ut", "qui", "quod", "sed",
            "ex", "de", "ab", "per", "pro", "hoc", "aut", "nec", "ac", "si",
            "esse", "sunt", "erat", "fuit", "habet", "dicit", "facit", "videt",
            "amare", "habere", "dicere", "facere", "videre", "scire", "posse",
            "magnus", "bonus", "malus", "novus", "primus", "omnis", "totus",
            "homo", "deus", "rex", "terra", "aqua", "caelum", "bellum", "verbum",
            "Roma", "Caesar", "Marcus", "Cicero", "Seneca",
        ]
    }

    // MARK: - Prediction

    /// Generate predictions for the current context
    ///
    /// - Parameters:
    ///   - context: Full text context before cursor
    ///   - currentWord: The word currently being typed
    /// - Returns: Array of prediction strings (max 3)
    func predict(context: String, currentWord: String) -> [String] {
        // If no current word, predict next word
        if currentWord.isEmpty {
            return predictNextWord(context: context)
        }

        // Otherwise, complete the current word
        return completeWord(context: context, prefix: currentWord)
    }

    /// Complete the current word being typed
    private func completeWord(context: String, prefix: String) -> [String] {
        // Normalize prefix for model query (remove macrons but remember them)
        let normalizedPrefix = LatinNormalization.stripMacrons(prefix)

        // Get model predictions
        var completions: [String]
        if isLoaded, let model = model {
            completions = getModelCompletions(context: context, prefix: normalizedPrefix)
        } else {
            completions = getFallbackCompletions(prefix: normalizedPrefix)
        }

        // Apply macron preservation - keep user's macrons in suggestions
        completions = completions.map { completion in
            LatinNormalization.applyCompletionPreservingDiacritics(
                userText: prefix,
                completion: completion
            )
        }

        return Array(completions.prefix(3))
    }

    /// Predict the next word after a space
    private func predictNextWord(context: String) -> [String] {
        if isLoaded, let model = model {
            return getModelNextWords(context: context)
        } else {
            // Return common Latin words as fallback
            return Array(fallbackWords.shuffled().prefix(3))
        }
    }

    // MARK: - Model Inference

    /// Get completions from the Core ML model
    private func getModelCompletions(context: String, prefix: String) -> [String] {
        guard let model = model else { return [] }

        // Normalize full context
        let normalizedContext = LatinNormalization.normalizeForModel(context)

        // Encode context
        var inputIds = tokenizer.encode(normalizedContext, addBos: true)

        // Truncate to max length
        if inputIds.count > maxContextLength {
            inputIds = Array(inputIds.suffix(maxContextLength))
        }

        // Pad to fixed length
        while inputIds.count < maxContextLength {
            inputIds.insert(CharacterTokenizer.padId, at: 0)
        }

        // Generate completions using beam search
        var completions: [String] = []

        do {
            // Run model inference
            let inputArray = try MLMultiArray(shape: [1, NSNumber(value: maxContextLength)], dataType: .int32)
            for (i, id) in inputIds.enumerated() {
                inputArray[i] = NSNumber(value: id)
            }

            let prediction = try model.prediction(from: MLDictionaryFeatureProvider(
                dictionary: ["input_ids": MLFeatureValue(multiArray: inputArray)]
            ))

            if let logits = prediction.featureValue(for: "logits")?.multiArrayValue {
                // Get top characters
                let topChars = getTopCharacters(from: logits, k: 5)

                // Generate completions by continuing from prefix
                for char in topChars {
                    let completion = prefix + String(char)
                    completions.append(completion)
                }
            }
        } catch {
            print("Model inference error: \(error)")
        }

        return completions
    }

    /// Get next word predictions from model
    private func getModelNextWords(context: String) -> [String] {
        // Similar to getModelCompletions but starts from space
        // For now, use fallback
        return Array(fallbackWords.shuffled().prefix(3))
    }

    /// Extract top K characters from logits
    private func getTopCharacters(from logits: MLMultiArray, k: Int) -> [Character] {
        var scores: [(Int, Float)] = []

        for i in 0..<logits.count {
            scores.append((i, logits[i].floatValue))
        }

        // Sort by score descending
        scores.sort { $0.1 > $1.1 }

        // Convert top K to characters
        var chars: [Character] = []
        for (id, _) in scores.prefix(k) {
            if let char = CharacterTokenizer.idToChar[id] {
                chars.append(char)
            }
        }

        return chars
    }

    // MARK: - Fallback Predictions

    /// Get fallback completions when model is unavailable
    private func getFallbackCompletions(prefix: String) -> [String] {
        let lowercasePrefix = prefix.lowercased()

        // Filter words that start with prefix
        let matches = fallbackWords.filter { word in
            word.lowercased().hasPrefix(lowercasePrefix)
        }

        // Sort by length (shorter = more likely to be wanted)
        let sorted = matches.sorted { $0.count < $1.count }

        // Match case of first letter
        let cased = sorted.map { word -> String in
            if let first = prefix.first, first.isUppercase {
                return word.prefix(1).uppercased() + word.dropFirst()
            }
            return word
        }

        return Array(cased.prefix(3))
    }
}
