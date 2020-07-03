//
//  BarButtonActivityIndicator.swift
//  OBAKit
//
//  Created by Alan Chu on 7/2/20.
//

import UIKit

extension UIActivityIndicatorView {
    static func asNavigationItem() -> UIBarButtonItem {
        let style: UIActivityIndicatorView.Style
        if #available(iOS 13.0, *) {
            style = .medium
        } else {
            style = .gray
        }
        let indicator = UIActivityIndicatorView(style: style)
        indicator.startAnimating()

        return UIBarButtonItem(customView: indicator)
    }
}
