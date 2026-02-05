import UIKit

/// Popup view for long-press character options (macrons, ligatures)
class LongPressPopupView: UIView {

    // MARK: - Properties

    var onSelect: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    var onSelectionChanged: (() -> Void)?

    private let options: [String]
    private var optionViews: [UIView] = []
    private var optionLabels: [UILabel] = []
    private var selectedIndex: Int? {
        didSet {
            guard selectedIndex != oldValue else { return }
            updateHighlight()
            if selectedIndex != nil {
                onSelectionChanged?()
            }
        }
    }

    private static let optionWidth: CGFloat = 44
    private static let optionHeight: CGFloat = 44

    // MARK: - Initialization

    init(options: [String]) {
        self.options = options
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        // Adaptive background: white in light mode, gray in dark mode
        backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.25, alpha: 1.0)
                : UIColor.white
        }
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 0.3

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        for option in options {
            // Container view for highlight background
            let container = UIView()
            container.layer.cornerRadius = 6
            container.clipsToBounds = true

            let label = UILabel()
            label.text = option
            label.font = .systemFont(ofSize: 24)
            label.textColor = .label
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])

            optionViews.append(container)
            optionLabels.append(label)
            stackView.addArrangedSubview(container)
        }
    }

    // MARK: - Public Methods

    /// Update selection based on touch location (in superview coordinates)
    func updateSelection(at point: CGPoint) {
        let localPoint = convert(point, from: superview)

        // Check if point is within popup bounds (with some tolerance)
        let expandedBounds = bounds.insetBy(dx: -10, dy: -10)
        if expandedBounds.contains(localPoint) {
            // Calculate which option is selected
            let adjustedX = localPoint.x - 4 // Account for padding
            let optionWidth = (bounds.width - 8) / CGFloat(options.count)
            let index = Int(adjustedX / optionWidth)
            selectedIndex = min(max(0, index), options.count - 1)
        } else {
            selectedIndex = nil
        }
    }

    /// Complete selection and return selected character (or nil if none)
    func completeSelection() -> String? {
        if let index = selectedIndex, index >= 0, index < options.count {
            return options[index]
        }
        return nil
    }

    private func updateHighlight() {
        for (index, container) in optionViews.enumerated() {
            if index == selectedIndex {
                container.backgroundColor = UIColor.systemBlue
                optionLabels[index].textColor = .white
            } else {
                container.backgroundColor = .clear
                optionLabels[index].textColor = .label
            }
        }
    }

    // MARK: - Class Methods

    class func popupWidth(for optionCount: Int) -> CGFloat {
        return CGFloat(optionCount) * optionWidth + 8 // Add padding
    }

    class func popupHeight() -> CGFloat {
        return optionHeight + 8 // Add padding
    }
}
