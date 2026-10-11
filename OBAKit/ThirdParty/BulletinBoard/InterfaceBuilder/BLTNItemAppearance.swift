/**
 *  BulletinBoard
 *  Copyright (c) 2017 - present Alexis Aubry. Licensed under the MIT license.
 */

import UIKit

/**
 * An object that defines the appearance of bulletin items.
 */

@objc class BLTNItemAppearance: NSObject {

    // MARK: - Color Customization

    /// The tint color to apply to the action button (default `.link`).
    @objc var actionButtonColor: UIColor = .link

    /// The button image to apply to the action button
    @objc var actionButtonImage: UIImage?

    /// The title color to apply to action button (default white).
    @objc var actionButtonTitleColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)

    /// The border color to apply to action button.
    @objc var actionButtonBorderColor: UIColor?

    /// The border width to apply to action button.
    @objc var actionButtonBorderWidth: CGFloat = 1.0

    /// The title color to apply to the alternative button (default `.link`).
    @objc var alternativeButtonTitleColor: UIColor = .link

    /// The border color to apply to the alternative button.
    @objc var alternativeButtonBorderColor: UIColor?

    /// The border width to apply to the alternative button.
    @objc var alternativeButtonBorderWidth: CGFloat = 1.0

    /// The tint color to apply to the imageView (if image rendered in template mode, default `.link`).
    @objc var imageViewTintColor: UIColor = .link

    /// The color of title text labels (default `.secondaryLabel`).
    @objc var titleTextColor: UIColor = .secondaryLabel

    /// The color of description text labels (default `.label`).
    @objc var descriptionTextColor: UIColor = .label

    // MARK: - Corner Radius Customization

    /// The corner radius of the action button (default 12).
    @objc var actionButtonCornerRadius: CGFloat = 12

    /// The corner radius of the alternative button (default 12).
    @objc var alternativeButtonCornerRadius: CGFloat = 12

    // MARK: - Font Customization

    /// An optional custom font to use for the title label. Set this to nil to use the system font.
    @objc var titleFontDescriptor: UIFontDescriptor?

    /// An optional custom font to use for the description label. Set this to nil to use the system font.
    @objc var descriptionFontDescriptor: UIFontDescriptor?

    /// An optional custom font to use for the buttons. Set this to nil to use the system font.
    @objc var buttonFontDescriptor: UIFontDescriptor?

    /**
     * Whether the description text should be displayed with a smaller font.
     *
     * You should set this to `true` if your text is long (more that two sentences).
     */

    @objc var shouldUseCompactDescriptionText: Bool = false

    // MARK: - Font Constants

    /// The font size of title elements (default 30).
    @objc var titleFontSize: CGFloat = 30

    /// The font size of description labels (default 20).
    @objc var descriptionFontSize: CGFloat = 20

    /// The font size of compact description labels (default 15).
    @objc var compactDescriptionFontSize: CGFloat = 15

    /// The font size of action buttons (default 17).
    @objc var actionButtonFontSize: CGFloat = 17

    /// The font size of alternative buttons (default 15).
    @objc var alternativeButtonFontSize: CGFloat = 15

}

// MARK: - Font Factories

/// OBA: upstream returned fixed-size fonts, so bulletins ignored Dynamic Type.
/// Each factory now scales its base size with `UIFontMetrics` for a matching
/// text style; the sizes above remain the default-category sizes.
extension BLTNItemAppearance {

    /**
     * Creates the font for title labels.
     */

    @objc func makeTitleFont() -> UIFont {
        let font = titleFontDescriptor.map { UIFont(descriptor: $0, size: titleFontSize) }
            ?? UIFont.systemFont(ofSize: titleFontSize, weight: .medium)
        return UIFontMetrics(forTextStyle: .title1).scaledFont(for: font)
    }

    /**
     * Creates the font for description labels.
     */

    @objc func makeDescriptionFont() -> UIFont {
        let size = shouldUseCompactDescriptionText ? compactDescriptionFontSize : descriptionFontSize
        let font = descriptionFontDescriptor.map { UIFont(descriptor: $0, size: size) }
            ?? UIFont.systemFont(ofSize: size)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
    }

    /**
     * Creates the font for action buttons.
     */

    @objc func makeActionButtonFont() -> UIFont {
        let font = buttonFontDescriptor.map { UIFont(descriptor: $0, size: actionButtonFontSize) }
            ?? UIFont.systemFont(ofSize: actionButtonFontSize, weight: .semibold)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
    }

    /**
     * Creates the font for alternative buttons.
     */

    @objc func makeAlternativeButtonFont() -> UIFont {
        let font = buttonFontDescriptor.map { UIFont(descriptor: $0, size: alternativeButtonFontSize) }
            ?? UIFont.systemFont(ofSize: alternativeButtonFontSize, weight: .semibold)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
    }

}

// MARK: - Status Bar

/**
 * Styles of status bar to use with bulletin items.
 */

@objc enum BLTNStatusBarAppearance: Int {

    /// The status bar is hidden.
    case hidden

    /// The color of the status bar is determined automatically. This is the default style.
    case automatic

    /// Style to use with dark backgrounds.
    case lightContent

    /// Style to use with light backgrounds.
    case darkContent

}
