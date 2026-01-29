import UIKit

/// Popup view for long-press character options (macrons, ligatures)
class LongPressPopupView: UIView {

    // MARK: - Properties

    var onSelect: ((String) -> Void)?

    private let stackView = UIStackView()
    private let options: [String]

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
        backgroundColor = .white
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for option in options {
            let button = UIButton(type: .system)
            button.setTitle(option, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 24)
            button.setTitleColor(.label, for: .normal)
            button.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }
    }

    // MARK: - Actions

    @objc private func optionTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        onSelect?(title)
        removeFromSuperview()
    }
}
