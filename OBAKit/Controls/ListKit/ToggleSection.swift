//
//  ToggleSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import IGListKit

/// IGListKit section data class that displays a `UISegmentedControl`.
final class ToggleSectionData: NSObject, ListDiffable {
    func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? ToggleSectionData else { return false }
        return selectedIndex == object.selectedIndex && segments == object.segments
    }

    init(segments: [String], selectedIndex: Int, valueChanged: @escaping ((Int) -> Void)) {
        self.segments = segments
        self.selectedIndex = selectedIndex
        self.valueChanged = valueChanged
    }

    let segments: [String]
    let selectedIndex: Int
    let valueChanged: (Int) -> Void
}

/// A IGListKit section controller that works with `ToggleSectionData` to display a `UISegmentedControl`.
final class ToggleSectionController: OBAListSectionController<ToggleSectionData> {
    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let sectionData = sectionData else { fatalError() }
        let cell = dequeueReusableCell(type: ToggleSectionCell.self, at: index)
        cell.sectionData = sectionData
        return cell
    }
}

/// A collection view cell that works with `ToggleSectionData` to display a `UISegmentedControl`.
final class ToggleSectionCell: SelfSizingCollectionCell {
    var sectionData: ToggleSectionData? {
        didSet {
            guard let sectionData = sectionData else { return }

            for (idx, elt) in sectionData.segments.enumerated() {
                segmentedControl.insertSegment(withTitle: elt, at: idx, animated: false)
            }
            segmentedControl.selectedSegmentIndex = sectionData.selectedIndex
        }
    }

    lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl.autolayoutNew()
        control.addTarget(self, action: #selector(valueChanged(_:)), for: .valueChanged)
        return control
    }()

    override func prepareForReuse() {
        super.prepareForReuse()
        segmentedControl.removeAllSegments()
    }

    @objc private func valueChanged(_ sender: Any) {
        sectionData?.valueChanged(segmentedControl.selectedSegmentIndex)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(segmentedControl)
        segmentedControl.pinToSuperview(.layoutMargins)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
