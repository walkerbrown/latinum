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
    func keyboardViewDidTapDismiss(_ view: KeyboardView)
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

    /// Punctuation appended to the bottom letter row on iPad (native layout),
    /// with the characters shown and typed while shift/caps lock is engaged.
    private let padLetterRow3Punctuation = [",", "."]
    private let padPunctuationShiftMap = [",": "!", ".": "?"]

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
    private var shiftButtons: [KeyButton] = []
    private var padPunctuationButtons: [KeyButton] = []
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

    // MARK: - Layout Style

    /// Layout family for the keyboard, resolved from the view's own size —
    /// never from UIScreen, which reports the device screen rather than the
    /// keyboard's actual container (wrong on iPad in Split View, Slide Over,
    /// Stage Manager, and the floating keyboard).
    private enum LayoutStyle {
        case iPhonePortrait    // compact widths, incl. iPad floating keyboard / Slide Over
        case iPhoneLandscape
        case iPadPortrait
        case iPadLandscape

        var isPad: Bool { self == .iPadPortrait || self == .iPadLandscape }
    }

    private var layoutStyle: LayoutStyle = .iPhonePortrait
    private var hasResolvedLayoutStyle = false

    private var isPadIdiom: Bool {
        switch traitCollection.userInterfaceIdiom {
        case .pad:
            return true
        case .unspecified:
            return UIDevice.current.userInterfaceIdiom == .pad
        default:
            return false
        }
    }

    private func resolveLayoutStyle() -> LayoutStyle {
        let width = bounds.width
        if isPadIdiom && width >= 500 {
            // A docked keyboard spans the screen's current width, so when the
            // view is screen-spanning, orientation follows from which screen
            // dimension it matches. A width threshold alone cannot tell
            // 12.9"/13" portrait (1024pt) from 9.7" landscape (1024pt).
            if let screenSize = window?.screen.bounds.size {
                let minDim = min(screenSize.width, screenSize.height)
                let maxDim = max(screenSize.width, screenSize.height)
                if width >= maxDim - 1 { return .iPadLandscape }
                if width >= minDim - 1 { return .iPadPortrait }
            }
            // Partial-width container (Split View, Stage Manager): by size.
            return width >= 1000 ? .iPadLandscape : .iPadPortrait
        }
        return width >= 500 ? .iPhoneLandscape : .iPhonePortrait
    }

    // MARK: - Layout Constants

    private var keySpacing: CGFloat {
        switch layoutStyle {
        case .iPhonePortrait, .iPhoneLandscape: return 6
        case .iPadPortrait: return 7
        case .iPadLandscape: return 9
        }
    }

    private let wideKeyWidth: CGFloat = 50
    private let row3ExtraSpacing: CGFloat = 14
    private let predictionRowHeight: CGFloat = 28
    private let predictionContentHeight: CGFloat = 25
    private let topEdgePadding: CGFloat = 9
    private let bottomEdgePadding: CGFloat = 4

    private var minSpacerHeight: CGFloat {
        layoutStyle.isPad ? 11 : 10
    }

    /// iPad values follow the native keyboard's row pitch (~64pt portrait,
    /// ~86pt landscape including inter-row gaps).
    private var keyHeight: CGFloat {
        switch layoutStyle {
        case .iPhonePortrait: return 46
        case .iPhoneLandscape: return 28
        case .iPadPortrait: return 56
        case .iPadLandscape: return 74
        }
    }

    /// Total keyboard height requested on iPad, where the view sizes itself
    /// (spacers sit at their minimum). On iPhone the system height is used.
    private var preferredPadHeight: CGFloat {
        predictionRowHeight + topEdgePadding + bottomEdgePadding
            + 4 * keyHeight + 5 * minSpacerHeight
    }

    private var heightConstraint: NSLayoutConstraint?
    private var stackLeadingConstraint: NSLayoutConstraint?
    private var stackTrailingConstraint: NSLayoutConstraint?

    /// Pending width constraints for iPad keys, expressed in letter-key units;
    /// activated once rows are in the view hierarchy.
    private var padWidthPlan: [(button: UIView, keyUnits: CGFloat, spacingUnits: CGFloat)] = []
    private var padEqualWidthPairs: [(UIView, UIView)] = []

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

        // Always rebuild on the first layout pass (matching pre-iPad behavior):
        // the view now has resolved traits, so trait-dependent key colors set
        // during the rebuild survive instead of being reset by trait-change
        // handlers firing on window attachment.
        let resolved = resolveLayoutStyle()
        if resolved != layoutStyle || !hasResolvedLayoutStyle {
            let isFirstResolve = !hasResolvedLayoutStyle
            hasResolvedLayoutStyle = true
            layoutStyle = resolved
            // On iPad, style changes happen routinely (rotation, floating
            // transitions) — skip the space-bar language splash for those
            // rebuilds. iPhone keeps its original behavior.
            rebuildKeyboard(displayLanguageLabel: isFirstResolve || !isPadIdiom)
            updateHeightForStyle()
        }
    }

    /// On iPad the keyboard view requests its own height; on iPhone the
    /// system-provided height is kept (spacers absorb the difference).
    private func updateHeightForStyle() {
        if layoutStyle.isPad {
            let constraint: NSLayoutConstraint
            if let existing = heightConstraint {
                constraint = existing
            } else {
                constraint = heightAnchor.constraint(equalToConstant: preferredPadHeight)
                constraint.priority = UILayoutPriority(999)
                heightConstraint = constraint
            }
            constraint.constant = preferredPadHeight
            constraint.isActive = true
        } else {
            heightConstraint?.isActive = false
        }
    }

    private func setupKeyboardStack() {
        keyboardStack.axis = .vertical
        keyboardStack.distribution = .fill
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyboardStack)

        let leading = keyboardStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: keySpacing + 1)
        let trailing = keyboardStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(keySpacing + 1))
        stackLeadingConstraint = leading
        stackTrailingConstraint = trailing

        NSLayoutConstraint.activate([
            keyboardStack.topAnchor.constraint(equalTo: topAnchor, constant: topEdgePadding),
            keyboardStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomEdgePadding),
            leading,
            trailing,
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
        // Carry the visible predictions across the rebuild — rebuilds happen
        // on rotation/style changes, and no controller event refreshes the
        // bar until the next keystroke.
        let existingPredictions = predictionLabels.map { $0.text ?? "" }

        for view in keyboardStack.arrangedSubviews {
            keyboardStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        keyButtons.removeAll()
        shiftButtons.removeAll()
        padPunctuationButtons.removeAll()
        modeButton = nil
        symbolToggleButton = nil
        spaceButton = nil
        spaceLabel = nil
        langLabel = nil
        predictionLabels.removeAll()
        predictionSeparators.removeAll()
        rowSpacers.removeAll()
        predictionSpacer = nil
        padWidthPlan.removeAll()
        padEqualWidthPairs.removeAll()

        stackLeadingConstraint?.constant = keySpacing + 1
        stackTrailingConstraint?.constant = -(keySpacing + 1)

        let predictionRow = createPredictionRow()
        predictionRow.heightAnchor.constraint(equalToConstant: predictionRowHeight).isActive = true
        keyboardStack.addArrangedSubview(predictionRow)

        let belowPredictionSpacer = createSpacer()
        keyboardStack.addArrangedSubview(belowPredictionSpacer)
        predictionSpacer = belowPredictionSpacer

        switch keyboardMode {
        case .letters:
            if layoutStyle.isPad {
                buildPadLetterKeyboard(displayLanguageLabel: displayLanguageLabel)
            } else {
                buildLetterKeyboard(displayLanguageLabel: displayLanguageLabel)
            }
        case .numbers:
            layoutStyle.isPad ? buildPadNumberKeyboard() : buildNumberKeyboard()
        case .symbols:
            layoutStyle.isPad ? buildPadSymbolKeyboard() : buildSymbolKeyboard()
        }

        if let firstSpacer = rowSpacers.first {
            for spacer in rowSpacers.dropFirst() {
                spacer.heightAnchor.constraint(equalTo: firstSpacer.heightAnchor).isActive = true
            }
            predictionSpacer?.heightAnchor.constraint(equalTo: firstSpacer.heightAnchor, multiplier: 2).isActive = true
        }

        if existingPredictions.contains(where: { !$0.isEmpty }) {
            updatePredictions(existingPredictions)
        }
    }

    /// Add key rows to the keyboard stack with uniform heights and stretchable
    /// spacers between them.
    private func addKeyRows(_ rows: [UIView]) {
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

    // MARK: - Shared Key Builders

    private func makeLetterButton(_ key: String) -> KeyButton {
        let button = KeyButton(key: key)
        button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        addFeedback(to: button)

        if longPressKeys.keys.contains(key.lowercased()) {
            setupLongPress(for: button)
        }

        keyButtons.append(button)
        return button
    }

    private func makeSymbolButton(_ key: String, fontSize: CGFloat? = nil) -> KeyButton {
        let button = KeyButton(key: key)
        button.addTarget(self, action: #selector(symbolKeyTapped(_:)), for: .touchUpInside)
        addFeedback(to: button)
        if let fontSize {
            button.titleLabel?.font = .systemFont(ofSize: fontSize)
        }
        return button
    }

    private func makeShiftButton() -> KeyButton {
        let shift = KeyButton(key: "shift")
        shift.setImage(UIImage(systemName: "shift"), for: .normal)
        shift.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
        addFeedback(to: shift)
        shiftButtons.append(shift)
        return shift
    }

    private func makeBackspaceButton() -> KeyButton {
        let backspace = KeyButton(key: "backspace")
        let backspaceConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        backspace.setImage(UIImage(systemName: "delete.left", withConfiguration: backspaceConfig), for: .normal)
        backspace.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        addFeedback(to: backspace)
        setupBackspaceLongPress(for: backspace)
        return backspace
    }

    private func makeReturnButton() -> KeyButton {
        let returnKey = KeyButton(key: "return")
        let returnConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        returnKey.setImage(UIImage(systemName: "return.left", withConfiguration: returnConfig), for: .normal)
        returnKey.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        addFeedback(to: returnKey)
        return returnKey
    }

    private func makeGlobeButton() -> KeyButton {
        let globeKey = KeyButton(key: "globe")
        globeKey.setImage(UIImage(systemName: "globe"), for: .normal)
        globeKey.addTarget(self, action: #selector(globeTapped), for: .touchUpInside)
        addFeedback(to: globeKey)
        return globeKey
    }

    private func makeModeButton(title: String, fontSize: CGFloat) -> KeyButton {
        let mode = KeyButton(key: title)
        mode.setTitle(title, for: .normal)
        mode.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .regular)
        mode.addTarget(self, action: #selector(modeTapped), for: .touchUpInside)
        addFeedback(to: mode)
        return mode
    }

    /// Fixed key width at just-below-required priority: at iPhone widths the
    /// constraint is satisfied exactly (rendering unchanged), but very narrow
    /// containers (iPad floating keyboard / Slide Over) compress these keys
    /// instead of breaking required constraints and zeroing the space bar.
    private func setCompressibleWidth(_ button: UIView, _ width: CGFloat) {
        let constraint = button.widthAnchor.constraint(equalToConstant: width)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
    }

    /// Shared tail of the letter-plane build: shift appearance and the
    /// transient "Lingua Latina" space-bar label.
    private func finishLetterKeyboard(displayLanguageLabel: Bool) {
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

    // MARK: - Letter Keyboard (iPhone)

    private func buildLetterKeyboard(displayLanguageLabel: Bool = true) {
        let row1 = createUniformKeyRow(keys: letterRow1)
        let row2 = createCenteredKeyRow(keys: letterRow2)
        let row3 = createBottomLetterRow()
        let row4 = createBottomFunctionRow()

        addKeyRows([row1, row2, row3, row4])
        finishLetterKeyboard(displayLanguageLabel: displayLanguageLabel)
    }

    private func createUniformKeyRow(keys: [String]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = keySpacing

        for key in keys {
            row.addArrangedSubview(makeLetterButton(key))
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
            keyStack.addArrangedSubview(makeLetterButton(key))
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

        let shift = makeShiftButton()
        shift.widthAnchor.constraint(equalToConstant: wideKeyWidth).isActive = true
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

        let backspace = makeBackspaceButton()
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
        let mode = makeModeButton(title: "123", fontSize: 18)
        setCompressibleWidth(mode, modeWidth)
        modeButton = mode
        row.addArrangedSubview(mode)

        if showGlobeKey {
            let globeKey = makeGlobeButton()
            setCompressibleWidth(globeKey, 48)
            row.addArrangedSubview(globeKey)
        }

        addKeyboardTypeSpecificKeys(to: row)

        let space = createSpaceButton()
        addFeedback(to: space)
        space.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        row.addArrangedSubview(space)

        addKeyboardTypeSpecificKeysAfterSpace(to: row)

        let returnKey = makeReturnButton()
        setCompressibleWidth(returnKey, 100)
        row.addArrangedSubview(returnKey)

        return row
    }

    private func addKeyboardTypeSpecificKeys(to row: UIStackView) {
        switch currentKeyboardType {
        case .emailAddress:
            let atKey = makeSymbolButton("@", fontSize: 18)
            setCompressibleWidth(atKey, 48)
            row.addArrangedSubview(atKey)

        case .URL, .webSearch:
            let slashKey = makeSymbolButton("/", fontSize: 18)
            setCompressibleWidth(slashKey, 36)
            row.addArrangedSubview(slashKey)

        default:
            break
        }
    }

    private func addKeyboardTypeSpecificKeysAfterSpace(to row: UIStackView) {
        switch currentKeyboardType {
        case .emailAddress:
            let dotKey = makeSymbolButton(".", fontSize: 18)
            setCompressibleWidth(dotKey, 48)
            row.addArrangedSubview(dotKey)

        case .URL, .webSearch:
            let dotKey = makeSymbolButton(".", fontSize: 18)
            setCompressibleWidth(dotKey, 36)
            row.addArrangedSubview(dotKey)

            let comKey = makeComKey()
            setCompressibleWidth(comKey, 52)
            row.addArrangedSubview(comKey)

        default:
            break
        }
    }

    private func makeComKey() -> KeyButton {
        let comKey = KeyButton(key: ".com")
        comKey.setTitle(".com", for: .normal)
        comKey.titleLabel?.font = .systemFont(ofSize: 14)
        comKey.addTarget(self, action: #selector(comKeyTapped), for: .touchUpInside)
        addFeedback(to: comKey)
        return comKey
    }

    @objc private func comKeyTapped() {
        delegate?.keyboardView(self, didTapSpecialKey: ".com")
    }

    private func createSpaceButton() -> KeyButton {
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

        addLangIndicator(to: space)

        return space
    }

    private func addLangIndicator(to space: KeyButton) {
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

    // MARK: - Number Keyboard (iPhone)

    private func buildNumberKeyboard() {
        let row1 = createSymbolRow(keys: numberRow1)
        let row2 = createSymbolRow(keys: numberRow2)
        let row3 = createNumberBottomRow(keys: numberRow3)
        let row4 = createNumberFunctionRow()

        addKeyRows([row1, row2, row3, row4])
    }

    private func buildSymbolKeyboard() {
        let row1 = createSymbolRow(keys: symbolRow1)
        let row2 = createSymbolRow(keys: symbolRow2)
        let row3 = createNumberBottomRow(keys: symbolRow3)
        let row4 = createNumberFunctionRow()

        addKeyRows([row1, row2, row3, row4])
    }

    private func createSymbolRow(keys: [String]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = keySpacing

        for key in keys {
            let button = makeSymbolButton(key, fontSize: 21)
            keyButtons.append(button)
            row.addArrangedSubview(button)
        }

        return row
    }

    private func makeSymbolToggleButton() -> KeyButton {
        let toggle = KeyButton(key: "symbolToggle")
        toggle.setTitle(keyboardMode == .numbers ? "#+=" : "123", for: .normal)
        toggle.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        toggle.addTarget(self, action: #selector(symbolToggleTapped), for: .touchUpInside)
        addFeedback(to: toggle)
        return toggle
    }

    private func createNumberBottomRow(keys: [String]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.spacing = keySpacing

        let toggle = makeSymbolToggleButton()
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
            let button = makeSymbolButton(key)
            keyButtons.append(button)
            symbolStack.addArrangedSubview(button)
        }
        row.addArrangedSubview(symbolStack)

        let rightSpacer = UIView()
        rightSpacer.widthAnchor.constraint(equalToConstant: row3ExtraSpacing - keySpacing).isActive = true
        row.addArrangedSubview(rightSpacer)

        let backspace = makeBackspaceButton()
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
        let mode = makeModeButton(title: "ABC", fontSize: 16)
        setCompressibleWidth(mode, modeWidth)
        modeButton = mode
        row.addArrangedSubview(mode)

        if showGlobeKey {
            let globeKey = makeGlobeButton()
            setCompressibleWidth(globeKey, 48)
            row.addArrangedSubview(globeKey)
        }

        let space = KeyButton(key: "space")
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        addFeedback(to: space)
        addLangIndicator(to: space)
        space.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        row.addArrangedSubview(space)

        let returnKey = makeReturnButton()
        setCompressibleWidth(returnKey, 100)
        row.addArrangedSubview(returnKey)

        return row
    }

    // MARK: - iPad Keyboard
    //
    // Native iPad arrangement: backspace ends the top row, return ends the
    // home row, shift keys flank the bottom letter row (which gains comma and
    // period), and the function row has mode keys on both sides of space plus
    // a dismiss-keyboard key in the corner.
    //
    // Key widths are expressed in letter-key units of an 11-column grid:
    // k = (rowWidth - 10·spacing) / 11. Constraints are written against the
    // keyboard stack's width so they stay correct when the container resizes
    // continuously (Split View, Stage Manager) without a rebuild.

    private func buildPadLetterKeyboard(displayLanguageLabel: Bool = true) {
        let row1 = createPadTopRow(keys: letterRow1, symbolAction: false)
        let row2 = createPadHomeRow(keys: letterRow2, symbolAction: false)
        let row3 = createPadShiftRow()
        let row4 = createPadFunctionRow(modeTitle: ".?123")

        addKeyRows([row1, row2, row3, row4])
        activatePadWidthConstraints()
        finishLetterKeyboard(displayLanguageLabel: displayLanguageLabel)
    }

    private func buildPadNumberKeyboard() {
        let row1 = createPadTopRow(keys: numberRow1, symbolAction: true)
        let row2 = createPadHomeRow(keys: numberRow2, symbolAction: true)
        let row3 = createPadToggleRow(keys: numberRow3)
        let row4 = createPadFunctionRow(modeTitle: "ABC")

        addKeyRows([row1, row2, row3, row4])
        activatePadWidthConstraints()
        spaceLabel?.alpha = 0
    }

    private func buildPadSymbolKeyboard() {
        let row1 = createPadTopRow(keys: symbolRow1, symbolAction: true)
        let row2 = createPadHomeRow(keys: symbolRow2, symbolAction: true)
        let row3 = createPadToggleRow(keys: symbolRow3)
        let row4 = createPadFunctionRow(modeTitle: "ABC")

        addKeyRows([row1, row2, row3, row4])
        activatePadWidthConstraints()
        spaceLabel?.alpha = 0
    }

    /// Top row: ten character keys plus backspace, all equal width.
    private func createPadTopRow(keys: [String], symbolAction: Bool) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = keySpacing

        for key in keys {
            if symbolAction {
                let button = makeSymbolButton(key, fontSize: 21)
                keyButtons.append(button)
                row.addArrangedSubview(button)
            } else {
                row.addArrangedSubview(makeLetterButton(key))
            }
        }

        row.addArrangedSubview(makeBackspaceButton())

        return row
    }

    /// Home row: character keys plus a return key that absorbs the remaining
    /// width. The 9-letter row gets the native half-key stagger via a leading
    /// spacer; the 10-symbol rows keep return wide by slightly narrowing keys.
    private func createPadHomeRow(keys: [String], symbolAction: Bool) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.spacing = keySpacing

        if keys.count == 9 {
            let stagger = UIView()
            planPadWidth(stagger, keyUnits: 0.4)
            row.addArrangedSubview(stagger)
        }

        for key in keys {
            let button: KeyButton
            if symbolAction {
                button = makeSymbolButton(key, fontSize: 21)
                keyButtons.append(button)
            } else {
                button = makeLetterButton(key)
            }
            if keys.count == 9 {
                planPadWidth(button, keyUnits: 1)
            } else {
                // 10 keys: shave each so return still gets 2 units + spacing
                planPadWidth(button, keyUnits: 0.9, spacingUnits: -0.1)
            }
            row.addArrangedSubview(button)
        }

        row.addArrangedSubview(makeReturnButton())

        return row
    }

    /// Bottom letter row: shift, letters, comma, period, shift — equal widths.
    private func createPadShiftRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = keySpacing

        row.addArrangedSubview(makeShiftButton())

        for key in letterRow3 {
            let button = KeyButton(key: key)
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            addFeedback(to: button)
            keyButtons.append(button)
            row.addArrangedSubview(button)
        }

        for key in padLetterRow3Punctuation {
            let button = KeyButton(key: key)
            button.addTarget(self, action: #selector(padPunctuationTapped(_:)), for: .touchUpInside)
            addFeedback(to: button)
            padPunctuationButtons.append(button)
            row.addArrangedSubview(button)
        }

        row.addArrangedSubview(makeShiftButton())

        return row
    }

    /// Bottom symbol row: wide plane-toggle keys flanking the punctuation keys.
    private func createPadToggleRow(keys: [String]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.spacing = keySpacing

        let leftToggle = makeSymbolToggleButton()
        symbolToggleButton = leftToggle
        row.addArrangedSubview(leftToggle)

        for key in keys {
            let button = makeSymbolButton(key)
            keyButtons.append(button)
            planPadWidth(button, keyUnits: 1)
            row.addArrangedSubview(button)
        }

        let rightToggle = makeSymbolToggleButton()
        row.addArrangedSubview(rightToggle)
        padEqualWidthPairs.append((leftToggle, rightToggle))

        return row
    }

    /// Function row: mode key, globe, space, mode key, dismiss-keyboard key.
    private func createPadFunctionRow(modeTitle: String) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.spacing = keySpacing

        // Native classic-iPad proportions: left mode key is letter-width,
        // the right-corner mode and dismiss keys are ~1.45 letter widths.
        let modeFontSize: CGFloat = modeTitle == "ABC" ? 16 : 18
        let leftMode = makeModeButton(title: modeTitle, fontSize: modeFontSize)
        modeButton = leftMode
        planPadWidth(leftMode, keyUnits: 1)
        row.addArrangedSubview(leftMode)

        if showGlobeKey {
            let globeKey = makeGlobeButton()
            planPadWidth(globeKey, keyUnits: 1)
            row.addArrangedSubview(globeKey)
        }

        if keyboardMode == .letters {
            addPadKeyboardTypeSpecificKeys(to: row)
        }

        let space = createSpaceButton()
        addFeedback(to: space)
        row.addArrangedSubview(space)

        if keyboardMode == .letters {
            addPadKeyboardTypeSpecificKeysAfterSpace(to: row)
        }

        let rightMode = makeModeButton(title: modeTitle, fontSize: modeFontSize)
        planPadWidth(rightMode, keyUnits: 1.45)
        row.addArrangedSubview(rightMode)

        let dismissKey = KeyButton(key: "dismiss")
        let dismissConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        dismissKey.setImage(UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: dismissConfig), for: .normal)
        dismissKey.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        addFeedback(to: dismissKey)
        planPadWidth(dismissKey, keyUnits: 1.45)
        row.addArrangedSubview(dismissKey)

        return row
    }

    private func addPadKeyboardTypeSpecificKeys(to row: UIStackView) {
        switch currentKeyboardType {
        case .emailAddress:
            let atKey = makeSymbolButton("@", fontSize: 18)
            planPadWidth(atKey, keyUnits: 1)
            row.addArrangedSubview(atKey)

        case .URL, .webSearch:
            let slashKey = makeSymbolButton("/", fontSize: 18)
            planPadWidth(slashKey, keyUnits: 1)
            row.addArrangedSubview(slashKey)

        default:
            break
        }
    }

    private func addPadKeyboardTypeSpecificKeysAfterSpace(to row: UIStackView) {
        switch currentKeyboardType {
        case .emailAddress:
            let dotKey = makeSymbolButton(".", fontSize: 18)
            planPadWidth(dotKey, keyUnits: 1)
            row.addArrangedSubview(dotKey)

        case .URL, .webSearch:
            let dotKey = makeSymbolButton(".", fontSize: 18)
            planPadWidth(dotKey, keyUnits: 1)
            row.addArrangedSubview(dotKey)

            let comKey = makeComKey()
            planPadWidth(comKey, keyUnits: 1)
            row.addArrangedSubview(comKey)

        default:
            break
        }
    }

    private func planPadWidth(_ button: UIView, keyUnits: CGFloat, spacingUnits: CGFloat = 0) {
        padWidthPlan.append((button, keyUnits, spacingUnits))
    }

    /// Activate planned iPad width constraints. Width = keyUnits·k +
    /// spacingUnits·s where k = (stackWidth - 10·s)/11, rewritten as a
    /// multiplier + constant against the keyboard stack's width anchor.
    private func activatePadWidthConstraints() {
        let s = keySpacing
        for entry in padWidthPlan {
            entry.button.widthAnchor.constraint(
                equalTo: keyboardStack.widthAnchor,
                multiplier: entry.keyUnits / 11.0,
                constant: (entry.spacingUnits - entry.keyUnits * 10.0 / 11.0) * s
            ).isActive = true
        }
        padWidthPlan.removeAll()

        for (left, right) in padEqualWidthPairs {
            right.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        }
        padEqualWidthPairs.removeAll()
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
        let optionSize: CGFloat = layoutStyle.isPad ? 56 : 44
        let popup = DiacriticMenuView(options: options, optionSize: optionSize)

        let popupWidth = DiacriticMenuView.popupWidth(for: options.count, optionSize: optionSize)
        let popupHeight = DiacriticMenuView.popupHeight(optionSize: optionSize)

        let buttonFrame = button.convert(button.bounds, to: self)
        let verticalOffset: CGFloat = 4

        // Above the key (native callout direction), clamped to the view's top
        // edge — for the top row on iPad the popup overlaps the prediction bar
        // rather than flipping below the user's finger.
        let popupY = max(0, buttonFrame.minY - popupHeight - verticalOffset)

        let idealX = buttonFrame.midX - popupWidth / 2
        let popupX = min(max(verticalOffset, idealX), bounds.width - popupWidth - verticalOffset)

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

    /// iPad letters-plane comma/period: types whatever the key currently
    /// displays ("," / "." or, while shifted, "!" / "?").
    @objc private func padPunctuationTapped(_ sender: KeyButton) {
        delegate?.keyboardView(self, didTapSpecialKey: sender.currentTitle ?? sender.keyValue)
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

    @objc private func dismissTapped() {
        delegate?.keyboardViewDidTapDismiss(self)
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

        for shiftButton in shiftButtons {
            switch state {
            case .lowercase:
                shiftButton.setImage(UIImage(systemName: "shift"), for: .normal)
                shiftButton.setHighlightedAppearance(false)
            case .uppercase:
                shiftButton.setImage(UIImage(systemName: "shift.fill"), for: .normal)
                shiftButton.setHighlightedAppearance(true)
            case .capsLock:
                shiftButton.setImage(UIImage(systemName: "capslock.fill"), for: .normal)
                shiftButton.setHighlightedAppearance(true)
            }
        }

        for button in padPunctuationButtons {
            let title = state == .lowercase
                ? button.keyValue
                : (padPunctuationShiftMap[button.keyValue] ?? button.keyValue)
            button.setTitle(title, for: .normal)
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
        if type == .emailAddress || type == .URL || type == .webSearch {
            rebuildKeyboard(displayLanguageLabel: false)
        } else {
            rebuildKeyboard()
        }
    }
}
