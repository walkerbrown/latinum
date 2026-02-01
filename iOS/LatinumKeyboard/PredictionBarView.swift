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
    private var labels: [UILabel] = []
    private var separators: [UIView] = []

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
        // Near-transparent background required for gesture recognition (UIKit quirk)
        backgroundColor = UIColor.clear.withAlphaComponent(0.01)

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Create three tappable areas with centered labels
        for i in 0..<3 {
            let container = UIView()
            container.tag = i
            container.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))

            let label = UILabel()
            label.font = .systemFont(ofSize: 19)
            label.textColor = .label
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -2),
            ])

            stackView.addArrangedSubview(container)
            labels.append(label)
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
            addSubview(separator)
            separators.append(separator)

            NSLayoutConstraint.activate([
                separator.trailingAnchor.constraint(equalTo: stackView.arrangedSubviews[i].trailingAnchor),
                separator.centerYAnchor.constraint(equalTo: centerYAnchor),
                separator.widthAnchor.constraint(equalToConstant: 1),
                separator.heightAnchor.constraint(equalToConstant: 22),
            ])
        }
    }

    // MARK: - Actions

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag,
              let text = labels[index].text,
              !text.isEmpty else { return }
        delegate?.predictionBarView(self, didSelectPrediction: text)
    }

    // MARK: - Public Methods

    func updatePredictions(_ predictions: [String]) {
        for (i, label) in labels.enumerated() {
            label.text = i < predictions.count ? predictions[i] : nil
        }

        // Show separators only between adjacent predictions
        for (i, separator) in separators.enumerated() {
            let hasLeft = labels[i].text?.isEmpty == false
            let hasRight = labels[i + 1].text?.isEmpty == false
            separator.isHidden = !(hasLeft && hasRight)
        }
    }
}
