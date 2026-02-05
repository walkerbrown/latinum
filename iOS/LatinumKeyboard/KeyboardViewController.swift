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

    // Prediction scheduling: debounce rapid keystrokes and discard stale results
    private var predictionDebounceTimer: Timer?
    private var predictionGeneration: UInt = 0
    private let predictionDebounceInterval: TimeInterval = 0.15

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
        updateKeyboardConfiguration()
        updateAutoCapitalization()
        schedulePredictionUpdate()
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
            // Data is now available — trigger an immediate prediction refresh
            self?.schedulePredictionUpdate()
        }
        predictionEngine.load()
    }

    // MARK: - Text Input

    override func textDidChange(_ textInput: UITextInput?) {
        // Update keyboard configuration (type, globe visibility) when context changes
        updateKeyboardConfiguration()

        // If the user has selected/highlighted a word, use it as the prediction prefix
        if let selected = textDocumentProxy.selectedText,
           !selected.trimmingCharacters(in: .whitespaces).isEmpty {
            currentWord = selected.trimmingCharacters(in: .whitespaces)
            hasSelection = true
            schedulePredictionUpdate()
            return
        }

        hasSelection = false
        // Update context when text changes externally
        updateCurrentWord()
        schedulePredictionUpdate()
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

    // MARK: - Prediction Scheduling

    /// Schedule a debounced prediction update.
    /// Resets the debounce timer on each call so rapid keystrokes coalesce into a
    /// single inference request once typing pauses for `predictionDebounceInterval`.
    /// Any in-flight prediction whose generation is stale will be discarded on arrival.
    private func schedulePredictionUpdate() {
        predictionDebounceTimer?.invalidate()
        predictionDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: predictionDebounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.performPredictionUpdate()
        }
    }

    /// Dispatch prediction work to the inference queue.
    private func performPredictionUpdate() {
        predictionGeneration &+= 1
        let generation = predictionGeneration

        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let word = currentWord

        predictionEngine.predictAsync(context: context, currentWord: word) { [weak self] predictions in
            guard let self = self else { return }
            // Discard if a newer request has been issued since this one was dispatched
            guard generation == self.predictionGeneration else { return }

            self.rawPredictions = predictions
            self.applyPredictionCapitalization()
        }
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
        schedulePredictionUpdate()
    }

    /// Insert a special character (macron, ligature)
    func insertSpecialCharacter(_ char: String) {
        textDocumentProxy.insertText(char)

        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        updateCurrentWord()
        schedulePredictionUpdate()
    }

    /// Handle backspace
    func deleteBackward() {
        textDocumentProxy.deleteBackward()
        updateCurrentWord()
        schedulePredictionUpdate()
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
        schedulePredictionUpdate()
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

        schedulePredictionUpdate()
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

        schedulePredictionUpdate()
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

        schedulePredictionUpdate()
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
        // When there's a selection, delete the selected text first
        if hasSelection, let selected = textDocumentProxy.selectedText {
            for _ in 0..<selected.count {
                textDocumentProxy.deleteBackward()
            }
            hasSelection = false
        } else {
            // Delete the current partial word
            for _ in 0..<currentWord.count {
                textDocumentProxy.deleteBackward()
            }
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

        schedulePredictionUpdate()
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
