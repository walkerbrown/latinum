import UIKit

/// Protocol for keyboard view delegate
protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, didTapKey key: String)
    func keyboardView(_ view: KeyboardView, didTapSpecialKey key: String)
    /// Returns true if a character was deleted.
    @discardableResult func keyboardViewDidTapBackspace(_ view: KeyboardView) -> Bool
    /// Returns true if a word was deleted.
    @discardableResult func keyboardViewDidDeleteWord(_ view: KeyboardView) -> Bool
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
class KeyboardView: UIInputView, UIGestureRecognizerDelegate {

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
    var feedback: KeyboardFeedback?

    private var shiftState: ShiftState = .lowercase
    private var keyboardMode: KeyboardMode = .letters
    private var keyButtons: [KeyButton] = []
    private var shiftButton: KeyButton?
    private var modeButton: KeyButton?
    private var symbolToggleButton: KeyButton?
    private var lastShiftTapTime: Date?

    private var spaceButton: KeyButton?
    private var spaceLabel: UILabel?
    private var langLabel: UILabel?
    private var lastSpaceTapTime: Date?

    private var showGlobeKey: Bool = true
    private var currentKeyboardType: UIKeyboardType = .default
    private var activeLongPressPopup: DiacriticMenuView?
    private var longPressButton: KeyButton?

    private var backspaceTimer: Timer?
    private var backspaceDeleteCount: Int = 0
    private let charDeleteThreshold: Int = 5
    private let backspaceRepeatInterval: TimeInterval = 0.12

    private let keyboardStack = UIStackView()
    private var predictionLabels: [UILabel] = []
    private var predictionSeparators: [UIView] = []
    private var rowSpacers: [UIView] = []
    private var predictionSpacer: UIView?

    // MARK: - Layout Constants

    private let keySpacing: CGFloat = 6
    private let wideKeyWidth: CGFloat = 50
    private let row3ExtraSpacing: CGFloat = 14
    private let predictionRowHeight: CGFloat = 28
    private let predictionContentHeight: CGFloat = 25
    private let topEdgePadding: CGFloat = 9
    private let bottomEdgePadding: CGFloat = 4
    private let minSpacerHeight: CGFloat = 10
    private var lastIsLandscape: Bool?

    private var isLandscape: Bool {
        UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }

    private var keyHeight: CGFloat {
        isLandscape ? 28 : 46
    }

    // MARK: - Initialization

    init() {
        super.init(frame: .zero, inputViewStyle: .keyboard)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = .clear
        setupKeyboardStack()
        rebuildKeyboard()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

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

    private func createSpacer() -> UIView {
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: minSpacerHeight).isActive = true
        return spacer
    }

    private func rebuildKeyboard(displayLanguageLabel: Bool = true) {
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

        let predictionRow = createPredictionRow()
        predictionRow.heightAnchor.constraint(equalToConstant: predictionRowHeight).isActive = true
        keyboardStack.addArrangedSubview(predictionRow)

        let belowPredictionSpacer = createSpacer()
        keyboardStack.addArrangedSubview(belowPredictionSpacer)
        predictionSpacer = belowPredictionSpacer

        switch keyboardMode {
        case .letters:
            buildLetterKeyboard(displayLanguageLabel: displayLanguageLabel)
        case .numbers:
            buildNumberKeyboard()
        case .symbols:
            buildSymbolKeyboard()
        }

        if let firstSpacer = rowSpacers.first {
            for spacer in rowSpacers.dropFirst() {
                spacer.heightAnchor.constraint(equalTo: firstSpacer.heightAnchor).isActive = true
            }
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

        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: predictionContentHeight),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        for i in 0..<3 {
            let tapContainer = UIView()
            tapContainer.tag = i
            tapContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(predictionTapped(_:))))

