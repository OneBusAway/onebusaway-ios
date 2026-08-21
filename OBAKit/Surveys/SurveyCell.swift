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

    /// Whether the hero question collects an answer inside the card. A `.label`
    /// hero is display-only — no option to pick, no field to fill in — so it is
    /// answerable without a selection.
    private var heroCollectsAnswer = true

    /// The answer a Next tap would submit, or `nil` while the hero question is
    /// still unanswered. A display-only hero answers with an empty string;
    /// without that, `Next` was gated on a selection that could never arrive and
    /// stayed permanently disabled.
    private var pendingAnswer: String? {
        if let currentSelection { return currentSelection }
        return heroCollectsAnswer ? nil : ""
    }

    public override func apply(_ config: OBAContentConfiguration) {
        super.apply(config)

        guard let config = config as? SurveyContentConfiguration else {
            fatalError("Invalid configuration type for SurveyCell")
        }

        viewModel = config.viewModel
        currentSelection = config.viewModel.selectedOption
        updateUI()
    }

    // MARK: - Metrics

    private enum Metrics {
        /// Matches `SurveyLauncherCardView`'s grouped card so the two survey
        /// surfaces read as the same component.
        static let cardRadius: CGFloat = 16.0
        static let cardPadding: CGFloat = 16.0
        static let optionRadius: CGFloat = 10.0
        static let hairline: CGFloat = 1.0

        // Icon tile, also lifted from `SurveyLauncherCardView`.
        static let tileSize: CGFloat = 42.0
        static let tileRadius: CGFloat = 10.0
        static let tileGlyphPointSize: CGFloat = 20.0
        static let tileTextGap: CGFloat = 14.0
        /// Ceilings for the scaled tile. Left uncapped, an AX5 tile is wide
        /// enough to leave the question a single word per line.
        static let maxTileSize: CGFloat = 72.0
        static let maxTileGlyphPointSize: CGFloat = 34.0
    }

    // MARK: - UI Components

    /// The rounded card the content sits in. The cell itself stays transparent:
    /// it spans the full row width, so drawing the card chrome on the cell drew
    /// a hairline across the whole screen instead of a card.
    private lazy var cardView: UIView = {
        let view = UIView.autolayoutNew()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = Metrics.cardRadius
        view.layer.cornerCurve = .continuous
        return view
    }()

    /// Brand-filled tile carrying the survey glyph. Decorative — the question
    /// text alongside it already says what the card is.
    private let iconTile: UIView = {
        let view = UIView.autolayoutNew()
        view.backgroundColor = ThemeColors.shared.brand
        view.layer.cornerRadius = Metrics.tileRadius
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let tileGlyph: UIImageView = {
        let symbol = UIImage(
            systemName: "questionmark.bubble",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.tileGlyphPointSize, weight: .semibold)
        )
        let imageView = UIImageView(image: symbol)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    lazy var questionLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    /// Held so `updateTileSize()` can rescale the tile when the user's text size
    /// changes; the tile is square, so both constraints share one constant.
    private lazy var tileSizeConstraints: [NSLayoutConstraint] = [
        iconTile.widthAnchor.constraint(equalToConstant: Metrics.tileSize),
        iconTile.heightAnchor.constraint(equalToConstant: Metrics.tileSize)
    ]

    /// Tile and question side by side. The tile keeps its square footprint while
    /// the question takes the rest of the width and wraps.
    private lazy var headerRow: UIStackView = {
        let stack = UIStackView.horizontalStack(arrangedSubviews: [iconTile, questionLabel])
        stack.spacing = Metrics.tileTextGap
        stack.alignment = .center
        return stack
    }()

    lazy var optionsStack: UIStackView = {
        let stack = UIStackView.verticalStack(arrangedSubviews: [])
        stack.spacing = ThemeMetrics.padding
        return stack
    }()

    /// Borderless and secondary: dismissing is the low-emphasis action, and the
    /// bordered half-width box it used to be competed with `Next`.
    lazy var dismissButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = OBALoc("survey_cell.dismiss_button", value: "Dismiss", comment: "Button to dismiss the survey")
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 12)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)

        let action = UIAction { [weak self] _ in
            guard let viewModel = self?.viewModel else { return }
            viewModel.onDismiss()
        }
        button.addAction(action, for: .touchUpInside)
        return button
    }()

    lazy var nextButton: UIButton = {
        let button = SurveyCell.prominentButton(
            title: OBALoc("survey_cell.next_button", value: "Next", comment: "Button to proceed to next survey question")
        )

        let action = UIAction { [weak self] _ in
            guard let self,
                  let viewModel = self.viewModel,
                  let answer = self.pendingAnswer else { return }
            viewModel.onNext(answer)
        }
        button.addAction(action, for: .touchUpInside)
        return button
    }()

    lazy var externalSurveyButton: UIButton = {
        let button = SurveyCell.prominentButton(
            title: OBALoc("survey_cell.open_external_survey_button", value: "Open Survey", comment: "Button that opens an external survey in the browser")
        )
        button.isHidden = true

        let action = UIAction { [weak self] _ in
            self?.viewModel?.onOpenExternalSurvey()
        }
        button.addAction(action, for: .touchUpInside)
        return button
    }()

    /// Dismiss trailing-aligned next to the call to action rather than splitting
    /// the card in half: the spacer takes the slack so both buttons keep their
    /// intrinsic width. `Next` and `Open Survey` are mutually exclusive, so they
    /// share the slot and every question type gets the same single action row.
    lazy var actionButtonsStack: UIStackView = {
        let spacer = UIView.autolayoutNew()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = UIStackView.horizontalStack(arrangedSubviews: [spacer, dismissButton, nextButton, externalSurveyButton])
        stack.spacing = ThemeMetrics.compactPadding
        stack.alignment = .center
        return stack
    }()

    lazy var contentStack: UIStackView = {
        let stack = UIStackView.verticalStack(arrangedSubviews: [
            headerRow,
            optionsStack,
            actionButtonsStack
        ])
        stack.spacing = ThemeMetrics.padding
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
        backgroundColor = .clear

        addSubview(cardView)
        cardView.pinToSuperview(.edges)

        let padding = Metrics.cardPadding
        iconTile.addSubview(tileGlyph)
        cardView.addSubview(contentStack)
        contentStack.pinToSuperview(.edges, insets: NSDirectionalEdgeInsets(top: padding, leading: padding, bottom: -padding, trailing: -padding))

        NSLayoutConstraint.activate(tileSizeConstraints + [
            tileGlyph.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            tileGlyph.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor)
        ])
        updateTileSize()

        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (self: SurveyCell, _: UITraitCollection) in
            for button in self.optionButtons {
                button.layer.borderColor = SurveyCell.optionBorderColor(isSelected: button.isSelected)
            }
        }

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: SurveyCell, _: UITraitCollection) in
            self.updateTileSize()
        }
    }

    /// Grows the tile alongside the question text. A fixed 42pt tile shrinks into
    /// a bullet next to accessibility-size text, which reads as a rendering bug.
    private func updateTileSize() {
        let metrics = UIFontMetrics(forTextStyle: .headline)
        let side = min(metrics.scaledValue(for: Metrics.tileSize, compatibleWith: traitCollection), Metrics.maxTileSize)
        for constraint in tileSizeConstraints {
            constraint.constant = side
        }

        let glyphPointSize = min(
            metrics.scaledValue(for: Metrics.tileGlyphPointSize, compatibleWith: traitCollection),
            Metrics.maxTileGlyphPointSize
        )
        tileGlyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold)
    }

    // MARK: - Factories

    /// The card's filled call-to-action buttons. `UIButton.Configuration` rounds
    /// its own background, so the buttons carry no `layer.cornerRadius` — setting
    /// both left the configuration's radius fighting the layer's.
    private static func prominentButton(title: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = ThemeColors.shared.brand
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private static func optionBorderColor(isSelected: Bool) -> CGColor {
        isSelected ? ThemeColors.shared.brand.cgColor : UIColor.separator.cgColor
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

        externalSurveyButton.isHidden = true
        nextButton.isHidden = false
        heroCollectsAnswer = true

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

        case .label:
            optionsStack.isHidden = true
            heroCollectsAnswer = false

        case .externalSurvey:
            optionsStack.isHidden = true
            nextButton.isHidden = true
            externalSurveyButton.isHidden = false
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

        let brand = ThemeColors.shared.brand

        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = .label
        config.image = UIImage(systemName: iconName)?.withTintColor(brand, renderingMode: .alwaysOriginal)
        config.imagePadding = ThemeMetrics.padding
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .preferredFont(forTextStyle: .body)
            return outgoing
        }

        let button = UIButton(configuration: config)
        button.configurationUpdateHandler = { btn in
            var updatedConfig = btn.configuration
            let name = btn.isSelected ? selectedIconName : iconName
            updatedConfig?.image = UIImage(systemName: name)?.withTintColor(brand, renderingMode: .alwaysOriginal)
            btn.configuration = updatedConfig
        }
        button.contentHorizontalAlignment = .leading
        // Filled with the page background rather than a gray: the card is already
        // `secondarySystemBackground`, so a gray-on-gray row had no edge.
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = Metrics.optionRadius
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = Metrics.hairline
        button.layer.borderColor = SurveyCell.optionBorderColor(isSelected: false)

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
        currentSelection = selectedTitles.isEmpty ? nil : (try? SurveyService.formatCheckboxAnswer(selectedTitles))
        viewModel?.onSelectionChanged(currentSelection)
        updateNextButtonState()
    }

    private func selectButton(_ button: UIButton) {
        button.isSelected = true
        button.backgroundColor = ThemeColors.shared.brand.withAlphaComponent(0.12)
        button.layer.borderColor = SurveyCell.optionBorderColor(isSelected: true)
    }

    private func deselectButton(_ button: UIButton) {
        button.isSelected = false
        button.backgroundColor = .systemBackground
        button.layer.borderColor = SurveyCell.optionBorderColor(isSelected: false)
    }

    private func updateNextButtonState() {
        nextButton.isEnabled = pendingAnswer != nil
    }

}
