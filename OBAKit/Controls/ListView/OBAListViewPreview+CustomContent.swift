//
//  OBAListViewPreview+CustomContent.swift
//  OBAKit
//
//  Created by Alan Chu on 10/8/20.
//

import Foundation

#if DEBUG

struct DEBUG_CustomContent: OBAListViewItem {
    var text: String

    static var customCellType: OBAListViewCell.Type? {
        return DEBUG_CustomContentCell.self
    }

    var contentConfiguration: OBAContentConfiguration {
        return DEBUG_CustomContentConfiguration(text: text)
    }
}

struct DEBUG_CustomContentConfiguration: OBAContentConfiguration {
    var text: String

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return DEBUG_CustomContentCell.self
    }
}

class DEBUG_CustomContentCell: OBAListViewCell {
    var customContentView: DEBUG_CustomContentView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        customContentView = DEBUG_CustomContentView.autolayoutNew()
        contentView.addSubview(customContentView)
        customContentView.pinToSuperview(.edges)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func apply(_ config: OBAContentConfiguration) {
        customContentView.apply(config)
    }
}

class DEBUG_CustomContentView: UIView, OBAContentView {
    var label: UILabel!
    override init(frame: CGRect) {
        super.init(frame: frame)

        label = .obaLabel()
        label.textAlignment = .center

        addSubview(label)

        label.pinToSuperview(.readableContent)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ config: OBAContentConfiguration) {
        guard let customContentConfiguration = config as? DEBUG_CustomContentConfiguration else {
            fatalError("Invalid data")
        }

        label.text = customContentConfiguration.text
    }
}

#endif
