import UIKit

/// Main keyboard view controller for the Latinum Latin keyboard extension.
///
/// This controller manages:
/// - The keyboard layout and key views
/// - User input handling
/// - Prediction generation and display
/// - Macron and ligature long-press handling
class KeyboardViewController: UIInputViewController {

    // MARK: - Properties

    /// The main keyboard view
    private var keyboardView: KeyboardView!

    /// Prediction engine for generating suggestions
    private var predictionEngine: PredictionEngine!

    /// Current shift state
    private var shiftState: ShiftState = .lowercase

    /// The text currently being typed (for prediction context)
    private var currentWord: String = ""

    /// Previously computed current word (to avoid redundant prediction updates)
    private var lastCurrentWord: String?

    /// Cached raw predictions (before capitalization)
    private var rawPredictions: [String] = []

    /// Cached keyboard type to detect changes
    private var lastKeyboardType: UIKeyboardType?

    // MARK: - Lifecycle

    override func loadView() {
        keyboardView = KeyboardView()
        keyboardView.delegate = self
        view = keyboardView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPredictionEngine()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateKeyboardConfiguration()
        updateAutoCapitalization()
        updatePredictions()
        applyPredictionCapitalization()
    }

    // MARK: - Keyboard Configuration

    /// Update keyboard configuration based on system state
    private func updateKeyboardConfiguration() {
        // Update globe key visibility based on whether multiple keyboards are enabled
        keyboardView.updateGlobeKeyVisibility(needsInputModeSwitchKey)

        // Update keyboard type if changed
        let currentType = textDocumentProxy.keyboardType ?? .default
        if currentType != lastKeyboardType {
            lastKeyboardType = currentType
            keyboardView.updateKeyboardType(currentType)
        }
    }

    // MARK: - Setup

    private func setupPredictionEngine() {
        predictionEngine = PredictionEngine()
        predictionEngine.load()
    }

    // MARK: - Text Input

    override func textDidChange(_ textInput: UITextInput?) {
        // Update keyboard configuration (type, globe visibility) when context changes
        updateKeyboardConfiguration()
        // Update context when text changes externally
        updateCurrentWord()
        updatePredictions()
    }

    /// Get the current word being typed from the text document context
    private func updateCurrentWord() {
        guard let context = textDocumentProxy.documentContextBeforeInput else {
            currentWord = ""
            return
        }

        // Find the start of the current word
        var word = ""
        for char in context.reversed() {
            if char.isLetter || char == "'" || char == "-" {
                word = String(char) + word
            } else {
                break
            }
        }
        currentWord = word
    }

    /// Update prediction suggestions based on current context (only if current word changed)
    private func updatePredictions() {
        // Skip if current word hasn't changed
        guard currentWord != lastCurrentWord else { return }
        lastCurrentWord = currentWord

        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        rawPredictions = predictionEngine.predict(context: context, currentWord: currentWord)
        applyPredictionCapitalization()
    }

    /// Re-apply capitalization to cached predictions (for shift state changes)
    private func applyPredictionCapitalization() {
        let capitalizedPredictions = rawPredictions.map { applyCapitalization($0) }
        keyboardView.updatePredictions(capitalizedPredictions)
    }

    /// Apply capitalization to a word based on current shift state
    private func applyCapitalization(_ text: String) -> String {
        switch shiftState {
        case .lowercase:
            return text
        case .uppercase:
            return text.prefix(1).uppercased() + text.dropFirst()
        case .capsLock:
            return text.uppercased()
        }
    }

    /// Enable uppercase based on autocapitalizationType and context
    private func updateAutoCapitalization() {
        // Respect the text field's autocapitalization preference
        let autocapType = textDocumentProxy.autocapitalizationType ?? .sentences

        switch autocapType {
        case .none:
            // Never auto-capitalize; leave shift state as-is unless user changed it
            return

        case .allCharacters:
            // Always uppercase (but don't override caps lock)
            if shiftState == .lowercase {
                shiftState = .uppercase
                keyboardView.updateShiftState(shiftState)
            }
            return

        case .words:
            // Capitalize at start of text or after whitespace
            let context = textDocumentProxy.documentContextBeforeInput ?? ""
            if context.isEmpty || context.last?.isWhitespace == true {
                if shiftState == .lowercase {
                    shiftState = .uppercase
                    keyboardView.updateShiftState(shiftState)
                }
            }

        case .sentences:
            // Capitalize at start of text, after sentence-ending punctuation, or new paragraph
            let context = textDocumentProxy.documentContextBeforeInput ?? ""
            if context.isEmpty || context.hasSuffix(". ") || context.hasSuffix("? ") || context.hasSuffix("! ") || context.hasSuffix("\n") {
                if shiftState == .lowercase {
                    shiftState = .uppercase
                    keyboardView.updateShiftState(shiftState)
                }
            }

        @unknown default:
            // Fall back to sentence capitalization for future cases
            let context = textDocumentProxy.documentContextBeforeInput ?? ""
            if context.isEmpty || context.hasSuffix(". ") || context.hasSuffix("\n") {
                if shiftState == .lowercase {
                    shiftState = .uppercase
                    keyboardView.updateShiftState(shiftState)
                }
            }
        }
    }

