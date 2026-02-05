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

    /// Cached raw predictions (before capitalization)
    private var rawPredictions: [String] = []

    /// Cached keyboard type to detect changes
    private var lastKeyboardType: UIKeyboardType?

    /// Whether text is currently selected (for word-highlight prediction)
    private var hasSelection: Bool = false

    /// Timestamp of last self-triggered text modification.
    /// Used to ignore textDidChange callbacks from our own insertions/deletions,
    /// since the proxy may report stale context in those callbacks.
    private var lastSelfModifiedTime: CFAbsoluteTime = 0


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
        KeyboardFeedback.shared.prepare()
        updateAutoCapitalization()
        performPredictionUpdate()
        applyPredictionCapitalization()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Defer needsInputModeSwitchKey until host connection is established.
        // updateKeyboardConfiguration may trigger rebuildKeyboard (e.g., globe
        // key visibility change), which clears prediction labels.  Re-apply
        // predictions afterward so the bar isn't blank on first appearance.
        updateKeyboardConfiguration()
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
        predictionEngine.onDataLoaded = { [weak self] in
            self?.performPredictionUpdate()
        }
        predictionEngine.load()
    }

    // MARK: - Text Input

    override func textDidChange(_ textInput: UITextInput?) {
        // Ignore callbacks triggered by our own text modifications.
        // The proxy often reports stale context in these callbacks, and we already
        // set currentWord and fired predictions in the originating method.
        // Use a 50ms window to catch all callbacks from a single modification
        // (textDidChange can fire multiple times per insertText call).
        //
        // IMPORTANT: updateKeyboardConfiguration() must run AFTER this guard
        // because it can trigger rebuildKeyboard() (e.g., globe key visibility
        // change), which clears the prediction labels. If it ran before the
        // guard, predictions set by insertCharacter() would be wiped and the
        // early return would prevent them from being re-applied.
        if CFAbsoluteTimeGetCurrent() - lastSelfModifiedTime < 0.05 {
            return
        }

        // External text change (cursor move, paste, autocorrect, etc.)
        updateKeyboardConfiguration()

        if let selected = textDocumentProxy.selectedText,
           !selected.trimmingCharacters(in: .whitespaces).isEmpty {
            currentWord = selected.trimmingCharacters(in: .whitespaces)
            hasSelection = true
            performPredictionUpdate()
            return
        }

        hasSelection = false
        updateCurrentWord()
        performPredictionUpdate()
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

    // MARK: - Prediction

    /// Generate and display predictions synchronously.
    private func performPredictionUpdate() {
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let word = currentWord

        rawPredictions = predictionEngine.predict(context: context, currentWord: word)
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

        lastSelfModifiedTime = CFAbsoluteTimeGetCurrent()
        textDocumentProxy.insertText(charToInsert)

        // Return to lowercase after single uppercase
        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        currentWord += charToInsert
        performPredictionUpdate()
    }

    /// Insert a special character (macron, ligature)
    func insertSpecialCharacter(_ char: String) {
        lastSelfModifiedTime = CFAbsoluteTimeGetCurrent()
        textDocumentProxy.insertText(char)

        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        currentWord += char
        performPredictionUpdate()
    }

    /// Handle backspace
    func deleteBackward() {
        lastSelfModifiedTime = CFAbsoluteTimeGetCurrent()
        textDocumentProxy.deleteBackward()

        if !currentWord.isEmpty {
            currentWord = String(currentWord.dropLast())
        } else {
            updateCurrentWord()
        }

        performPredictionUpdate()
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

        lastSelfModifiedTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<charsToDelete {
            textDocumentProxy.deleteBackward()
        }

        currentWord = ""
        performPredictionUpdate()
        updateAutoCapitalization()
    }

    /// Handle space
    func insertSpace() {
        lastSelfModifiedTime = CFAbsoluteTimeGetCurrent()
        textDocumentProxy.insertText(" ")
        currentWord = ""

        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        performPredictionUpdate()
        updateAutoCapitalization()
    }

    /// Handle double-tap space - replace space with ". " and uppercase
    func handleDoubleTapSpace() {
        lastSelfModifiedTime = CFAbsoluteTimeGetCurrent()
        textDocumentProxy.deleteBackward()
        textDocumentProxy.insertText(". ")
        currentWord = ""

        shiftState = .uppercase
        keyboardView.updateShiftState(shiftState)

        performPredictionUpdate()
    }

    /// Handle return key
    func insertReturn() {
        lastSelfModifiedTime = CFAbsoluteTimeGetCurrent()
        textDocumentProxy.insertText("\n")
        currentWord = ""

        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        performPredictionUpdate()
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
        lastSelfModifiedTime = CFAbsoluteTimeGetCurrent()

        if hasSelection, let selected = textDocumentProxy.selectedText {
            for _ in 0..<selected.count {
                textDocumentProxy.deleteBackward()
            }
            hasSelection = false
        } else {
            for _ in 0..<currentWord.count {
                textDocumentProxy.deleteBackward()
            }
        }

        textDocumentProxy.insertText(prediction)
        textDocumentProxy.insertText(" ")

        currentWord = ""

        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        performPredictionUpdate()
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
