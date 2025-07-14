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

  public override func apply(_ config: OBAContentConfiguration) {
      super.apply(config)

      guard let config = config as? SurveyContentConfiguration else {
          fatalError("Invalid configuration type for SurveyCell")
      }
      
      viewModel = config.viewModel
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
  
  lazy var closeButton: UIButton = {
      let button = UIButton.buildCloseButton()
      button.tintColor = .systemGreen
      let action = UIAction { [weak self] _ in
          guard let viewModel = self?.viewModel else { return }
          viewModel.onDismiss()
      }
      button.addAction(action, for: .touchUpInside)
      return button
  }()
  
  lazy var closeButtonWrapper: UIView = {
      let wrapper = closeButton.embedInWrapperView(setConstraints: false)
      NSLayoutConstraint.activate([
          closeButton.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
          closeButton.topAnchor.constraint(equalTo: wrapper.topAnchor),
          closeButton.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
          wrapper.heightAnchor.constraint(greaterThanOrEqualTo: closeButton.heightAnchor)
      ])
      return wrapper
  }()
  
  // Removed headerRow from original code
  lazy var optionsStack: UIStackView = {
      let stack = UIStackView.verticalStack(arrangedSubviews: [])
      stack.spacing = 8
      return stack
  }()
  
  lazy var nextButton: UIButton = {
      let button = UIButton(configuration: .filled())
      button.translatesAutoresizingMaskIntoConstraints = false
      button.setTitle("Next", for: .normal)
      button.backgroundColor = .systemGreen
      button.layer.cornerRadius = 8
      
      let action = UIAction { [weak self] _ in
          guard let viewModel = self?.viewModel,
                let selectedOption = viewModel.selectedOption else { return }
          viewModel.onNext(selectedOption)
      }
      button.addAction(action, for: .touchUpInside)
      return button
  }()
  
  lazy var actionButtonsStack: UIStackView = {
      let stack = UIStackView.horizontalStack(arrangedSubviews: [nextButton])
      stack.spacing = ThemeMetrics.compactPadding
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
      
      // Add close button positioned in top-right corner (like donation section)
      addSubview(closeButton)
      NSLayoutConstraint.activate([
          closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
          closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
      ])
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
          questionLabel.text = "Take survey to help improve transit"
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
      
      switch question.content {
      case .radio(_, let options):
          optionsStack.isHidden = false
          createRadioButtons(options: options)
          
      case .text:
          optionsStack.isHidden = true
          // For text questions, just show action buttons
          
      case .checkbox(_, let options):
          optionsStack.isHidden = false
          createCheckboxButtons(options: Array(options.prefix(3))) // Show first 3 for space
          
      case .label:
          optionsStack.isHidden = true
      }
  }
  
  private func createRadioButtons(options: [String]) {
      for (index, option) in options.enumerated() {
          let button = createOptionButton(title: option, isRadio: true)
          button.tag = index
          
          // Update selection state
          if let selectedOption = viewModel?.selectedOption, selectedOption == option {
              selectButton(button, isRadio: true)
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
      let button = UIButton(type: .system)
      
      // Configure button appearance
      button.backgroundColor = .systemGray6
      button.layer.cornerRadius = 8
      button.layer.borderWidth = 1
      button.layer.borderColor = UIColor.systemGray4.cgColor
      button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
      
      // Configure text - ensure no background styling
      button.setTitle(title, for: .normal)
      button.setTitle(title, for: .selected)
      button.setTitleColor(.label, for: .normal)
      button.setTitleColor(.label, for: .selected)
      button.titleLabel?.backgroundColor = .clear
      button.titleLabel?.numberOfLines = 0
      button.titleLabel?.font = .preferredFont(forTextStyle: .body)
      button.contentHorizontalAlignment = .leading
      
      // Remove any default button styling that might affect text
      button.configuration = nil
      button.titleLabel?.layer.backgroundColor = UIColor.clear.cgColor
      
      // Add radio/checkbox indicator
      let iconName = isRadio ? "circle" : "square"
      let selectedIconName = isRadio ? "circle.fill" : "checkmark.square.fill"
      
      // Normal state: green outline circle
      let normalIcon = UIImage(systemName: iconName)?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
      // Selected state: green filled circle
      let selectedIcon = UIImage(systemName: selectedIconName)?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
      
      button.setImage(normalIcon, for: .normal)
      button.setImage(selectedIcon, for: .selected)
      
      // Ensure proper spacing between icon and text
      button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
      button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
      
      // Add action
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
      guard let viewModel = viewModel else { return }
      
      // Deselect all other radio buttons
      optionButtons.forEach { button in
          if button != selectedButton {
              deselectButton(button, isRadio: true)
          }
      }
      
      // Select this button
      selectButton(selectedButton, isRadio: true)
      
      // Get the selected option
      let selectedTitle = selectedButton.titleLabel?.text ?? ""
      
      // Update view model
      viewModel.onSelectionChanged(selectedTitle)
      
      // Update button state
      updateNextButtonState()
  }
  
  private func handleCheckboxSelection(_ button: UIButton) {
      button.isSelected.toggle()
      
      if button.isSelected {
          selectButton(button, isRadio: false)
      } else {
          deselectButton(button, isRadio: false)
      }
      
      // For now, just handle single selection for checkboxes too
      let selectedTitle = button.titleLabel?.text ?? ""
      if button.isSelected {
          viewModel?.onSelectionChanged(selectedTitle)
      }
      
      // Update button state
      updateNextButtonState()
  }
  
  private func selectButton(_ button: UIButton, isRadio: Bool) {
      button.isSelected = true
      button.backgroundColor = .systemGreen.withAlphaComponent(0.15)
      button.layer.borderColor = UIColor.systemGreen.cgColor
  }
  
  private func deselectButton(_ button: UIButton, isRadio: Bool) {
      button.isSelected = false
      button.backgroundColor = .systemGray6
      button.layer.borderColor = UIColor.systemGray4.cgColor
  }
  
  private func updateNextButtonState() {
      guard let viewModel = viewModel else { return }
      
      // Enable next button only if an option is selected
      let hasSelection = viewModel.selectedOption != nil
      nextButton.isEnabled = hasSelection
      nextButton.alpha = hasSelection ? 1.0 : 0.6
  }
}
