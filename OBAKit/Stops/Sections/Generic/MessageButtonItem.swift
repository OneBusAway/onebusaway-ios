//
//  MessagedButtonItem.swift
//  OBAKit
//
//  Created by Alan Chu on 2/24/21.
//

import UIKit
import OBAKitCore

/// Displays a button with optional support for showing activity indicator on selection (see `showActivityIndicatorOnSelect` property).
struct MessageButtonItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(MessageButtonContentConfiguration(buttonText: buttonText, showActivityIndicatorOnSelect: showActivityIndicatorOnSelect, onTapAction: {
            onSelectAction?(self)
        }))
    }

    static var customCellType: OBAListViewCell.Type? {
        return MessageButtonCell.self
    }

    let separatorConfiguration: OBAListRowSeparatorConfiguration = .hidden()

    var onSelectAction: OBAListViewAction<MessageButtonItem>?

    var id: String
    var buttonText: String

    /// When the user selects this item, the button will be replaced by an activity indicator.
    var showActivityIndicatorOnSelect: Bool

    init(id: String,
         buttonText: String,
         showActivityIndicatorOnSelect: Bool,
         onSelectAction: OBAListViewAction<MessageButtonItem>? = nil) {

        self.id = id
        self.buttonText = buttonText
        self.showActivityIndicatorOnSelect = showActivityIndicatorOnSelect
        self.onSelectAction = onSelectAction
    }

    init(asLoadMoreButtonWithID id: String,
         showActivityIndicatorOnSelect: Bool,
         onSelectAction: OBAListViewAction<MessageButtonItem>? = nil) {

        let loadMoreLocalized = OBALoc("stop_controller.load_more_button", value: "Load More", comment: "Load More button")
        self.init(id: id, buttonText: loadMoreLocalized, showActivityIndicatorOnSelect: showActivityIndicatorOnSelect, onSelectAction: onSelectAction)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MessageButtonItem, rhs: MessageButtonItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.buttonText == rhs.buttonText &&
            lhs.showActivityIndicatorOnSelect == rhs.showActivityIndicatorOnSelect
    }
}

struct MessageButtonContentConfiguration: OBAContentConfiguration {
    var formatters: Formatters?
    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return MessageButtonCell.self
    }

    var buttonText: String
    var showActivityIndicatorOnSelect: Bool

    var onTapAction: VoidBlock?
}

final class MessageButtonCell: OBAListViewCell {
    lazy var button: ActivityIndicatedButton = {
        let button = ActivityIndicatedButton()
        button.translatesAutoresizingMaskIntoConstraints = true
        button.isUserInteractionEnabled = false

        return button
    }()

    var showActivityIndicatorOnSelect: Bool = false
    var onTapAction: VoidBlock?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(button)

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
        button.pinToSuperview(.layoutMargins)
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

        largeContentTitle = config.buttonText

        // There is no action because the button is only for visuals.
        let buttonConfiguration = ActivityIndicatedButton.Configuration(text: config.buttonText, largeContentImage: nil, action: { })

        button.config = buttonConfiguration
        showActivityIndicatorOnSelect = config.showActivityIndicatorOnSelect
        onTapAction = config.onTapAction
    }
}