    // MARK: - Key Handling

    /// Insert a character from the keyboard
    func insertCharacter(_ char: String) {
        // Handle shift state
        let charToInsert: String
        switch shiftState {
        case .lowercase:
            charToInsert = char.lowercased()
        case .uppercase, .capsLock:
            charToInsert = char.uppercased()
        }

        textDocumentProxy.insertText(charToInsert)

        // Return to lowercase after single uppercase
        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        updateCurrentWord()
        updatePredictions()
    }

    /// Insert a special character (macron, ligature)
    func insertSpecialCharacter(_ char: String) {
        textDocumentProxy.insertText(char)

        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        updateCurrentWord()
        updatePredictions()
    }

    /// Handle backspace
    func deleteBackward() {
        textDocumentProxy.deleteBackward()
        updateCurrentWord()
        updatePredictions()
        updateAutoCapitalization()
    }

    /// Delete the previous word (for hold-backspace acceleration)
    func deleteWord() {
        guard let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty else {
            return
        }

        // Find the start of the current/previous word
        var charsToDelete = 0
        var foundWordChar = false

        for char in context.reversed() {
            if char.isWhitespace {
                if foundWordChar {
                    break
                }
                charsToDelete += 1
            } else {
                foundWordChar = true
                charsToDelete += 1
            }
        }

        // Delete the word
        for _ in 0..<charsToDelete {
            textDocumentProxy.deleteBackward()
        }

        updateCurrentWord()
        updatePredictions()
        updateAutoCapitalization()
    }

    /// Handle space
    func insertSpace() {
        textDocumentProxy.insertText(" ")
        currentWord = ""

        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        updatePredictions()
        updateAutoCapitalization()
    }

    /// Handle double-tap space - replace space with ". " and uppercase
    func handleDoubleTapSpace() {
        // Delete the space we just inserted from the first tap
        textDocumentProxy.deleteBackward()

        // Insert period and space
        textDocumentProxy.insertText(". ")
        currentWord = ""

        // Enable uppercase for next sentence
        shiftState = .uppercase
        keyboardView.updateShiftState(shiftState)

        updatePredictions()
    }

    /// Handle return key
    func insertReturn() {
        textDocumentProxy.insertText("\n")
        currentWord = ""

        // Reset shift to lowercase before auto-cap decides (caps lock persists)
        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        updatePredictions()
        // Auto-cap will re-enable uppercase for new paragraph if appropriate
        updateAutoCapitalization()
    }

    /// Toggle shift state
    func toggleShift() {
        switch shiftState {
        case .lowercase:
            shiftState = .uppercase
        case .uppercase:
            shiftState = .lowercase
        case .capsLock:
            shiftState = .lowercase
        }
        keyboardView.updateShiftState(shiftState)
        applyPredictionCapitalization()
    }

    /// Enable caps lock (double-tap shift)
    func enableCapsLock() {
        shiftState = .capsLock
        keyboardView.updateShiftState(shiftState)
        applyPredictionCapitalization()
    }

    /// Apply a prediction suggestion
    func applyPrediction(_ prediction: String) {
        // Delete the current partial word
        for _ in 0..<currentWord.count {
            textDocumentProxy.deleteBackward()
        }

        // Prediction is already capitalized as displayed, insert directly
        textDocumentProxy.insertText(prediction)
        textDocumentProxy.insertText(" ")

        currentWord = ""

        // Return to lowercase after uppercase (but not caps lock)
        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        // Force prediction update for new context
        lastCurrentWord = nil
        updatePredictions()
    }

    /// Advance to next input mode (globe key)
    func advanceInputMode() {
        advanceToNextInputMode()
    }
}

// MARK: - KeyboardViewDelegate

extension KeyboardViewController: KeyboardViewDelegate {
    func keyboardView(_ view: KeyboardView, didTapKey key: String) {
        insertCharacter(key)
    }

    func keyboardView(_ view: KeyboardView, didTapSpecialKey key: String) {
        insertSpecialCharacter(key)
    }

    func keyboardViewDidTapBackspace(_ view: KeyboardView) {
        deleteBackward()
    }

    func keyboardViewDidDeleteWord(_ view: KeyboardView) {
        deleteWord()
    }

    func keyboardViewDidTapSpace(_ view: KeyboardView) {
        insertSpace()
    }

    func keyboardViewDidDoubleTapSpace(_ view: KeyboardView) {
        handleDoubleTapSpace()
    }

    func keyboardViewDidTapReturn(_ view: KeyboardView) {
        insertReturn()
    }

    func keyboardViewDidTapShift(_ view: KeyboardView) {
        toggleShift()
    }

    func keyboardViewDidDoubleTapShift(_ view: KeyboardView) {
        enableCapsLock()
    }

    func keyboardView(_ view: KeyboardView, didSelectPrediction prediction: String) {
        applyPrediction(prediction)
    }

    func keyboardViewDidTapGlobe(_ view: KeyboardView) {
        advanceInputMode()
    }
}

// MARK: - ShiftState

enum ShiftState {
    case lowercase
    case uppercase
    case capsLock
}
