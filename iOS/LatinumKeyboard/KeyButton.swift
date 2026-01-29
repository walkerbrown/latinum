import UIKit

/// Custom button for keyboard keys
class KeyButton: UIButton {

    // MARK: - Properties

    /// The key value this button represents
    let keyValue: String

    /// Whether this is a special key (shift, backspace, etc.)
    let isSpecial: Bool

    // MARK: - Initialization

    init(key: String, isSpecial: Bool = false) {
        self.keyValue = key
        self.isSpecial = isSpecial
        super.init(frame: .zero)
        setupButton()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupButton() {
        // Appearance
        if isSpecial {
            backgroundColor = UIColor.systemGray3
            setTitleColor(.label, for: .normal)
            tintColor = .label
        } else {
            backgroundColor = .white
            setTitleColor(.label, for: .normal)
            setTitle(keyValue, for: .normal)
        }

        titleLabel?.font = .systemFont(ofSize: 22, weight: .regular)

        // Shape
        layer.cornerRadius = 5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 0

        // Constraints
        translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Touch Feedback

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted {
                backgroundColor = isSpecial ? UIColor.systemGray4 : UIColor.systemGray5
                transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            } else {
                backgroundColor = isSpecial ? UIColor.systemGray3 : .white
                transform = .identity
            }
        }
    }
}
