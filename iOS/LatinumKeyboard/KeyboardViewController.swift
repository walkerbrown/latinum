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
        updateAutoCapitalization()
        updatePredictions()
    }

    // MARK: - Setup

    private func setupPredictionEngine() {
        predictionEngine = PredictionEngine()
        predictionEngine.load()
    }

    // MARK: - Text Input

    override func textWillChange(_ textInput: UITextInput?) {
        // Called when the text is about to change
    }

    override func textDidChange(_ textInput: UITextInput?) {
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

    /// Update prediction suggestions based on current context
    private func updatePredictions() {
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let predictions = predictionEngine.predict(context: context, currentWord: currentWord)
        // Apply capitalization based on current shift state
        let capitalizedPredictions = predictions.map { applyCapitalization($0) }
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

    /// Check if we should auto-capitalize (empty field or after ". ")
    private func updateAutoCapitalization() {
        let context = textDocumentProxy.documentContextBeforeInput ?? ""

        // Capitalize if empty or ends with ". "
        if context.isEmpty || context.hasSuffix(". ") {
            if shiftState == .lowercase {
                shiftState = .uppercase
                keyboardView.updateShiftState(shiftState)
            }
        }
    }

    /// Check if we should capitalize after current action
    private func shouldAutoCapitalize() -> Bool {
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        return context.isEmpty || context.hasSuffix(". ")
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

        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        updatePredictions()
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
        updatePredictions()
    }

    /// Enable caps lock (double-tap shift)
    func enableCapsLock() {
        shiftState = .capsLock
        keyboardView.updateShiftState(shiftState)
        updatePredictions()
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
