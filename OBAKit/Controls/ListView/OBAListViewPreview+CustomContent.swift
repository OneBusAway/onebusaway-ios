//
//  OBAListViewPreview+CustomContent.swift
//  OBAKit
//
//  Created by Alan Chu on 10/8/20.
//

import Foundation

#if DEBUG

struct DEBUG_Person: OBAListViewItem {
    var id: UUID = UUID()
    var name: String
    var address: String

    var onSelectAction: OBAListViewAction<DEBUG_Person>? = nil

    var contentConfiguration: OBAContentConfiguration {
        return OBAListRowConfiguration(image: UIImage(systemName: "person.fill"), text: name, secondaryText: address, appearance: .subtitle, accessoryType: .disclosureIndicator)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DEBUG_Person, rhs: DEBUG_Person) -> Bool {
        return lhs.name == rhs.name &&
            lhs.address == rhs.address
    }
}

struct DEBUG_CustomContent: OBAListViewItem {
    var text: String
    var onSelectAction: OBAListViewAction<DEBUG_CustomContent>? = nil

    static var customCellType: OBAListViewCell.Type? {
        return DEBUG_CustomContentCell.self
    }

    var trailingContextualActions: [OBAListViewContextualAction<DEBUG_CustomContent>]? {
        let action = OBAListViewContextualAction<DEBUG_CustomContent>(style: .normal, title: "Hello", image: nil, backgroundColor: .systemPurple, handler: { item in
            print(item)
        })

        return [action]
    }

    var contentConfiguration: OBAContentConfiguration {
        return DEBUG_CustomContentConfiguration(text: text)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }

    static func == (lhs: DEBUG_CustomContent, rhs: DEBUG_CustomContent) -> Bool {
        return lhs.text == rhs.text
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
