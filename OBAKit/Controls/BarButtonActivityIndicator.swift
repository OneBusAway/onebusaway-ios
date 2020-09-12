//
//  BarButtonActivityIndicator.swift
//  OBAKit
//
//  Created by Alan Chu on 7/2/20.
//

import UIKit

extension UIActivityIndicatorView {
    static func asNavigationItem() -> UIBarButtonItem {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()

        return UIBarButtonItem(customView: indicator)
    }
}
