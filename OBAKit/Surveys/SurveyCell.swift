//
//  SurveyCell.swift
//  OBAKit
//
//  Copyright Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

class SurveyCell: OBAListViewCell {

    var viewModel: SurveyStopListItem?
    private var optionButtons: [UIButton] = []
    private var currentSelection: String?

    public override func apply(_ config: OBAContentConfiguration) {
        super.apply(config)

        guard let config = config as? SurveyContentConfiguration else {
            fatalError("Invalid configuration type for SurveyCell")
        }

        viewModel = config.viewModel
        currentSelection = config.viewModel.selectedOption
        updateUI()
    }

    // MARK: - UI Components

    lazy var questionLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        return label
    }()

    lazy var optionsStack: UIStackView = {
        let stack = UIStackView.verticalStack(arrangedSubviews: [])
        stack.spacing = 8
        return stack
    }()

    lazy var dismissButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = OBALoc("survey_cell.dismiss_button", value: "Dismiss", comment: "Button to dismiss the survey")
        config.baseForegroundColor = .label
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: incoming.font?.pointSize ?? UIFont.labelFontSize, weight: .medium)
            return outgoing
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemGray4.cgColor

        let action = UIAction { [weak self] _ in
            guard let viewModel = self?.viewModel else { return }
            viewModel.onDismiss()
        }
        button.addAction(action, for: .touchUpInside)
        return button
    }()

    lazy var nextButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = OBALoc("survey_cell.next_button", value: "Next", comment: "Button to proceed to next survey question")
        config.baseBackgroundColor = .systemGreen
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 8
        button.clipsToBounds = true

        let action = UIAction { [weak self] _ in
            guard let self,
                  let viewModel = self.viewModel,
                  let selectedOption = self.currentSelection else { return }
            viewModel.onNext(selectedOption)
        }
        button.addAction(action, for: .touchUpInside)
        return button
    }()

    lazy var actionButtonsStack: UIStackView = {
        let stack = UIStackView.horizontalStack(arrangedSubviews: [dismissButton, nextButton])
        stack.spacing = ThemeMetrics.compactPadding
        stack.distribution = .fillEqually
        return stack
    }()

    lazy var contentStack: UIStackView = {
        let stack = UIStackView.verticalStack(arrangedSubviews: [
            questionLabel,
            optionsStack,
            UIView.spacerView(height: 8.0),
            actionButtonsStack
        ])
        stack.spacing = 8.0
        return stack
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemGray4.cgColor

        // Add content stack with padding
        addSubview(contentStack)
        contentStack.pinToSuperview(.edges, insets: NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: -12, trailing: -12))
    }

    // MARK: - UI Updates

    private func updateUI() {
        guard let viewModel = viewModel else { return }

        if let heroQuestion = viewModel.survey.heroQuestion {
            questionLabel.text = heroQuestion.content.displayText
            questionLabel.isHidden = false

            // Setup question-specific UI
            setupQuestionUI(for: heroQuestion)
        } else {
            questionLabel.text = OBALoc("survey_cell.default_prompt", value: "Take survey to help improve transit", comment: "Default prompt when no hero question exists")
            questionLabel.isHidden = false
            optionsStack.isHidden = true
        }

        // Update button state based on selection
        updateNextButtonState()
    }

    private func setupQuestionUI(for question: SurveyQuestion) {
        // Clear existing options
        optionButtons.forEach { $0.removeFromSuperview() }
        optionButtons.removeAll()
        optionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch question.content.type {
        case .radio:
            let options = question.content.options ?? []
            optionsStack.isHidden = false
            createRadioButtons(options: options)

        case .text:
            optionsStack.isHidden = true
            // For text questions, just show action buttons

        case .checkbox:
            let options = question.content.options ?? []
            optionsStack.isHidden = false
            createCheckboxButtons(options: Array(options.prefix(3))) // Show first 3 for space

        case .label, .externalSurvey:
            optionsStack.isHidden = true
        }
    }

    private func createRadioButtons(options: [String]) {
        for (index, option) in options.enumerated() {
            let button = createOptionButton(title: option, isRadio: true)
            button.tag = index

            // Update selection state
            if let selectedOption = viewModel?.selectedOption, selectedOption == option {
                selectButton(button)
            }

            optionButtons.append(button)
            optionsStack.addArrangedSubview(button)
        }
    }

    private func createCheckboxButtons(options: [String]) {
        for (index, option) in options.enumerated() {
            let button = createOptionButton(title: option, isRadio: false)
            button.tag = index

            optionButtons.append(button)
            optionsStack.addArrangedSubview(button)
        }
    }

    private func createOptionButton(title: String, isRadio: Bool) -> UIButton {
        let iconName = isRadio ? "circle" : "square"
        let selectedIconName = isRadio ? "circle.fill" : "checkmark.square.fill"

        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = .label
        config.image = UIImage(systemName: iconName)?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .preferredFont(forTextStyle: .body)
            return outgoing
        }

        let button = UIButton(configuration: config)
        button.configurationUpdateHandler = { btn in
            var updatedConfig = btn.configuration
            let name = btn.isSelected ? selectedIconName : iconName
            updatedConfig?.image = UIImage(systemName: name)?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
            btn.configuration = updatedConfig
        }
        button.contentHorizontalAlignment = .leading
        button.backgroundColor = .systemGray6
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemGray4.cgColor

        let action = UIAction { [weak self] _ in
            if isRadio {
                self?.handleRadioSelection(button)
            } else {
                self?.handleCheckboxSelection(button)
            }
        }
        button.addAction(action, for: .touchUpInside)

        return button
    }

    private func handleRadioSelection(_ selectedButton: UIButton) {
        // Deselect all other radio buttons
        optionButtons.forEach { button in
            if button != selectedButton {
                deselectButton(button)
            }
        }

        // Select this button
        selectButton(selectedButton)

        guard let selectedTitle = selectedButton.titleLabel?.text, !selectedTitle.isEmpty else {
            Logger.error("handleRadioSelection: button has no title, cannot record selection")
            return
        }

        currentSelection = selectedTitle
        viewModel?.onSelectionChanged(selectedTitle)
        updateNextButtonState()
    }

    private func handleCheckboxSelection(_ button: UIButton) {
        button.isSelected.toggle()

        if button.isSelected {
            selectButton(button)
        } else {
            deselectButton(button)
        }

        // Build current selection from all selected checkboxes
        let selectedTitles = optionButtons
            .filter { $0.isSelected }
            .compactMap { $0.titleLabel?.text }
        currentSelection = selectedTitles.isEmpty ? nil : SurveyService.formatCheckboxAnswer(selectedTitles)
        viewModel?.onSelectionChanged(currentSelection)
        updateNextButtonState()
    }

    private func selectButton(_ button: UIButton) {
        button.isSelected = true
        button.backgroundColor = .systemGreen.withAlphaComponent(0.15)
        button.layer.borderColor = UIColor.systemGreen.cgColor
    }

    private func deselectButton(_ button: UIButton) {
        button.isSelected = false
        button.backgroundColor = .systemGray6
        button.layer.borderColor = UIColor.systemGray4.cgColor
    }

    private func updateNextButtonState() {
        let hasSelection = currentSelection != nil
        nextButton.isEnabled = hasSelection
        nextButton.configurationUpdateHandler = { btn in
            var config = btn.configuration
            config?.baseBackgroundColor = .systemGreen
            config?.baseForegroundColor = .white
            btn.configuration = config
            btn.alpha = btn.isEnabled ? 1.0 : 0.5
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.borderColor = UIColor.systemGray4.cgColor
            dismissButton.layer.borderColor = UIColor.systemGray4.cgColor
            for button in optionButtons {
                if button.isSelected {
                    button.layer.borderColor = UIColor.systemGreen.cgColor
                } else {
                    button.layer.borderColor = UIColor.systemGray4.cgColor
                }
            }
        }
    }
}
