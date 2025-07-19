import UIKit

/// Simple survey view controller using common UI elements.
class SurveyViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])

        configureQuestions()
    }

    // MARK: - UI Setup
    private func configureQuestions() {
        // Question 1: radio buttons
        let radioLabel = UILabel()
        radioLabel.text = "Travel purpose"
        radioLabel.font = .preferredFont(forTextStyle: .headline)
        contentStack.addArrangedSubview(radioLabel)

        let commuteButton = makeRadioButton(title: "Commute")
        let leisureButton = makeRadioButton(title: "Leisure")
        let otherButton = makeRadioButton(title: "Other")
        let radioStack = UIStackView(arrangedSubviews: [commuteButton, leisureButton, otherButton])
        radioStack.axis = .vertical
        radioStack.spacing = 8
        contentStack.addArrangedSubview(radioStack)

        // Question 2: checkboxes
        let checkLabel = UILabel()
        checkLabel.text = "Improvements you want"
        checkLabel.font = .preferredFont(forTextStyle: .headline)
        contentStack.addArrangedSubview(checkLabel)

        let reliabilityCheck = makeCheckbox(title: "Reliability")
        let cleanlinessCheck = makeCheckbox(title: "Cleanliness")
        let seatingCheck = makeCheckbox(title: "More seating")
        let checkStack = UIStackView(arrangedSubviews: [reliabilityCheck, cleanlinessCheck, seatingCheck])
        checkStack.axis = .vertical
        checkStack.spacing = 8
        contentStack.addArrangedSubview(checkStack)

        // Question 3: text field
        let textLabel = UILabel()
        textLabel.text = "Additional comments"
        textLabel.font = .preferredFont(forTextStyle: .headline)
        contentStack.addArrangedSubview(textLabel)

        let textField = UITextField()
        textField.borderStyle = .roundedRect
        contentStack.addArrangedSubview(textField)
    }

    // MARK: - Helpers
    private func makeRadioButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: "circle"), for: .normal)
        button.setImage(UIImage(systemName: "largecircle.fill.circle"), for: .selected)
        button.addTarget(self, action: #selector(toggleRadioButton(_:)), for: .touchUpInside)
        button.contentHorizontalAlignment = .leading
        return button
    }

    private func makeCheckbox(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: "square"), for: .normal)
        button.setImage(UIImage(systemName: "checkmark.square"), for: .selected)
        button.addTarget(self, action: #selector(toggleCheckBox(_:)), for: .touchUpInside)
        button.contentHorizontalAlignment = .leading
        return button
    }

    // MARK: - Actions
    @objc private func toggleRadioButton(_ sender: UIButton) {
        for case let button as UIButton in (sender.superview?.subviews ?? []) {
            button.isSelected = (button == sender)
        }
    }

    @objc private func toggleCheckBox(_ sender: UIButton) {
        sender.isSelected.toggle()
    }
}
