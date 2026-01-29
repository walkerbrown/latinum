import Foundation

/// Character-level tokenizer for Latin text prediction
struct CharacterTokenizer {

    // MARK: - Special Token IDs

    static let padId = 0
    static let unkId = 1
    static let bosId = 2
    static let eosId = 3
    static let spaceId = 4

    // MARK: - Vocabulary

    static let vocabSize = 78

    /// Character to ID mapping
    static let charToId: [Character: Int] = [
        " ": 4,
        "a": 5, "b": 6, "c": 7, "d": 8, "e": 9, "f": 10, "g": 11, "h": 12,
        "i": 13, "j": 14, "k": 15, "l": 16, "m": 17, "n": 18, "o": 19, "p": 20,
        "q": 21, "r": 22, "s": 23, "t": 24, "u": 25, "v": 26, "w": 27, "x": 28,
        "y": 29, "z": 30,
        "A": 31, "B": 32, "C": 33, "D": 34, "E": 35, "F": 36, "G": 37, "H": 38,
        "I": 39, "J": 40, "K": 41, "L": 42, "M": 43, "N": 44, "O": 45, "P": 46,
        "Q": 47, "R": 48, "S": 49, "T": 50, "U": 51, "V": 52, "W": 53, "X": 54,
        "Y": 55, "Z": 56,
        ".": 57, ",": 58, ";": 59, ":": 60, "!": 61, "?": 62, "'": 63, "-": 64,
        "\"": 65, "(": 66, ")": 67,
        "0": 68, "1": 69, "2": 70, "3": 71, "4": 72, "5": 73, "6": 74, "7": 75,
        "8": 76, "9": 77,
    ]

    /// ID to character mapping
    static let idToChar: [Int: Character] = [
        4: " ",
        5: "a", 6: "b", 7: "c", 8: "d", 9: "e", 10: "f", 11: "g", 12: "h",
        13: "i", 14: "j", 15: "k", 16: "l", 17: "m", 18: "n", 19: "o", 20: "p",
        21: "q", 22: "r", 23: "s", 24: "t", 25: "u", 26: "v", 27: "w", 28: "x",
        29: "y", 30: "z",
        31: "A", 32: "B", 33: "C", 34: "D", 35: "E", 36: "F", 37: "G", 38: "H",
        39: "I", 40: "J", 41: "K", 42: "L", 43: "M", 44: "N", 45: "O", 46: "P",
        47: "Q", 48: "R", 49: "S", 50: "T", 51: "U", 52: "V", 53: "W", 54: "X",
        55: "Y", 56: "Z",
        57: ".", 58: ",", 59: ";", 60: ":", 61: "!", 62: "?", 63: "'", 64: "-",
        65: "\"", 66: "(", 67: ")",
        68: "0", 69: "1", 70: "2", 71: "3", 72: "4", 73: "5", 74: "6", 75: "7",
        76: "8", 77: "9",
    ]

    // MARK: - Encoding

    /// Encode text to token IDs
    static func encode(_ text: String, addBos: Bool = false, addEos: Bool = false) -> [Int] {
        var ids: [Int] = []

        if addBos {
            ids.append(bosId)
        }

        for char in text {
            if let id = charToId[char] {
                ids.append(id)
            } else {
                ids.append(unkId)
            }
        }

        if addEos {
            ids.append(eosId)
        }

        return ids
    }

    /// Instance method for encoding
    func encode(_ text: String, addBos: Bool = false, addEos: Bool = false) -> [Int] {
        return Self.encode(text, addBos: addBos, addEos: addEos)
    }

    // MARK: - Decoding

    /// Decode token IDs back to text
    static func decode(_ ids: [Int], skipSpecial: Bool = true) -> String {
        var chars: [Character] = []
        let specialIds: Set<Int> = skipSpecial
            ? [padId, bosId, eosId, unkId]
            : [padId, bosId, eosId]

        for id in ids {
            guard !specialIds.contains(id),
                  let char = idToChar[id] else {
                continue
            }
            chars.append(char)
        }

        return String(chars)
    }

    /// Instance method for decoding
    func decode(_ ids: [Int], skipSpecial: Bool = true) -> String {
        return Self.decode(ids, skipSpecial: skipSpecial)
    }
}
