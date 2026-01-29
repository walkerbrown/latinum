import UIKit

/// Delegate protocol for prediction bar
protocol PredictionBarViewDelegate: AnyObject {
    func predictionBarView(_ view: PredictionBarView, didSelectPrediction prediction: String)
}

/// View displaying prediction suggestions above the keyboard
class PredictionBarView: UIView {

    // MARK: - Properties

    weak var delegate: PredictionBarViewDelegate?

    private let stackView = UIStackView()
    private var predictionButtons: [UIButton] = []

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
        backgroundColor = UIColor.systemGray6

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

        // Create three prediction buttons
        for i in 0..<3 {
            let button = createPredictionButton()
            button.tag = i
            predictionButtons.append(button)
            stackView.addArrangedSubview(button)

            // Add separator except after last
            if i < 2 {
                let separator = UIView()
                separator.backgroundColor = UIColor.systemGray4
                separator.widthAnchor.constraint(equalToConstant: 0.5).isActive = true
                stackView.addArrangedSubview(separator)
            }
        }
    }

    private func createPredictionButton() -> UIButton {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        button.setTitleColor(.label, for: .normal)
        button.addTarget(self, action: #selector(predictionTapped(_:)), for: .touchUpInside)
        return button
    }

    // MARK: - Actions

    @objc private func predictionTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal), !title.isEmpty else { return }
        delegate?.predictionBarView(self, didSelectPrediction: title)
    }

    // MARK: - Public Methods

    func updatePredictions(_ predictions: [String]) {
        for (index, button) in predictionButtons.enumerated() {
            if index < predictions.count {
                button.setTitle(predictions[index], for: .normal)
                button.isHidden = false
            } else {
                button.setTitle(nil, for: .normal)
                button.isHidden = false
            }
        }
    }
}
