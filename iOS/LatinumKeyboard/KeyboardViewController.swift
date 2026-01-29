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

    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboard()
        setupPredictionEngine()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePredictions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        keyboardView.frame = view.bounds
    }

    // MARK: - Setup

    private func setupKeyboard() {
        keyboardView = KeyboardView(frame: view.bounds)
        keyboardView.delegate = self
        keyboardView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(keyboardView)
    }

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
        keyboardView.updatePredictions(predictions)
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
    }

    /// Enable caps lock (double-tap shift)
    func enableCapsLock() {
        shiftState = .capsLock
        keyboardView.updateShiftState(shiftState)
    }

    /// Apply a prediction suggestion
    func applyPrediction(_ prediction: String) {
        // Delete the current partial word
        for _ in 0..<currentWord.count {
            textDocumentProxy.deleteBackward()
        }

        // Insert the prediction
        textDocumentProxy.insertText(prediction)

        // Add space after word
        textDocumentProxy.insertText(" ")

        currentWord = ""

        if shiftState == .uppercase {
            shiftState = .lowercase
            keyboardView.updateShiftState(shiftState)
        }

        updatePredictions()
    }

    /// Switch to next keyboard
    func switchKeyboard() {
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

    func keyboardViewDidTapSpace(_ view: KeyboardView) {
        insertSpace()
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
        switchKeyboard()
    }
}

// MARK: - ShiftState

enum ShiftState {
    case lowercase
    case uppercase
    case capsLock
}
