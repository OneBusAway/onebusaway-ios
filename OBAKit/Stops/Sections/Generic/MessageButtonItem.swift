//
//  MessagedButtonItem.swift
//  OBAKit
//
//  Created by Alan Chu on 2/24/21.
//

import UIKit
import OBAKitCore

/// Displays a button with optional footer text and error text.
/// With optional support for showing activity indicator on selection (see `showActivityIndicatorOnSelect` property).
struct MessageButtonItem: OBAListViewItem {
    var contentConfiguration: OBAContentConfiguration {
        return MessageButtonContentConfiguration(errorText: errorText, buttonText: buttonText, footerText: footerText, showActivityIndicatorOnSelect: showActivityIndicatorOnSelect, onTapAction: {
            onSelectAction?(self)
        })
    }
    static var customCellType: OBAListViewCell.Type? {
        return MessageButtonCell.self
    }

    var onSelectAction: OBAListViewAction<MessageButtonItem>?

    var id: String
    var errorText: String?
    var buttonText: String
    var footerText: String?

    /// When the user selects this item, the button will be replaced by an activity indicator.
    var showActivityIndicatorOnSelect: Bool

    init(id: String,
         error: Error? = nil,
         buttonText: String,
         footerText: String? = nil,
         showActivityIndicatorOnSelect: Bool,
         onSelectAction: OBAListViewAction<MessageButtonItem>? = nil) {

        self.id = id
        self.errorText = error?.localizedDescription
        self.buttonText = buttonText
        self.footerText = footerText
        self.showActivityIndicatorOnSelect = showActivityIndicatorOnSelect
        self.onSelectAction = onSelectAction
    }

    init(asLoadMoreButtonWithID id: String,
         error: Error? = nil,
         footerText: String? = nil,
         showActivityIndicatorOnSelect: Bool,
         onSelectAction: OBAListViewAction<MessageButtonItem>? = nil) {

        let loadMoreLocalized = OBALoc("stop_controller.load_more_button", value: "Load More", comment: "Load More button")
        self.init(id: id, error: error, buttonText: loadMoreLocalized, footerText: footerText, showActivityIndicatorOnSelect: showActivityIndicatorOnSelect, onSelectAction: onSelectAction)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MessageButtonItem, rhs: MessageButtonItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.errorText == rhs.errorText &&
            lhs.buttonText == rhs.buttonText &&
            lhs.footerText == rhs.footerText &&
            lhs.showActivityIndicatorOnSelect == rhs.showActivityIndicatorOnSelect
    }
}

struct MessageButtonContentConfiguration: OBAContentConfiguration {
    var formatters: Formatters?
    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return MessageButtonCell.self
    }

    var errorText: String?
    var buttonText: String
    var footerText: String?
    var showActivityIndicatorOnSelect: Bool

    var onTapAction: VoidBlock?
}

final class MessageButtonCell: OBAListViewCell {
    // MARK: - UI
    private lazy var errorLabel: UILabel = {
        let label: PaddingLabel = .obaLabel(font: .preferredFont(forTextStyle: .body), textColor: ThemeColors.shared.label)
        label.translatesAutoresizingMaskIntoConstraints = true
        label.textAlignment = .center
        label.backgroundColor = UIColor.red.withAlphaComponent(0.25)
        label.insets = UIEdgeInsets(top: ThemeMetrics.padding,
                                    left: ThemeMetrics.padding,
                                    bottom: ThemeMetrics.padding,
                                    right: ThemeMetrics.padding)
        label.cornerRadius = 8
        return label
    }()

    lazy var button: ActivityIndicatedButton = {
        let button = ActivityIndicatedButton()
        button.translatesAutoresizingMaskIntoConstraints = true
        button.isUserInteractionEnabled = false

        return button
    }()

    private lazy var footerLabel: UILabel = {
        let label: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .footnote), textColor: ThemeColors.shared.secondaryLabel)
        label.textAlignment = .center
        return label
    }()

    private lazy var stack: UIStackView = {
        let stack = UIStackView.stack(axis: .vertical,
                                      distribution: .fill,
                                      alignment: .center,
                                      arrangedSubviews: [button, footerLabel])
        stack.spacing = ThemeMetrics.padding
        stack.setCompressionResistance(horizontal: nil, vertical: .required)
        return stack
    }()

    var showActivityIndicatorOnSelect: Bool = false
    var onTapAction: VoidBlock?

    override var showsSeparator: Bool {
        return false
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(stack)

        self.showsLargeContentViewer = true
        self.addInteraction(UILargeContentViewerInteraction())

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(onSelect))
        self.addGestureRecognizer(tapGesture)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stack.pinToSuperview(.layoutMargins)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        button.prepareForReuse()
        button.config = nil
    }

    @objc func onSelect(_ sender: UITapGestureRecognizer) {
        if showActivityIndicatorOnSelect {
            button.showActivityIndicator()
        }

        onTapAction?()
    }

    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? MessageButtonContentConfiguration else { return }

        // If there is an error, add the error label to the stack view.
        // If there isn't an error, remove error label from stack view.
        if let errorText = config.errorText, !errorText.isEmpty {
            if !stack.arrangedSubviews.contains(errorLabel) {
                stack.insertArrangedSubview(errorLabel, at: 0)
            }
        } else if stack.arrangedSubviews.contains(errorLabel) {
            stack.removeArrangedSubview(errorLabel)
            errorLabel.removeFromSuperview()
        }

        errorLabel.text = config.errorText
        footerLabel.text = config.footerText

        largeContentTitle = config.buttonText

        // There is no action because the button is only for visuals.
        let buttonConfiguration = ActivityIndicatedButton.Configuration(text: config.buttonText, largeContentImage: nil, action: { })

        button.config = buttonConfiguration
        showActivityIndicatorOnSelect = config.showActivityIndicatorOnSelect
        onTapAction = config.onTapAction
    }
}
