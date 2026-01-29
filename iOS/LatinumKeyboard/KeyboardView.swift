import UIKit

/// Protocol for keyboard view delegate
protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, didTapKey key: String)
    func keyboardView(_ view: KeyboardView, didTapSpecialKey key: String)
    func keyboardViewDidTapBackspace(_ view: KeyboardView)
    func keyboardViewDidTapSpace(_ view: KeyboardView)
    func keyboardViewDidTapReturn(_ view: KeyboardView)
    func keyboardViewDidTapShift(_ view: KeyboardView)
    func keyboardViewDidDoubleTapShift(_ view: KeyboardView)
    func keyboardView(_ view: KeyboardView, didSelectPrediction prediction: String)
    func keyboardViewDidTapGlobe(_ view: KeyboardView)
}

/// Main keyboard view containing all keys and prediction bar
class KeyboardView: UIView {

    // MARK: - Constants

    /// Standard iOS keyboard row layouts (QWERTY)
    private let topRow = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    private let middleRow = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
    private let bottomRow = ["z", "x", "c", "v", "b", "n", "m"]

    /// Keys that support long-press for macrons/ligatures
    private let longPressKeys: [String: [String]] = [
        "a": ["\u{0101}", "\u{00E6}"],  // ā, æ
        "e": ["\u{0113}"],               // ē
        "i": ["\u{012B}"],               // ī
        "o": ["\u{014D}", "\u{0153}"],  // ō, œ
        "u": ["\u{016B}"],               // ū
        "y": ["\u{0233}"],               // ȳ
        "A": ["\u{0100}", "\u{00C6}"],  // Ā, Æ
        "E": ["\u{0112}"],               // Ē
        "I": ["\u{012A}"],               // Ī
        "O": ["\u{014C}", "\u{0152}"],  // Ō, Œ
        "U": ["\u{016A}"],               // Ū
        "Y": ["\u{0232}"],               // Ȳ
    ]

    // MARK: - Properties

    weak var delegate: KeyboardViewDelegate?

    private var shiftState: ShiftState = .lowercase
    private var keyButtons: [KeyButton] = []
    private var shiftButton: KeyButton?
    private var lastShiftTapTime: Date?

    // UI Components
    private let predictionBar = PredictionBarView()
    private let keyboardStack = UIStackView()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = UIColor.systemGray5

