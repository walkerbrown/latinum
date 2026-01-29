import Foundation

/// Latin text normalization utilities for the Latinum keyboard.
/// Handles macron stripping, ligature expansion, and diacritic preservation.
enum LatinNormalization {

    // MARK: - Macron Mappings

    /// Maps macronized vowels to their base form
    static let macronToBase: [Character: Character] = [
        "\u{0101}": "a",  // ā
        "\u{0113}": "e",  // ē
        "\u{012B}": "i",  // ī
        "\u{014D}": "o",  // ō
        "\u{016B}": "u",  // ū
        "\u{0233}": "y",  // ȳ
        "\u{0100}": "A",  // Ā
        "\u{0112}": "E",  // Ē
        "\u{012A}": "I",  // Ī
        "\u{014C}": "O",  // Ō
        "\u{016A}": "U",  // Ū
        "\u{0232}": "Y",  // Ȳ
    ]

    /// Maps base vowels to macronized form (lowercase)
    static let baseToMacronLower: [Character: Character] = [
        "a": "\u{0101}",  // ā
        "e": "\u{0113}",  // ē
        "i": "\u{012B}",  // ī
        "o": "\u{014D}",  // ō
        "u": "\u{016B}",  // ū
        "y": "\u{0233}",  // ȳ
    ]

    /// Maps base vowels to macronized form (uppercase)
    static let baseToMacronUpper: [Character: Character] = [
        "A": "\u{0100}",  // Ā
        "E": "\u{0112}",  // Ē
        "I": "\u{012A}",  // Ī
        "O": "\u{014C}",  // Ō
        "U": "\u{016A}",  // Ū
        "Y": "\u{0232}",  // Ȳ
    ]

    // MARK: - Ligature Mappings

    /// Maps ligatures to their expanded form
    static let ligatureToExpanded: [Character: String] = [
        "\u{00E6}": "ae",  // æ
        "\u{00C6}": "Ae",  // Æ
        "\u{0153}": "oe",  // œ
        "\u{0152}": "Oe",  // Œ
    ]

    // MARK: - Normalization Functions

    /// Strip macrons from text for model input
    static func stripMacrons(_ text: String) -> String {
        var result = ""
        for char in text {
            if let base = macronToBase[char] {
                result.append(base)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Expand ligatures for model input
    static func expandLigatures(_ text: String) -> String {
        var result = ""
        for char in text {
            if let expanded = ligatureToExpanded[char] {
                result.append(expanded)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Fully normalize text for model queries
    static func normalizeForModel(_ text: String) -> String {
        return expandLigatures(stripMacrons(text)).lowercased()
    }

    /// Get long-press options for a character
    static func getLongPressOptions(_ char: Character) -> [Character] {
        var options: [Character] = []

        // Macron options
        if let macron = baseToMacronLower[char] {
            options.append(macron)
        } else if let macron = baseToMacronUpper[char] {
            options.append(macron)
        }

        // Ligature options
        switch char {
        case "a": options.append("\u{00E6}")  // æ
        case "A": options.append("\u{00C6}")  // Æ
        case "o": options.append("\u{0153}")  // œ
        case "O": options.append("\u{0152}")  // Œ
        default: break
        }

        return options
    }

    /// Apply completion while preserving user's macrons
    ///
    /// The model returns completions in normalized (macron-free) form.
    /// This function merges the completion with the user's text, preserving
    /// any macrons or ligatures the user has already typed.
    ///
    /// Example:
    ///     userText = "amā"  (user typed macron)
    ///     completion = "amare"  (model suggests)
    ///     result = "amāre"  (macron preserved, completion extended)
    static func applyCompletionPreservingDiacritics(
        userText: String,
        completion: String
    ) -> String {
        guard !userText.isEmpty else { return completion }

        let userNormalized = normalizeForModel(userText)

        guard completion.lowercased().hasPrefix(userNormalized) else {
            return completion
        }

        let extensionStart = completion.index(
            completion.startIndex,
            offsetBy: userNormalized.count
        )
        let extensionPart = String(completion[extensionStart...])

        return userText + extensionPart
    }
}
