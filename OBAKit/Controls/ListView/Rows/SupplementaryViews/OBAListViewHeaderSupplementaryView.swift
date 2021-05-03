//
//  OBAListViewHeaderSupplementaryView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/10/20.
//

import UIKit

// MARK: - UICollectionReusableView

/// Respond to user actions on the header view.
public protocol OBAListRowHeaderSupplementaryViewDelegate: AnyObject {
    func didTap(_ headerView: OBAListRowViewHeader, section: OBAListViewSection)
}

/// The view for displaying `OBAListRowViewHeader` as a `UICollectionView` supplementary header.
/// To respond to user actions on the header view, set `delegate`.
public class OBAListRowHeaderSupplementaryView: UICollectionReusableView {
    static let ReuseIdentifier = "OBAListRowHeaderSupplementaryView_ReuseIdentifier"

    // MARK: - Properties to set
    public weak var delegate: OBAListRowHeaderSupplementaryViewDelegate?
    public var section: OBAListViewSection? {
        get { headerView.section }
        set { headerView.section = newValue }
    }

    // MARK: - UI
    fileprivate var headerView: OBAListRowViewHeader = OBAListRowViewHeader.autolayoutNew()

    public override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(headerView)
        headerView.pinToSuperview(.edges)

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(tapGestureRecognizer)
    }

    @objc func didTap(_ sender: UITapGestureRecognizer) {
        guard let section = section else { return }
        self.delegate?.didTap(self.headerView, section: section)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