            let touchDown = UILongPressGestureRecognizer(target: self, action: #selector(predictionTouchedDown(_:)))
            touchDown.minimumPressDuration = 0
            touchDown.cancelsTouchesInView = false
            touchDown.delegate = self
            tapContainer.addGestureRecognizer(touchDown)

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

    @objc private func predictionTouchedDown(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let index = gesture.view?.tag,
              index < predictionLabels.count,
              let text = predictionLabels[index].text,
              !text.isEmpty else { return }
        feedback?.provideFeedback()
    }

    @objc private func predictionTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag,
              index < predictionLabels.count,
              let text = predictionLabels[index].text,
              !text.isEmpty else { return }
        delegate?.keyboardView(self, didSelectPrediction: text)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    // MARK: - Letter Keyboard

    private func buildLetterKeyboard(displayLanguageLabel: Bool = true) {
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

        if displayLanguageLabel {
            self.spaceButton?.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.35, alpha: 1.0)
                : UIColor(white: 1.0, alpha: 1.0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.animateSpaceBar()
            }
        } else {
            spaceLabel?.alpha = 0
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
            addFeedback(to: button)

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
            addFeedback(to: button)

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

        let shift = KeyButton(key: "shift")
        shift.setImage(UIImage(systemName: "shift"), for: .normal)
        shift.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
        addFeedback(to: shift)
        shift.widthAnchor.constraint(equalToConstant: wideKeyWidth).isActive = true
        shiftButton = shift
        row.addArrangedSubview(shift)

        let leftSpacer = UIView()
        leftSpacer.widthAnchor.constraint(equalToConstant: row3ExtraSpacing - keySpacing).isActive = true
        row.addArrangedSubview(leftSpacer)

        let letterStack = UIStackView()
        letterStack.axis = .horizontal
        letterStack.distribution = .fillEqually
        letterStack.spacing = keySpacing

        for key in letterRow3 {
            let button = KeyButton(key: key)
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            addFeedback(to: button)
            keyButtons.append(button)
            letterStack.addArrangedSubview(button)
        }
        row.addArrangedSubview(letterStack)

        let rightSpacer = UIView()
        rightSpacer.widthAnchor.constraint(equalToConstant: row3ExtraSpacing - keySpacing).isActive = true
        row.addArrangedSubview(rightSpacer)

        let backspace = KeyButton(key: "backspace")
        let backspaceConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        backspace.setImage(UIImage(systemName: "delete.left", withConfiguration: backspaceConfig), for: .normal)
        backspace.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        addFeedback(to: backspace)
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

        let modeWidth: CGFloat = showGlobeKey ? 48 : 48 + keySpacing + 48
        let mode = KeyButton(key: "123")
        mode.setTitle("123", for: .normal)
        mode.titleLabel?.font = .systemFont(ofSize: 18, weight: .regular)
        mode.addTarget(self, action: #selector(modeTapped), for: .touchUpInside)
        addFeedback(to: mode)
        mode.widthAnchor.constraint(equalToConstant: modeWidth).isActive = true
        modeButton = mode
        row.addArrangedSubview(mode)

        if showGlobeKey {
            let globeKey = KeyButton(key: "globe")
            globeKey.setImage(UIImage(systemName: "globe"), for: .normal)
            globeKey.addTarget(self, action: #selector(globeTapped), for: .touchUpInside)
            addFeedback(to: globeKey)
            globeKey.widthAnchor.constraint(equalToConstant: 48).isActive = true
            row.addArrangedSubview(globeKey)
        }

        addKeyboardTypeSpecificKeys(to: row)

        let space = createSpaceButton()
        addFeedback(to: space)
        row.addArrangedSubview(space)

        addKeyboardTypeSpecificKeysAfterSpace(to: row)

        let returnKey = KeyButton(key: "return")
        let returnConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        returnKey.setImage(UIImage(systemName: "return.left", withConfiguration: returnConfig), for: .normal)
        returnKey.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        addFeedback(to: returnKey)
        returnKey.widthAnchor.constraint(equalToConstant: 100).isActive = true
        row.addArrangedSubview(returnKey)

        return row
    }

    private func addKeyboardTypeSpecificKeys(to row: UIStackView) {
        switch currentKeyboardType {
        case .emailAddress:
            let atKey = KeyButton(key: "@")
            atKey.setTitle("@", for: .normal)
            atKey.titleLabel?.font = .systemFont(ofSize: 18)
            atKey.addTarget(self, action: #selector(symbolKeyTapped(_:)), for: .touchUpInside)
            addFeedback(to: atKey)
            atKey.widthAnchor.constraint(equalToConstant: 48).isActive = true
            row.addArrangedSubview(atKey)

        case .URL, .webSearch:
            let slashKey = KeyButton(key: "/")
            slashKey.setTitle("/", for: .normal)
            slashKey.titleLabel?.font = .systemFont(ofSize: 18)
            slashKey.addTarget(self, action: #selector(symbolKeyTapped(_:)), for: .touchUpInside)
            addFeedback(to: slashKey)
            slashKey.widthAnchor.constraint(equalToConstant: 36).isActive = true
            row.addArrangedSubview(slashKey)

        default:
            break
        }
    }

    private func addKeyboardTypeSpecificKeysAfterSpace(to row: UIStackView) {
        switch currentKeyboardType {
        case .emailAddress:
            let dotKey = KeyButton(key: ".")
            dotKey.setTitle(".", for: .normal)
            dotKey.titleLabel?.font = .systemFont(ofSize: 18)
            dotKey.addTarget(self, action: #selector(symbolKeyTapped(_:)), for: .touchUpInside)
            addFeedback(to: dotKey)
            dotKey.widthAnchor.constraint(equalToConstant: 48).isActive = true
            row.addArrangedSubview(dotKey)

        case .URL, .webSearch:
            let dotKey = KeyButton(key: ".")
            dotKey.setTitle(".", for: .normal)
            dotKey.titleLabel?.font = .systemFont(ofSize: 18)
            dotKey.addTarget(self, action: #selector(symbolKeyTapped(_:)), for: .touchUpInside)
            addFeedback(to: dotKey)
            dotKey.widthAnchor.constraint(equalToConstant: 36).isActive = true
            row.addArrangedSubview(dotKey)

            let comKey = KeyButton(key: ".com")
            comKey.setTitle(".com", for: .normal)
            comKey.titleLabel?.font = .systemFont(ofSize: 14)
            comKey.addTarget(self, action: #selector(comKeyTapped), for: .touchUpInside)
            addFeedback(to: comKey)
            comKey.widthAnchor.constraint(equalToConstant: 52).isActive = true
            row.addArrangedSubview(comKey)

        default:
            break
        }
    }

    @objc private func comKeyTapped() {
        delegate?.keyboardView(self, didTapSpecialKey: ".com")
    }

    private func createSpaceButton() -> UIButton {
        let space = KeyButton(key: "space")
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        spaceButton = space

        let centerLabel = UILabel()
        centerLabel.text = "Lingua Latina"
        centerLabel.font = .systemFont(ofSize: 16, weight: .medium)
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
        langLabel = langIndicator

        NSLayoutConstraint.activate([
            langIndicator.trailingAnchor.constraint(equalTo: space.trailingAnchor, constant: -6),
            langIndicator.bottomAnchor.constraint(equalTo: space.bottomAnchor, constant: -6),
        ])

        return space
    }

    private func animateSpaceBar() {
        guard let spaceLabel = spaceLabel else { return }

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
            addFeedback(to: button)
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

        let toggle = KeyButton(key: "symbolToggle")
        toggle.setTitle(keyboardMode == .numbers ? "#+=": "123", for: .normal)
        toggle.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        toggle.addTarget(self, action: #selector(symbolToggleTapped), for: .touchUpInside)
        addFeedback(to: toggle)
        toggle.widthAnchor.constraint(equalToConstant: wideKeyWidth).isActive = true
        symbolToggleButton = toggle
        row.addArrangedSubview(toggle)

        let leftSpacer = UIView()
        leftSpacer.widthAnchor.constraint(equalToConstant: row3ExtraSpacing - keySpacing).isActive = true
        row.addArrangedSubview(leftSpacer)

        let symbolStack = UIStackView()
        symbolStack.axis = .horizontal
        symbolStack.distribution = .fillEqually
        symbolStack.spacing = keySpacing

        for key in keys {
            let button = KeyButton(key: key)
            button.addTarget(self, action: #selector(symbolKeyTapped(_:)), for: .touchUpInside)
            addFeedback(to: button)
            keyButtons.append(button)
            symbolStack.addArrangedSubview(button)
        }
        row.addArrangedSubview(symbolStack)

        let rightSpacer = UIView()
        rightSpacer.widthAnchor.constraint(equalToConstant: row3ExtraSpacing - keySpacing).isActive = true
        row.addArrangedSubview(rightSpacer)

        let backspace = KeyButton(key: "backspace")
        let backspaceConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        backspace.setImage(UIImage(systemName: "delete.left", withConfiguration: backspaceConfig), for: .normal)
        backspace.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        addFeedback(to: backspace)
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

        let modeWidth: CGFloat = showGlobeKey ? 48 : 48 + keySpacing + 48
        let mode = KeyButton(key: "ABC")
        mode.setTitle("ABC", for: .normal)
        mode.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        mode.addTarget(self, action: #selector(modeTapped), for: .touchUpInside)
        addFeedback(to: mode)
        mode.widthAnchor.constraint(equalToConstant: modeWidth).isActive = true
        modeButton = mode
        row.addArrangedSubview(mode)

        if showGlobeKey {
            let globeKey = KeyButton(key: "globe")
            globeKey.setImage(UIImage(systemName: "globe"), for: .normal)
            globeKey.addTarget(self, action: #selector(globeTapped), for: .touchUpInside)
            addFeedback(to: globeKey)
            globeKey.widthAnchor.constraint(equalToConstant: 48).isActive = true
            row.addArrangedSubview(globeKey)
        }

        let space = KeyButton(key: "space")
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        addFeedback(to: space)

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

        let returnKey = KeyButton(key: "return")
        let returnConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        returnKey.setImage(UIImage(systemName: "return.left", withConfiguration: returnConfig), for: .normal)
        returnKey.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        addFeedback(to: returnKey)
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
            feedback?.provideHapticOnly()

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
        let popup = DiacriticMenuView(options: options)

        let popupWidth = DiacriticMenuView.popupWidth(for: options.count)
        let popupHeight = DiacriticMenuView.popupHeight()

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

        popup.onSelectionChanged = { [weak self] in
            self?.feedback?.provideFeedback()
        }

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
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: backspaceRepeatInterval, repeats: true) { [weak self] _ in
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

        let deleted: Bool
        if backspaceDeleteCount > charDeleteThreshold {
            deleted = delegate?.keyboardViewDidDeleteWord(self) ?? false
        } else {
            deleted = delegate?.keyboardViewDidTapBackspace(self) ?? false
        }

        if deleted {
            feedback?.provideFeedback()
        } else {
            // Nothing left to delete — stop repeating
            stopBackspaceRepeat()
        }
    }

    // MARK: - Feedback

    private func addFeedback(to button: UIButton) {
        button.addTarget(self, action: #selector(keyTouchedDown(_:)), for: .touchDown)
    }

    @objc private func keyTouchedDown(_ sender: UIButton) {
        feedback?.provideFeedback()
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

        // Return to letters mode after space in numbers/symbols mode
        if keyboardMode != .letters {
            keyboardMode = .letters
            rebuildKeyboard(displayLanguageLabel: false)
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

    /// Record a space insertion so the next physical space tap triggers double-tap.
    func recordSpaceTap() {
        lastSpaceTapTime = Date()
    }

    func updateShiftState(_ state: ShiftState) {
        shiftState = state

        guard keyboardMode == .letters else { return }

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

        for (i, separator) in predictionSeparators.enumerated() {
            let hasLeft = predictionLabels[i].text?.isEmpty == false
            let hasRight = predictionLabels[i + 1].text?.isEmpty == false
            separator.isHidden = !(hasLeft && hasRight)
        }
    }

    func updateGlobeKeyVisibility(_ visible: Bool) {
        guard showGlobeKey != visible else { return }
        showGlobeKey = visible
        rebuildKeyboard()
    }

    func updateKeyboardType(_ type: UIKeyboardType) {
        guard currentKeyboardType != type else { return }
        currentKeyboardType = type
        rebuildKeyboard()
    }
}
