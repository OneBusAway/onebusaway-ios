/**
 *  BulletinBoard
 *  Copyright (c) 2017 - present Alexis Aubry. Licensed under the MIT license.
 */

import UIKit
import OBAKitCore

/**
 * A button that closes the card.
 *
 * OBA changes from upstream:
 * - The glyph is the `xmark` SF Symbol rather than a path drawn into a 1x
 *   bitmap with the deprecated `UIGraphicsBeginImageContext`.
 * - The colors are dynamic system colors, so the button follows light and dark
 *   mode while the card is on screen. Upstream picked fixed colors once, from
 *   the luminance of the card's background at load time.
 * - The accessibility label comes from the app's localized strings instead of
 *   a force-unwrapped lookup into UIKit's private bundle, and the control has
 *   the button trait.
 * - Highlighting starts on touch down instead of touch up, and dims the
 *   subviews rather than the control, whose alpha is its visibility.
 */

class BulletinCloseButton: UIControl {
    private let backgroundContainer = UIView()
    private let closeGlyph = UIImageView()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
        configureConstraints()
        configureHighlighting()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews() {

        // Content

        isAccessibilityElement = true
        accessibilityLabel = Strings.close
        accessibilityTraits = .button

        // Layout
        addSubview(backgroundContainer)
        addSubview(closeGlyph)

        backgroundContainer.layer.cornerRadius = 14
        backgroundContainer.backgroundColor = .tertiarySystemFill

        let glyphConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        closeGlyph.image = UIImage(systemName: "xmark", withConfiguration: glyphConfiguration)
        closeGlyph.tintColor = .secondaryLabel
        closeGlyph.contentMode = .center

        backgroundContainer.isUserInteractionEnabled = false
        closeGlyph.isUserInteractionEnabled = false

    }

    private func configureConstraints() {

        backgroundContainer.translatesAutoresizingMaskIntoConstraints = false
        closeGlyph.translatesAutoresizingMaskIntoConstraints = false

        backgroundContainer.widthAnchor.constraint(equalToConstant: 28).isActive = true
        backgroundContainer.heightAnchor.constraint(equalToConstant: 28).isActive = true
        backgroundContainer.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        backgroundContainer.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

        closeGlyph.centerXAnchor.constraint(equalTo: backgroundContainer.centerXAnchor).isActive = true
        closeGlyph.centerYAnchor.constraint(equalTo: backgroundContainer.centerYAnchor).isActive = true

    }

    // MARK: - Highlighting

    private func configureHighlighting() {
        addTarget(self, action: #selector(highlight), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(unhighlight), for: [.touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel])
    }

    // OBA: highlighting dims the subviews, not `self.alpha`. The view
    // controller shows and hides the button through `self.alpha`, so upstream's
    // unhighlight could bring a hidden button back.

    @objc private func highlight() {
        setContentAlpha(0.5)
    }

    @objc func unhighlight() {
        setContentAlpha(1)
    }

    private func setContentAlpha(_ alpha: CGFloat) {
        UIView.animate(withDuration: 0.1) {
            self.backgroundContainer.alpha = alpha
            self.closeGlyph.alpha = alpha
        }
    }
}
