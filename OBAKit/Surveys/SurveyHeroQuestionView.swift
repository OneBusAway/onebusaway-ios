// OBAKit/Surveys/SurveyHeroQuestionView.swift
//
//  SurveyHeroQuestionView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

public class SurveyHeroQuestionView: UIView {
    
    private let survey: Survey
    private let onAnswer: (String) -> Void
    private let onMoreQuestions: () -> Void
    private let onAnswerLater: () -> Void
    private let onDismiss: () -> Void
    
    private var stackView: UIStackView!
    private var questionLabel: UILabel!
    private var optionsContainer: UIView!
    private var selectedRadioButton: UIButton?
    
    public init(
        survey: Survey,
        onAnswer: @escaping (String) -> Void,
        onMoreQuestions: @escaping () -> Void,
        onAnswerLater: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.survey = survey
        self.onAnswer = onAnswer
        self.onMoreQuestions = onMoreQuestions
        self.onAnswerLater = onAnswerLater
        self.onDismiss = onDismiss
        
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        
        setupStackView()
        setupContent()
    }
    
    private func setupStackView() {
        stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }
    
    private func setupContent() {
        guard let heroQuestion = survey.heroQuestion else { return }
        
        // Header with survey title and close button
        let headerView = createHeaderView()
        stackView.addArrangedSubview(headerView)
        
        // Question text
        questionLabel = UILabel()
        questionLabel.text = heroQuestion.content.displayText
        questionLabel.font = .systemFont(ofSize: 16, weight: .medium)
        questionLabel.numberOfLines = 0
        questionLabel.textColor = .label
        stackView.addArrangedSubview(questionLabel)
        
        // Question options
        optionsContainer = UIView()
        setupQuestionOptions(heroQuestion)
        stackView.addArrangedSubview(optionsContainer)
        
        // Action buttons
        let buttonStack = createActionButtons()
        stackView.addArrangedSubview(buttonStack)
    }
    