        setupPredictionBar()
        setupKeyboardLayout()
    }

    private func setupPredictionBar() {
        predictionBar.translatesAutoresizingMaskIntoConstraints = false
        predictionBar.delegate = self
        addSubview(predictionBar)

        NSLayoutConstraint.activate([
            predictionBar.topAnchor.constraint(equalTo: topAnchor),
            predictionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            predictionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            predictionBar.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupKeyboardLayout() {
        keyboardStack.axis = .vertical
        keyboardStack.distribution = .fillEqually
        keyboardStack.spacing = 6
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyboardStack)

        NSLayoutConstraint.activate([
            keyboardStack.topAnchor.constraint(equalTo: predictionBar.bottomAnchor, constant: 4),
            keyboardStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            keyboardStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            keyboardStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        // Create rows
        let row1 = createKeyRow(keys: topRow)
        let row2 = createKeyRow(keys: middleRow, centered: true)
        let row3 = createBottomLetterRow()
        let row4 = createBottomFunctionRow()

        keyboardStack.addArrangedSubview(row1)
        keyboardStack.addArrangedSubview(row2)
        keyboardStack.addArrangedSubview(row3)
        keyboardStack.addArrangedSubview(row4)
    }

    private func createKeyRow(keys: [String], centered: Bool = false) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 6

        // Add centering spacers for middle row
        if centered {
            let leftSpacer = UIView()
            leftSpacer.widthAnchor.constraint(equalToConstant: 15).isActive = true
            row.addArrangedSubview(leftSpacer)
        }

        for key in keys {
            let button = KeyButton(key: key)
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)

            // Setup long press for vowels
            if longPressKeys.keys.contains(key.lowercased()) {
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(keyLongPressed(_:)))
                longPress.minimumPressDuration = 0.3
                button.addGestureRecognizer(longPress)
            }

            keyButtons.append(button)
            row.addArrangedSubview(button)
        }

        if centered {
            let rightSpacer = UIView()
            rightSpacer.widthAnchor.constraint(equalToConstant: 15).isActive = true
            row.addArrangedSubview(rightSpacer)
        }

        return row
    }

    private func createBottomLetterRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.spacing = 6

        // Shift button
        let shift = KeyButton(key: "shift", isSpecial: true)
        shift.setImage(UIImage(systemName: "shift"), for: .normal)
        shift.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
        shift.widthAnchor.constraint(equalToConstant: 42).isActive = true
        shiftButton = shift
        row.addArrangedSubview(shift)

        // Letter keys
        let letterStack = UIStackView()
        letterStack.axis = .horizontal
        letterStack.distribution = .fillEqually
        letterStack.spacing = 6

        for key in bottomRow {
            let button = KeyButton(key: key)
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            keyButtons.append(button)
            letterStack.addArrangedSubview(button)
        }
        row.addArrangedSubview(letterStack)

        // Backspace button
        let backspace = KeyButton(key: "backspace", isSpecial: true)
        backspace.setImage(UIImage(systemName: "delete.left"), for: .normal)
        backspace.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        backspace.widthAnchor.constraint(equalToConstant: 42).isActive = true
        row.addArrangedSubview(backspace)

        return row
    }

    private func createBottomFunctionRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.spacing = 6

        // Globe/keyboard switch
        let globe = KeyButton(key: "globe", isSpecial: true)
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.addTarget(self, action: #selector(globeTapped), for: .touchUpInside)
        globe.widthAnchor.constraint(equalToConstant: 42).isActive = true
        row.addArrangedSubview(globe)

        // Space bar
        let space = KeyButton(key: "space", isSpecial: true)
        space.setTitle("spatium", for: .normal)
        space.titleLabel?.font = .systemFont(ofSize: 14)
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        row.addArrangedSubview(space)

        // Return
        let returnKey = KeyButton(key: "return", isSpecial: true)
        returnKey.setTitle("return", for: .normal)
        returnKey.titleLabel?.font = .systemFont(ofSize: 14)
        returnKey.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        returnKey.widthAnchor.constraint(equalToConstant: 80).isActive = true
        row.addArrangedSubview(returnKey)

        return row
    }

    // MARK: - Actions

    @objc private func keyTapped(_ sender: KeyButton) {
        delegate?.keyboardView(self, didTapKey: sender.keyValue)
    }

    @objc private func keyLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let button = gesture.view as? KeyButton else { return }

        let key = shiftState == .lowercase ? button.keyValue.lowercased() : button.keyValue.uppercased()

        guard let options = longPressKeys[key] ?? longPressKeys[key.lowercased()] else { return }

        // Show popup with options
        showLongPressPopup(for: button, options: options)
    }

    private func showLongPressPopup(for button: KeyButton, options: [String]) {
        let popup = LongPressPopupView(options: options)
        popup.onSelect = { [weak self] selected in
            self?.delegate?.keyboardView(self!, didTapSpecialKey: selected)
        }

        // Position popup above button
        let buttonFrame = button.convert(button.bounds, to: self)
        popup.frame = CGRect(
            x: buttonFrame.midX - 100,
            y: buttonFrame.minY - 50,
            width: 200,
            height: 44
        )

        addSubview(popup)

        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            popup.removeFromSuperview()
        }
    }

    @objc private func shiftTapped() {
        // Check for double-tap
        let now = Date()
        if let lastTap = lastShiftTapTime, now.timeIntervalSince(lastTap) < 0.3 {
            delegate?.keyboardViewDidDoubleTapShift(self)
            lastShiftTapTime = nil
        } else {
            delegate?.keyboardViewDidTapShift(self)
            lastShiftTapTime = now
        }
    }

    @objc private func backspaceTapped() {
        delegate?.keyboardViewDidTapBackspace(self)
    }

    @objc private func spaceTapped() {
        delegate?.keyboardViewDidTapSpace(self)
    }

    @objc private func returnTapped() {
        delegate?.keyboardViewDidTapReturn(self)
    }

    @objc private func globeTapped() {
        delegate?.keyboardViewDidTapGlobe(self)
    }

    // MARK: - Public Methods

    func updateShiftState(_ state: ShiftState) {
        shiftState = state

        // Update key labels
        for button in keyButtons {
            let label: String
            switch state {
            case .lowercase:
                label = button.keyValue.lowercased()
            case .uppercase, .capsLock:
                label = button.keyValue.uppercased()
            }
            button.setTitle(label, for: .normal)
        }

        // Update shift button appearance
        switch state {
        case .lowercase:
            shiftButton?.setImage(UIImage(systemName: "shift"), for: .normal)
            shiftButton?.backgroundColor = UIColor.systemGray3
        case .uppercase:
            shiftButton?.setImage(UIImage(systemName: "shift.fill"), for: .normal)
            shiftButton?.backgroundColor = UIColor.white
        case .capsLock:
            shiftButton?.setImage(UIImage(systemName: "capslock.fill"), for: .normal)
            shiftButton?.backgroundColor = UIColor.white
        }
    }

    func updatePredictions(_ predictions: [String]) {
        predictionBar.updatePredictions(predictions)
    }
}

// MARK: - PredictionBarViewDelegate

extension KeyboardView: PredictionBarViewDelegate {
    func predictionBarView(_ view: PredictionBarView, didSelectPrediction prediction: String) {
        delegate?.keyboardView(self, didSelectPrediction: prediction)
    }
}
