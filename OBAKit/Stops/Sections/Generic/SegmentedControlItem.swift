//
//  SegmentedControlItem.swift
//  OBAKit
//
//  Created by Alan Chu on 2/24/21.
//

import UIKit
import OBAKitCore

struct SegmentedControlItem: OBAListViewItem {
    var contentConfiguration: OBAContentConfiguration {
        return SegmentedControlContentConfiguration(viewModel: self)
    }

    static var customCellType: OBAListViewCell.Type? {
        return SegmentedControlCell.self
    }

    var onSelectAction: OBAListViewAction<SegmentedControlItem>? {
        didSet {
            if onSelectAction != nil {
                print("Note, you set onSelectAction on a SegmentedControlItem, which doesn't use onSelectAction. Set onSelectItem instead.")
            }
        }
    }

    var onValueChanged: SegmentedControlCell.OnValidChangedHandler?
    var id: String
    var segments: [String]
    var initialSelectedIndex: Int

    init(id: String, segments: [String], initialSelectedIndex: Int = 0, onValueChanged: SegmentedControlCell.OnValidChangedHandler?) {
        self.id = id
        self.segments = segments
        self.initialSelectedIndex = initialSelectedIndex
        self.onValueChanged = onValueChanged
        self.onSelectAction = nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SegmentedControlItem, rhs: SegmentedControlItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.segments == rhs.segments &&
            lhs.initialSelectedIndex == rhs.initialSelectedIndex
    }
}

struct SegmentedControlContentConfiguration: OBAContentConfiguration {
    var viewModel: SegmentedControlItem
    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return SegmentedControlCell.self
    }
}

final class SegmentedControlCell: OBAListViewCell {
    typealias OnValidChangedHandler = (Int) -> Void

    var onValueChangedHandler: OnValidChangedHandler?

    lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl.autolayoutNew()
        control.addTarget(self, action: #selector(valueChanged(_:)), for: .valueChanged)
        return control
    }()

    override var showsSeparator: Bool {
        return false
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onValueChangedHandler = nil
        segmentedControl.removeAllSegments()
    }

    @objc private func valueChanged(_ sender: Any) {
        onValueChangedHandler?(segmentedControl.selectedSegmentIndex)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(segmentedControl)
        segmentedControl.pinToSuperview(.layoutMargins)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? SegmentedControlContentConfiguration else { return }
        for (idx, elt) in config.viewModel.segments.enumerated() {
            segmentedControl.insertSegment(withTitle: elt, at: idx, animated: false)
        }

        self.onValueChangedHandler = config.viewModel.onValueChanged
        segmentedControl.selectedSegmentIndex = config.viewModel.initialSelectedIndex
    }
}
