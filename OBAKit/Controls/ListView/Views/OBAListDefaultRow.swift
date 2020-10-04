//
//  OBAListViewRow.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

import UIKit

// MARK: - iOS 14+
@available(iOS 14, *)
extension UICollectionViewListCell: OBAListContentConfigurable {
    public func configure(with config: OBAListContentConfiguration) {
        self.contentConfiguration = config.listContentConfiguration
    }
}

// MARK: - Fallback
class OBAListViewRow: UICollectionViewCell, OBAListContentConfigurable {
    private var data: TableRowData? {
        didSet {
            self.tableRowView.data = data
        }
    }
    private var tableRowView: TableRowView!

    public override init(frame: CGRect) {
        super.init(frame: frame)

        tableRowView = TableRowView(frame: .zero)
        self.contentView.addSubview(tableRowView)
        tableRowView.pinToSuperview(.readableContent)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with config: OBAListContentConfiguration) {
        let style: UITableViewCell.CellStyle
        switch config.appearance {
        case .default: style = .default
        case .subtitle: style = .subtitle
        case .value: style = .value2
        case .header: style = .default
        }

        self.data = TableRowData(title: config.text, attributedTitle: config.attributedText, subtitle: config.secondaryText, style: style, accessoryType: config.accessoryType, tapped: nil)
    }
}
