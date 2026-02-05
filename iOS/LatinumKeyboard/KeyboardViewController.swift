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

    private var keyboardView: KeyboardView!
    private var predictionEngine: PredictionEngine!
    private let haptics = KeyboardHaptics()
    private let audio = KeyboardAudio()
    private var shiftState: ShiftState = .lowercase
    private var currentWord: String = ""
    private var rawPredictions: [String] = []
    private var lastKeyboardType: UIKeyboardType?
    private var hasSelection: Bool = false

    /// Timestamp of last self-triggered text modification, used to
    /// skip textDidChange callbacks caused by our own insertions.
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
        haptics.prepare()
        audio.prepare()
        haptics.isEnabled = KeyboardSettings.hapticEnabled
        audio.isEnabled = KeyboardSettings.soundEnabled
        keyboardView.haptics = haptics
        keyboardView.audio = audio
        updateAutoCapitalization()
        performPredictionUpdate()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // updateKeyboardConfiguration may trigger rebuildKeyboard (e.g., globe
        // key visibility change), which clears prediction labels.
        updateKeyboardConfiguration()
        applyPredictionCapitalization()
    }

    // MARK: - Keyboard Configuration

    private func updateKeyboardConfiguration() {
        keyboardView.updateGlobeKeyVisibility(needsInputModeSwitchKey)

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
        // Skip callbacks from our own text modifications (50ms window).
        // Must run BEFORE updateKeyboardConfiguration(), which can trigger
        // rebuildKeyboard() and clear prediction labels.
        if CFAbsoluteTimeGetCurrent() - lastSelfModifiedTime < 0.05 {
            return
        }

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

    private func performPredictionUpdate() {
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let word = currentWord

        rawPredictions = predictionEngine.predict(context: context, currentWord: word)
        applyPredictionCapitalization()
    }

    private func applyPredictionCapitalization() {
        let capitalizedPredictions = rawPredictions.map { applyCapitalization($0) }
        keyboardView.updatePredictions(capitalizedPredictions)
    }

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

    private func updateAutoCapitalization() {
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

    func insertCharacter(_ char: String) {
        let charToInsert: String
        switch shiftState {
        case .lowercase:
            charToInsert = char.lowercased()
        case .uppercase, .capsLock:
            charToInsert = char.uppercased()
        }

        lastSelfModifiedTime = CFAbsoluteTimeGetCurrent()
        textDocumentProxy.insertText(charToInsert)

        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        currentWord += charToInsert
        performPredictionUpdate()
    }

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

    /// Delete one character backward. Returns true if content was deleted.
    @discardableResult
    func deleteBackward() -> Bool {
        // Check if there's content to delete
        let hasContent = textDocumentProxy.documentContextBeforeInput?.isEmpty == false

        guard hasContent else { return false }

        lastSelfModifiedTime = CFAbsoluteTimeGetCurrent()
        textDocumentProxy.deleteBackward()

        if !currentWord.isEmpty {
            currentWord = String(currentWord.dropLast())
        } else {
            updateCurrentWord()
        }

        performPredictionUpdate()
        updateAutoCapitalization()
        return true
    }

    /// Delete one word backward. Returns true if content was deleted.
    @discardableResult
    func deleteWord() -> Bool {
        guard let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty else {
            return false
        }

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
        return true
    }

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

    func handleDoubleTapSpace() {
        lastSelfModifiedTime = CFAbsoluteTimeGetCurrent()
        textDocumentProxy.deleteBackward()
        textDocumentProxy.insertText(". ")
        currentWord = ""

        shiftState = .uppercase
        keyboardView.updateShiftState(shiftState)

        performPredictionUpdate()
    }

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

    func enableCapsLock() {
        shiftState = .capsLock
        keyboardView.updateShiftState(shiftState)
        applyPredictionCapitalization()
    }

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

        // Record the space insertion so a subsequent space tap triggers
        // double-tap behavior (replacing " " with ". ").
        keyboardView.recordSpaceTap()

        currentWord = ""

        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        performPredictionUpdate()
    }

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

    @discardableResult
    func keyboardViewDidTapBackspace(_ view: KeyboardView) -> Bool {
        deleteBackward()
    }

    @discardableResult
    func keyboardViewDidDeleteWord(_ view: KeyboardView) -> Bool {
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
