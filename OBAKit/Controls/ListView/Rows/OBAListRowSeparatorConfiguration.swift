//
//  OBAListRowSeparatorConfiguration.swift
//  OBAKit
//
//  Created by Alan Chu on 6/20/21.
//

public struct OBAListRowSeparatorConfiguration: Equatable {
    public let showsSeparator: Bool
    public let insets: NSDirectionalEdgeInsets

    public init(showsSeparator: Bool = true, insets: NSDirectionalEdgeInsets = .zero) {
        self.showsSeparator = showsSeparator
        self.insets = insets
    }

    /// Convenience initializer for a hidden separator configuration.
    static func hidden() -> OBAListRowSeparatorConfiguration {
        return .init(showsSeparator: false)
    }

    /// Convenience initializer for an inset-focused separator configuration.
    static func withInset(top: CGFloat = .zero, leading: CGFloat = .zero, bottom: CGFloat = .zero, trailing: CGFloat = .zero) -> OBAListRowSeparatorConfiguration {
        return .init(insets: NSDirectionalEdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
    }
}

// #398 - list view separators always appears on iOS 14.4
@available(iOS 14.5, *)
extension UIListSeparatorConfiguration {
    mutating func applying(_ obaConfiguration: OBAListRowSeparatorConfiguration) {
        let visibility: UIListSeparatorConfiguration.Visibility = obaConfiguration.showsSeparator ? .automatic : .hidden

        self.topSeparatorVisibility = visibility
        self.bottomSeparatorVisibility = visibility

        self.topSeparatorInsets = obaConfiguration.insets
        self.bottomSeparatorInsets = obaConfiguration.insets
    }
}