    private func createHeaderView() -> UIView {
        let headerView = UIView()
        
        let titleLabel = UILabel()
        titleLabel.text = survey.name
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .systemGray3
        closeButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        
        headerView.addSubview(titleLabel)
        headerView.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            
            closeButton.topAnchor.constraint(equalTo: headerView.topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        return headerView
    }
    
    private func setupQuestionOptions(_ question: SurveyQuestion) {
        let optionsStack = UIStackView()
        optionsStack.axis = .vertical
        optionsStack.spacing = 8
        optionsStack.translatesAutoresizingMaskIntoConstraints = false
        
        switch question.content {
        case .radio(_, let options):
            for option in options {
                let button = createRadioButton(title: option)
                optionsStack.addArrangedSubview(button)
            }
            
        case .text:
            let textField = createTextInputField()
            optionsStack.addArrangedSubview(textField)
            
        case .checkbox(_, let options):
            // For hero questions, we'll show first few options only
            let limitedOptions = Array(options.prefix(3))
            for option in limitedOptions {
                let button = createCheckboxButton(title: option)
                optionsStack.addArrangedSubview(button)
            }
            
            if options.count > 3 {
                let moreLabel = UILabel()
                moreLabel.text = "...and \(options.count - 3) more options"
                moreLabel.font = .systemFont(ofSize: 14)
                moreLabel.textColor = .secondaryLabel
                optionsStack.addArrangedSubview(moreLabel)
            }
            
        case .label:
            // Labels don't need interaction options
            break
        }
        
        optionsContainer.addSubview(optionsStack)
        
        NSLayoutConstraint.activate([
            optionsStack.topAnchor.constraint(equalTo: optionsContainer.topAnchor),
            optionsStack.leadingAnchor.constraint(equalTo: optionsContainer.leadingAnchor),
            optionsStack.trailingAnchor.constraint(equalTo: optionsContainer.trailingAnchor),
            optionsStack.bottomAnchor.constraint(equalTo: optionsContainer.bottomAnchor)
        ])
    }
    
    private func createRadioButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.setTitleColor(.systemBlue, for: .selected)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.backgroundColor = .systemGray6
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemGray4.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        
        // Add radio button indicator
        let radioImage = UIImage(systemName: "circle")
        let radioSelectedImage = UIImage(systemName: "circle.fill")
        button.setImage(radioImage, for: .normal)
        button.setImage(radioSelectedImage, for: .selected)
        button.tintColor = .systemBlue
        
        button.addTarget(self, action: #selector(radioButtonTapped(_:)), for: .touchUpInside)
        
        return button
    }
    
    private func createCheckboxButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.setTitleColor(.systemBlue, for: .selected)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.backgroundColor = .systemGray6
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemGray4.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        
        // Add checkbox indicator
        let checkboxImage = UIImage(systemName: "square")
        let checkboxSelectedImage = UIImage(systemName: "checkmark.square.fill")
        button.setImage(checkboxImage, for: .normal)
        button.setImage(checkboxSelectedImage, for: .selected)
        button.tintColor = .systemBlue
        
        button.addTarget(self, action: #selector(checkboxButtonTapped(_:)), for: .touchUpInside)
        
        return button
    }
    
    private func createTextInputField() -> UITextField {
        let textField = UITextField()
        textField.borderStyle = .roundedRect
        textField.placeholder = "Enter your answer..."
        textField.font = .systemFont(ofSize: 15)
        textField.addTarget(self, action: #selector(textFieldChanged(_:)), for: .editingChanged)
        
        return textField
    }
    
    private func createActionButtons() -> UIStackView {
        let buttonStack = UIStackView()
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 12
        
        let moreButton = UIButton(type: .system)
        moreButton.setTitle("More Questions", for: .normal)
        moreButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        moreButton.backgroundColor = .systemBlue
        moreButton.setTitleColor(.white, for: .normal)
        moreButton.layer.cornerRadius = 8
        moreButton.addTarget(self, action: #selector(moreQuestionsTapped), for: .touchUpInside)
        
        let laterButton = UIButton(type: .system)
        laterButton.setTitle("Later", for: .normal)
        laterButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        laterButton.backgroundColor = .systemGray5
        laterButton.setTitleColor(.label, for: .normal)
        laterButton.layer.cornerRadius = 8
        laterButton.addTarget(self, action: #selector(answerLaterTapped), for: .touchUpInside)
        
        buttonStack.addArrangedSubview(moreButton)
        buttonStack.addArrangedSubview(laterButton)
        
        // Set button heights
        moreButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        laterButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        return buttonStack
    }
    
    @objc private func radioButtonTapped(_ sender: UIButton) {
        // Deselect previous button
        selectedRadioButton?.isSelected = false
        selectedRadioButton?.backgroundColor = .systemGray6
        selectedRadioButton?.layer.borderColor = UIColor.systemGray4.cgColor
        
        // Select new button
        sender.isSelected = true
        sender.backgroundColor = .systemBlue.withAlphaComponent(0.1)
        sender.layer.borderColor = UIColor.systemBlue.cgColor
        selectedRadioButton = sender
        
        guard let title = sender.titleLabel?.text else { return }
        onAnswer(title)
    }
    
    @objc private func checkboxButtonTapped(_ sender: UIButton) {
        sender.isSelected.toggle()
        
        if sender.isSelected {
            sender.backgroundColor = .systemBlue.withAlphaComponent(0.1)
            sender.layer.borderColor = UIColor.systemBlue.cgColor
        } else {
            sender.backgroundColor = .systemGray6
            sender.layer.borderColor = UIColor.systemGray4.cgColor
        }
        
        // For hero questions, we'll handle single selection for simplicity
        guard let title = sender.titleLabel?.text else { return }
        if sender.isSelected {
            onAnswer(title)
        }
    }
    
    @objc private func textFieldChanged(_ sender: UITextField) {
        guard let text = sender.text, !text.isEmpty else { return }
        onAnswer(text)
    }
    
    @objc private func moreQuestionsTapped() {
        onMoreQuestions()
    }
    
    @objc private func answerLaterTapped() {
        onAnswerLater()
    }
    
    @objc private func dismissTapped() {
        onDismiss()
    }
}

// MARK: - Animation Extensions
extension SurveyHeroQuestionView {
    
    /// Animate the view sliding in from the bottom
    public func animateIn() {
        transform = CGAffineTransform(translationX: 0, y: 100)
        alpha = 0
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            self.transform = .identity
            self.alpha = 1
        }
    }
    
    /// Animate the view sliding out to the bottom
    public func animateOut(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn) {
            self.transform = CGAffineTransform(translationX: 0, y: 100)
            self.alpha = 0
        } completion: { _ in
            completion()
        }
    }
}
