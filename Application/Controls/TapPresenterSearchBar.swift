//
//  TapPresenterSearchBar.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/28/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit

/// Effectively a 'dummy' search bar. Taps on this control are intercepted and used to trigger display of the 'real' search UI.
public class TapPresenterSearchBar: UISearchBar, UISearchBarDelegate {

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        delegate = self
    }

    public var tapped: (() -> Void)?

    public func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        tapped?()
        return false
    }
}
