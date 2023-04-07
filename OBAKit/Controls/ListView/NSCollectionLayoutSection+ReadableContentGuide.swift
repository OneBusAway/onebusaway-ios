//
//  NSCollectionLayoutSection+ReadableContentGuide.swift
//  OBAKit
//
//  Created by Alan Chu on 4/7/23.
//

import Foundation

extension NSCollectionLayoutSection {
    /// `NSCollectionLayoutSection.list` with content insets set to the Readable Content Guide.
    @MainActor static func readableContentGuideList(
        using configuration: UICollectionLayoutListConfiguration,
        layoutEnvironment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let section = self.list(using: configuration, layoutEnvironment: layoutEnvironment)

        // Change the section's content insets reference to the readable content.
        // This changes the way that the insets in the section's contentInsets property are interpreted.
        section.contentInsetsReference = .readableContent

        // Zero out the default leading/trailing contentInsets, but preserve the default top/bottom values.
        // This ensures each section will be inset horizontally exactly to the readable content width.
        var contentInsets = section.contentInsets
        contentInsets.leading = 0
        contentInsets.trailing = 0
        section.contentInsets = contentInsets

        return section
    }
}
