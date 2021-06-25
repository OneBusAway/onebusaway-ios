//
//  OBAListRowViewHeader.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

import OBAKitCore

/// A header view that visually separates sections in `OBAListView`.
/// To include collapsible sections support, the `section` model you assign has to implement
/// collapsible sections.
public class OBAListRowViewHeader: OBAListRowView {
    static let ReuseIdentifier = "OBAListRowViewHeader_ReuseIdentifier"

    public var section: OBAListViewSection?
}
