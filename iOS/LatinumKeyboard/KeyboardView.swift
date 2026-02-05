import UIKit

/// Protocol for keyboard view delegate
protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, didTapKey key: String)
    func keyboardView(_ view: KeyboardView, didTapSpecialKey key: String)
    func keyboardViewDidTapBackspace(_ view: KeyboardView)
    func keyboardViewDidDeleteWord(_ view: KeyboardView)
    func keyboardViewDidTapSpace(_ view: KeyboardView)
    func keyboardViewDidDoubleTapSpace(_ view: KeyboardView)
    func keyboardViewDidTapReturn(_ view: KeyboardView)
    func keyboardViewDidTapShift(_ view: KeyboardView)
    func keyboardViewDidDoubleTapShift(_ view: KeyboardView)
    func keyboardView(_ view: KeyboardView, didSelectPrediction prediction: String)
    func keyboardViewDidTapGlobe(_ view: KeyboardView)
}

/// Keyboard input mode
enum KeyboardMode {
    case letters
    case numbers      // 123 - numbers and primary symbols
    case symbols      // #+= - additional symbols
}

/// Main keyboard view containing all keys and prediction bar
class KeyboardView: UIView {

    // MARK: - Constants

    /// Standard iOS keyboard row layouts (QWERTY)
    private let letterRow1 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    private let letterRow2 = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
    private let letterRow3 = ["z", "x", "c", "v", "b", "n", "m"]

    /// Numbers and primary symbols (US English layout)
    private let numberRow1 = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private let numberRow2 = ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
    private let numberRow3 = [".", ",", "?", "!", "'"]

