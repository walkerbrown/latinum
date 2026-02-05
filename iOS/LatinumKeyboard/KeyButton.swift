import UIKit

/// Custom button for keyboard keys
class KeyButton: UIButton {

    // MARK: - Properties

    /// The key value this button represents
    let keyValue: String

    // MARK: - Computed Colors (adaptive for dark/light mode)

    private var normalBackgroundColor: UIColor {
        // All keys use the same color
        return UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.25, alpha: 1.0)
                : UIColor.white
        }
    }

    private var highlightedBackgroundColor: UIColor {
        // All keys use the same highlight color
        return UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.20, alpha: 1.0)
                : UIColor.systemGray5
        }
    }

    // MARK: - Initialization

    init(key: String) {
        self.keyValue = key
        super.init(frame: .zero)
        setupButton()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupButton() {
        backgroundColor = normalBackgroundColor
        setTitleColor(.label, for: .normal)
        tintColor = .label

        // Auto-set title only for single character keys (letters, numbers, symbols)
        // Multi-character keys (shift, backspace, etc.) get custom images/titles
        if keyValue.count == 1 {
            setTitle(keyValue, for: .normal)
        }

        titleLabel?.font = .systemFont(ofSize: 22, weight: .regular)
        layer.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false

        // Update background color when color appearance changes (dark/light mode)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.backgroundColor = self.isHighlighted ? self.highlightedBackgroundColor : self.normalBackgroundColor
        }
    }

    // MARK: - Touch Feedback

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted {
                backgroundColor = highlightedBackgroundColor
                transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            } else {
                backgroundColor = normalBackgroundColor
                transform = .identity
            }
        }
    }

    /// Force update background color (e.g., for shift key state changes)
    func setHighlightedAppearance(_ highlighted: Bool) {
        if highlighted {
            backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 0.25, alpha: 1.0)
                    : UIColor.white
            }
        } else {
            backgroundColor = normalBackgroundColor
        }
    }
}
