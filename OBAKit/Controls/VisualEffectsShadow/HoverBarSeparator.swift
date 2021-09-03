//
//  HoverBarSeparator.swift
//  OBAKit
//
//  Created by Alan Chu on 8/22/21.
//

import SwiftUI
import OBAKitCore

/// A view for visually separating buttons in HoverBar.
class HoverBarSeparator: UIView {
    fileprivate var separatorHeight: CGFloat = 1.0

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: separatorHeight)
    }

    override var isAccessibilityElement: Bool {
        get { return false }
        set { _ = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    fileprivate func configure() {
        self.backgroundColor = ThemeColors.shared.separator

        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: separatorHeight)
        ])
    }
}

struct HoverBarSeparator_Previews: PreviewProvider {
    static var previews: some View {
        UIViewPreview {
            HoverBarSeparator()
        }
        .previewLayout(.fixed(width: 64, height: 8))
    }
}