    /// Additional symbols
    private let symbolRow1 = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
    private let symbolRow2 = ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]
    private let symbolRow3 = [".", ",", "?", "!", "'"]

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
    private var keyboardMode: KeyboardMode = .letters
    private var keyButtons: [KeyButton] = []
    private var shiftButton: KeyButton?
    private var modeButton: KeyButton?
    private var symbolToggleButton: KeyButton?
    private var lastShiftTapTime: Date?

    // Space bar animation and double-tap
    private var spaceButton: KeyButton?
    private var spaceLabel: UILabel?
    private var langLabel: UILabel?
    private var lastSpaceTapTime: Date?

    // Long press handling for letters
    private var activeLongPressPopup: LongPressPopupView?
    private var longPressButton: KeyButton?

    // Backspace repeat handling
    private var backspaceTimer: Timer?
    private var backspaceDeleteCount: Int = 0
    private let charDeleteThreshold: Int = 5  // Switch to word deletion after this many chars

    // UI Components
    private let keyboardStack = UIStackView()

    // Prediction bar components (integrated into keyboardStack)
    private var predictionLabels: [UILabel] = []
    private var predictionSeparators: [UIView] = []

    // Flexible spacers between rows
    private var rowSpacers: [UIView] = []
    private var predictionSpacer: UIView?

    // Layout constants
    private let keySpacing: CGFloat = 6
    private let wideKeyWidth: CGFloat = 50
    private let row3ExtraSpacing: CGFloat = 14  // Extra space between shift-z and m-backspace

    // Track orientation for rebuilding
    private var isLandscape: Bool {
        UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }
    private var lastIsLandscape: Bool?

    private var keyHeight: CGFloat {
        isLandscape ? 28 : 46
    }

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // MARK: - Layout Constants

    private let predictionRowHeight: CGFloat = 28
    private let topEdgePadding: CGFloat = 9  // Hand-tuned to accomodate capital accented pop-up keys
    private let bottomEdgePadding: CGFloat = 4  // Hand-tuned to align with system keyboards

    // MARK: - Setup

    private func setupView() {
        backgroundColor = .clear
        setupKeyboardStack()
        rebuildKeyboard()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Rebuild keyboard only when orientation actually changes
        if lastIsLandscape != isLandscape {
            lastIsLandscape = isLandscape
            rebuildKeyboard()
        }
    }

    private func setupKeyboardStack() {
        keyboardStack.axis = .vertical
        keyboardStack.distribution = .fill
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyboardStack)

        NSLayoutConstraint.activate([
            keyboardStack.topAnchor.constraint(equalTo: topAnchor, constant: topEdgePadding),
            keyboardStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomEdgePadding),
            keyboardStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: keySpacing + 1),
            keyboardStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(keySpacing + 1)),
        ])
    }

    /// Minimum height for spacers between rows
    private let minSpacerHeight: CGFloat = 10

    /// Creates a flexible spacer view for use between keyboard rows
    private func createSpacer() -> UIView {
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: minSpacerHeight).isActive = true
        return spacer
    }

    private func rebuildKeyboard() {
        // Clear existing views
        for view in keyboardStack.arrangedSubviews {
            keyboardStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        keyButtons.removeAll()
        shiftButton = nil
        modeButton = nil
        symbolToggleButton = nil
        spaceButton = nil
        spaceLabel = nil
        langLabel = nil
        predictionLabels.removeAll()
        predictionSeparators.removeAll()
        rowSpacers.removeAll()
        predictionSpacer = nil

        // Build prediction row (shared across all keyboard modes)
        let predictionRow = createPredictionRow()
        predictionRow.heightAnchor.constraint(equalToConstant: predictionRowHeight).isActive = true
        keyboardStack.addArrangedSubview(predictionRow)

        // Add spacer below prediction row (will be 2x height of other spacers)
        let belowPredictionSpacer = createSpacer()
        keyboardStack.addArrangedSubview(belowPredictionSpacer)
        predictionSpacer = belowPredictionSpacer

        switch keyboardMode {
        case .letters:
            buildLetterKeyboard()
        case .numbers:
            buildNumberKeyboard()
        case .symbols:
            buildSymbolKeyboard()
        }

        // Constrain all regular spacers to equal height
        if let firstSpacer = rowSpacers.first {
            for spacer in rowSpacers.dropFirst() {
                spacer.heightAnchor.constraint(equalTo: firstSpacer.heightAnchor).isActive = true
            }
            // Prediction spacer is 2x the height of regular spacers
            predictionSpacer?.heightAnchor.constraint(equalTo: firstSpacer.heightAnchor, multiplier: 2).isActive = true
        }
    }

    // MARK: - Prediction Row

    private func createPredictionRow() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.clear.withAlphaComponent(0.01)

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stackView)

        // Center stack view vertically, pin to sides
        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 25),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Create three tappable areas with centered labels
        for i in 0..<3 {
            let tapContainer = UIView()
            tapContainer.tag = i
            tapContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(predictionTapped(_:))))

            let label = UILabel()
            label.font = .systemFont(ofSize: 19)
            label.textColor = .label
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            tapContainer.addSubview(label)

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: tapContainer.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: tapContainer.centerYAnchor),
            ])

            stackView.addArrangedSubview(tapContainer)
            predictionLabels.append(label)
        }

        // Add vertical separators between predictions
        for i in 0..<2 {
            let separator = UIView()
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.isUserInteractionEnabled = false
            separator.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 1.0, alpha: 0.15)
                    : UIColor(white: 0.0, alpha: 0.12)
            }
            container.addSubview(separator)
            predictionSeparators.append(separator)

            NSLayoutConstraint.activate([
                separator.trailingAnchor.constraint(equalTo: stackView.arrangedSubviews[i].trailingAnchor),
                separator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                separator.widthAnchor.constraint(equalToConstant: 1),
                separator.heightAnchor.constraint(equalToConstant: 22),
            ])
        }

        return container
    }

    @objc private func predictionTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag,
              index < predictionLabels.count,
              let text = predictionLabels[index].text,
              !text.isEmpty else { return }
        delegate?.keyboardView(self, didSelectPrediction: text)
    }

    // MARK: - Letter Keyboard

    private func buildLetterKeyboard() {
        let row1 = createUniformKeyRow(keys: letterRow1)
        let row2 = createCenteredKeyRow(keys: letterRow2)
        let row3 = createBottomLetterRow()
        let row4 = createBottomFunctionRow()

        let rows = [row1, row2, row3, row4]
        for (index, row) in rows.enumerated() {
            row.heightAnchor.constraint(equalToConstant: keyHeight).isActive = true
            keyboardStack.addArrangedSubview(row)

            // Add spacer after each row except the last
            if index < rows.count - 1 {
                let spacer = createSpacer()
                keyboardStack.addArrangedSubview(spacer)
                rowSpacers.append(spacer)
            }
        }

        updateShiftState(shiftState)

        // Temporarily highlight, as with system keyboards
        self.spaceButton?.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.35, alpha: 1.0)
            : UIColor(white: 1.0, alpha: 1.0)
        }
        // Trigger space bar animation after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.animateSpaceBar()
        }
    }

    private func createUniformKeyRow(keys: [String]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = keySpacing

        for key in keys {
            let button = KeyButton(key: key)
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)

            if longPressKeys.keys.contains(key.lowercased()) {
                setupLongPress(for: button)
            }

            keyButtons.append(button)
            row.addArrangedSubview(button)
        }

        return row
    }

    private func createCenteredKeyRow(keys: [String]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.spacing = keySpacing

        // Calculate centering spacer width based on difference in key count
        // Row 1 has 10 keys, Row 2 has 9 keys, so we need half a key width on each side
        let spacerWidth: CGFloat = 18

        let leftSpacer = UIView()
        leftSpacer.widthAnchor.constraint(equalToConstant: spacerWidth).isActive = true
        row.addArrangedSubview(leftSpacer)

        let keyStack = UIStackView()
        keyStack.axis = .horizontal
        keyStack.distribution = .fillEqually
        keyStack.spacing = keySpacing

        for key in keys {
            let button = KeyButton(key: key)
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)

            if longPressKeys.keys.contains(key.lowercased()) {
                setupLongPress(for: button)
            }

            keyButtons.append(button)
            keyStack.addArrangedSubview(button)
        }

        row.addArrangedSubview(keyStack)

        let rightSpacer = UIView()
        rightSpacer.widthAnchor.constraint(equalToConstant: spacerWidth).isActive = true
        row.addArrangedSubview(rightSpacer)

        return row
    }

    private func createBottomLetterRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.spacing = keySpacing

        // Shift button
        let shift = KeyButton(key: "shift")
        shift.setImage(UIImage(systemName: "shift"), for: .normal)
        shift.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
        shift.widthAnchor.constraint(equalToConstant: wideKeyWidth).isActive = true
        shiftButton = shift
        row.addArrangedSubview(shift)

        // Extra spacer between shift and z
        let leftSpacer = UIView()
        leftSpacer.widthAnchor.constraint(equalToConstant: row3ExtraSpacing - keySpacing).isActive = true
        row.addArrangedSubview(leftSpacer)

        // Letter keys - uniform width
        let letterStack = UIStackView()
        letterStack.axis = .horizontal
        letterStack.distribution = .fillEqually
        letterStack.spacing = keySpacing

        for key in letterRow3 {
            let button = KeyButton(key: key)
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            keyButtons.append(button)
            letterStack.addArrangedSubview(button)
        }
        row.addArrangedSubview(letterStack)

        // Extra spacer between m and backspace
        let rightSpacer = UIView()
        rightSpacer.widthAnchor.constraint(equalToConstant: row3ExtraSpacing - keySpacing).isActive = true
        row.addArrangedSubview(rightSpacer)

        // Backspace button with long press for repeat delete
        let backspace = KeyButton(key: "backspace")
        let backspaceConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        backspace.setImage(UIImage(systemName: "delete.left", withConfiguration: backspaceConfig), for: .normal)
        backspace.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        setupBackspaceLongPress(for: backspace)
        backspace.widthAnchor.constraint(equalToConstant: wideKeyWidth).isActive = true
        row.addArrangedSubview(backspace)

        return row
    }

    private func createBottomFunctionRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.spacing = keySpacing

        // 123 button
        let mode = KeyButton(key: "123")
        mode.setTitle("123", for: .normal)
        mode.titleLabel?.font = .systemFont(ofSize: 18, weight: .regular)
        mode.addTarget(self, action: #selector(modeTapped), for: .touchUpInside)
        mode.widthAnchor.constraint(equalToConstant: 48).isActive = true
        modeButton = mode
        row.addArrangedSubview(mode)

        // Globe button for input mode switching (required for App Store)
        let globeKey = KeyButton(key: "globe")
        globeKey.setImage(UIImage(systemName: "globe"), for: .normal)
        globeKey.addTarget(self, action: #selector(globeTapped), for: .touchUpInside)
        globeKey.widthAnchor.constraint(equalToConstant: 48).isActive = true
        row.addArrangedSubview(globeKey)

        // Space bar with "Lingua Latina" text that fades
        let space = createSpaceButton()
        row.addArrangedSubview(space)

        // Return - slightly wider
        let returnKey = KeyButton(key: "return")
        let returnConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        returnKey.setImage(UIImage(systemName: "return.left", withConfiguration: returnConfig), for: .normal)
        returnKey.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        returnKey.widthAnchor.constraint(equalToConstant: 100).isActive = true
        row.addArrangedSubview(returnKey)

        return row
    }

    private func createSpaceButton() -> UIButton {
        let space = KeyButton(key: "space")
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        spaceButton = space

        // "Lingua Latina" label in center (will fade out after 1 second)
        let centerLabel = UILabel()
        centerLabel.text = "Lingua Latina"
        centerLabel.font = .systemFont(ofSize: 16, weight: .medium)
        // Adaptive color: black in light mode, white in dark mode
        centerLabel.textColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .black
        }
        centerLabel.textAlignment = .center
        centerLabel.translatesAutoresizingMaskIntoConstraints = false
        space.addSubview(centerLabel)
        spaceLabel = centerLabel

        NSLayoutConstraint.activate([
            centerLabel.centerXAnchor.constraint(equalTo: space.centerXAnchor),
            centerLabel.centerYAnchor.constraint(equalTo: space.centerYAnchor),
        ])

        // "LA" label in lower right corner - immediately visible
        let langIndicator = UILabel()
        langIndicator.text = "LA"
        langIndicator.font = .systemFont(ofSize: 9, weight: .medium)
        // Lighter in light mode, secondary in dark mode
        langIndicator.textColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .secondaryLabel
                : .tertiaryLabel
        }
        langIndicator.transform = CGAffineTransform(scaleX: 1.0, y: 1.5)
        langIndicator.translatesAutoresizingMaskIntoConstraints = false
        space.addSubview(langIndicator)
        langLabel = langIndicator

        NSLayoutConstraint.activate([
            langIndicator.trailingAnchor.constraint(equalTo: space.trailingAnchor, constant: -6),
            langIndicator.bottomAnchor.constraint(equalTo: space.bottomAnchor, constant: -6),
        ])

        return space
    }

    private func animateSpaceBar() {
        guard let spaceLabel = spaceLabel else { return }

        // Fade out "Lingua Latina" - LA is already visible
        UIView.animate(withDuration: 0.4) {
            spaceLabel.alpha = 0
            self.spaceButton?.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.25, alpha: 1.0)
                : UIColor.white
            }
        }
    }

    // MARK: - Number Keyboard

    private func buildNumberKeyboard() {
        let row1 = createSymbolRow(keys: numberRow1)
        let row2 = createSymbolRow(keys: numberRow2)
        let row3 = createNumberBottomRow(keys: numberRow3)
        let row4 = createNumberFunctionRow()

        let rows = [row1, row2, row3, row4]
        for (index, row) in rows.enumerated() {
            row.heightAnchor.constraint(equalToConstant: keyHeight).isActive = true
            keyboardStack.addArrangedSubview(row)

            if index < rows.count - 1 {
                let spacer = createSpacer()
                keyboardStack.addArrangedSubview(spacer)
                rowSpacers.append(spacer)
            }
        }
    }

    private func buildSymbolKeyboard() {
        let row1 = createSymbolRow(keys: symbolRow1)
        let row2 = createSymbolRow(keys: symbolRow2)
        let row3 = createNumberBottomRow(keys: symbolRow3)
        let row4 = createNumberFunctionRow()

        let rows = [row1, row2, row3, row4]
        for (index, row) in rows.enumerated() {
            row.heightAnchor.constraint(equalToConstant: keyHeight).isActive = true
            keyboardStack.addArrangedSubview(row)

            if index < rows.count - 1 {
                let spacer = createSpacer()
                keyboardStack.addArrangedSubview(spacer)
                rowSpacers.append(spacer)
            }
        }
    }

    private func createSymbolRow(keys: [String]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = keySpacing

        for key in keys {
            let button = KeyButton(key: key)
            button.addTarget(self, action: #selector(symbolKeyTapped(_:)), for: .touchUpInside)
            button.titleLabel?.font = .systemFont(ofSize: 21)
            keyButtons.append(button)
            row.addArrangedSubview(button)
        }

        return row
    }

    private func createNumberBottomRow(keys: [String]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.spacing = keySpacing

        // Symbol toggle button
        let toggle = KeyButton(key: "symbolToggle")
        toggle.setTitle(keyboardMode == .numbers ? "#+=": "123", for: .normal)
        toggle.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        toggle.addTarget(self, action: #selector(symbolToggleTapped), for: .touchUpInside)
        toggle.widthAnchor.constraint(equalToConstant: wideKeyWidth).isActive = true
        symbolToggleButton = toggle
        row.addArrangedSubview(toggle)

        // Extra spacer
        let leftSpacer = UIView()
        leftSpacer.widthAnchor.constraint(equalToConstant: row3ExtraSpacing - keySpacing).isActive = true
        row.addArrangedSubview(leftSpacer)

        // Symbol keys
        let symbolStack = UIStackView()
        symbolStack.axis = .horizontal
        symbolStack.distribution = .fillEqually
        symbolStack.spacing = keySpacing

        for key in keys {
            let button = KeyButton(key: key)
            button.addTarget(self, action: #selector(symbolKeyTapped(_:)), for: .touchUpInside)
            keyButtons.append(button)
            symbolStack.addArrangedSubview(button)
        }
        row.addArrangedSubview(symbolStack)

        // Extra spacer
        let rightSpacer = UIView()
        rightSpacer.widthAnchor.constraint(equalToConstant: row3ExtraSpacing - keySpacing).isActive = true
        row.addArrangedSubview(rightSpacer)

        // Backspace button with long press for repeat delete
        let backspace = KeyButton(key: "backspace")
        let backspaceConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        backspace.setImage(UIImage(systemName: "delete.left", withConfiguration: backspaceConfig), for: .normal)
        backspace.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        setupBackspaceLongPress(for: backspace)
        backspace.widthAnchor.constraint(equalToConstant: wideKeyWidth).isActive = true
        row.addArrangedSubview(backspace)

        return row
    }

    private func createNumberFunctionRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.spacing = keySpacing

        // ABC button
        let mode = KeyButton(key: "ABC")
        mode.setTitle("ABC", for: .normal)
        mode.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        mode.addTarget(self, action: #selector(modeTapped), for: .touchUpInside)
        mode.widthAnchor.constraint(equalToConstant: 48).isActive = true
        modeButton = mode
        row.addArrangedSubview(mode)

        // Globe button for input mode switching (required for App Store)
        let globeKey = KeyButton(key: "globe")
        globeKey.setImage(UIImage(systemName: "globe"), for: .normal)
        globeKey.addTarget(self, action: #selector(globeTapped), for: .touchUpInside)
        globeKey.widthAnchor.constraint(equalToConstant: 48).isActive = true
        row.addArrangedSubview(globeKey)

        // Space bar (simpler version for number mode)
        let space = KeyButton(key: "space")
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)

        // "LA" label
        let langIndicator = UILabel()
        langIndicator.text = "LA"
        langIndicator.font = .systemFont(ofSize: 9, weight: .medium)
        langIndicator.textColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .secondaryLabel
                : .tertiaryLabel
        }
        langIndicator.transform = CGAffineTransform(scaleX: 1.0, y: 1.5)
        langIndicator.translatesAutoresizingMaskIntoConstraints = false
        space.addSubview(langIndicator)

        NSLayoutConstraint.activate([
            langIndicator.trailingAnchor.constraint(equalTo: space.trailingAnchor, constant: -6),
            langIndicator.bottomAnchor.constraint(equalTo: space.bottomAnchor, constant: -6),
        ])

        row.addArrangedSubview(space)

        // Return key
        let returnKey = KeyButton(key: "return")
        let returnConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        returnKey.setImage(UIImage(systemName: "return.left", withConfiguration: returnConfig), for: .normal)
        returnKey.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        returnKey.widthAnchor.constraint(equalToConstant: 100).isActive = true
        row.addArrangedSubview(returnKey)

        return row
    }

    // MARK: - Long Press Handling

    private func setupLongPress(for button: KeyButton) {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        button.addGestureRecognizer(longPress)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? KeyButton else { return }

        switch gesture.state {
        case .began:
            let key = shiftState == .lowercase ? button.keyValue.lowercased() : button.keyValue.uppercased()
            guard let options = longPressKeys[key] ?? longPressKeys[key.lowercased()] else { return }

            longPressButton = button
            showLongPressPopup(for: button, options: options)

        case .changed:
            guard let popup = activeLongPressPopup else { return }
            let location = gesture.location(in: self)
            popup.updateSelection(at: location)

        case .ended:
            guard let popup = activeLongPressPopup else { return }
            if let selected = popup.completeSelection() {
                delegate?.keyboardView(self, didTapSpecialKey: selected)
            }
            dismissLongPressPopup()

        case .cancelled, .failed:
            dismissLongPressPopup()

        default:
            break
        }
    }

    private func showLongPressPopup(for button: KeyButton, options: [String]) {
        let popup = LongPressPopupView(options: options)

        let popupWidth = LongPressPopupView.popupWidth(for: options.count)
        let popupHeight = LongPressPopupView.popupHeight()

        let buttonFrame = button.convert(button.bounds, to: self)
        let verticalOffset: CGFloat = 4
        let horizontalOffset: CGFloat = 50

        // Vertical position
        let isTopRow = buttonFrame.minY - popupHeight - verticalOffset < 0
        let popupY = isTopRow
            ? buttonFrame.maxY + verticalOffset
            : buttonFrame.minY - popupHeight - verticalOffset

        // Horizontal position
        let popupX: CGFloat
        if isTopRow {
            let isLeftSide = buttonFrame.midX < bounds.width / 2
            popupX = isLeftSide
                ? buttonFrame.minX + horizontalOffset
                : buttonFrame.maxX - popupWidth - horizontalOffset
        } else {
            let idealX = buttonFrame.midX - popupWidth / 2
            popupX = min(max(verticalOffset, idealX), bounds.width - popupWidth - verticalOffset)
        }

        popup.frame = CGRect(
            x: popupX,
            y: popupY,
            width: popupWidth,
            height: popupHeight
        )

        addSubview(popup)
        activeLongPressPopup = popup
    }

    private func dismissLongPressPopup() {
        activeLongPressPopup?.removeFromSuperview()
        activeLongPressPopup = nil
        longPressButton = nil
    }

    // MARK: - Backspace Long Press

    private func setupBackspaceLongPress(for button: KeyButton) {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleBackspaceLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        button.addGestureRecognizer(longPress)
    }

    @objc private func handleBackspaceLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            backspaceDeleteCount = 0
            startBackspaceRepeat()
        case .ended, .cancelled, .failed:
            stopBackspaceRepeat()
        default:
            break
        }
    }

    private func startBackspaceRepeat() {
        stopBackspaceRepeat()
        // Start with character-by-character deletion at 0.1s interval
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.performBackspaceRepeat()
        }
    }

    private func stopBackspaceRepeat() {
        backspaceTimer?.invalidate()
        backspaceTimer = nil
        backspaceDeleteCount = 0
    }

    private func performBackspaceRepeat() {
        backspaceDeleteCount += 1

        if backspaceDeleteCount > charDeleteThreshold {
            // Switch to word-by-word deletion
            delegate?.keyboardViewDidDeleteWord(self)
        } else {
            // Character-by-character deletion
            delegate?.keyboardViewDidTapBackspace(self)
        }
    }

    // MARK: - Actions

    @objc private func keyTapped(_ sender: KeyButton) {
        delegate?.keyboardView(self, didTapKey: sender.keyValue)
    }

    @objc private func symbolKeyTapped(_ sender: KeyButton) {
        delegate?.keyboardView(self, didTapSpecialKey: sender.keyValue)
    }

    @objc private func shiftTapped() {
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
        let now = Date()
        if let lastTap = lastSpaceTapTime, now.timeIntervalSince(lastTap) < 0.3 {
            delegate?.keyboardViewDidDoubleTapSpace(self)
            lastSpaceTapTime = nil
        } else {
            delegate?.keyboardViewDidTapSpace(self)
            lastSpaceTapTime = now
        }
    }

    @objc private func returnTapped() {
        delegate?.keyboardViewDidTapReturn(self)
    }

    @objc private func globeTapped() {
        delegate?.keyboardViewDidTapGlobe(self)
    }

    @objc private func modeTapped() {
        switch keyboardMode {
        case .letters:
            keyboardMode = .numbers
        case .numbers, .symbols:
            keyboardMode = .letters
        }
        rebuildKeyboard()
    }

    @objc private func symbolToggleTapped() {
        switch keyboardMode {
        case .numbers:
            keyboardMode = .symbols
        case .symbols:
            keyboardMode = .numbers
        case .letters:
            break
        }
        rebuildKeyboard()
    }

    // MARK: - Public Methods

    func updateShiftState(_ state: ShiftState) {
        shiftState = state

        guard keyboardMode == .letters else { return }

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
            shiftButton?.setHighlightedAppearance(false)
        case .uppercase:
            shiftButton?.setImage(UIImage(systemName: "shift.fill"), for: .normal)
            shiftButton?.setHighlightedAppearance(true)
        case .capsLock:
            shiftButton?.setImage(UIImage(systemName: "capslock.fill"), for: .normal)
            shiftButton?.setHighlightedAppearance(true)
        }
    }

    func updatePredictions(_ predictions: [String]) {
        for (i, label) in predictionLabels.enumerated() {
            label.text = i < predictions.count ? predictions[i] : nil
        }

        // Show separators only between adjacent predictions
        for (i, separator) in predictionSeparators.enumerated() {
            let hasLeft = predictionLabels[i].text?.isEmpty == false
            let hasRight = predictionLabels[i + 1].text?.isEmpty == false
            separator.isHidden = !(hasLeft && hasRight)
        }
    }
}
