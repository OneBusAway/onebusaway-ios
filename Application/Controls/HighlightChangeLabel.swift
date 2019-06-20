//
//  HighlightChangeLabel.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/7/19.
//

import UIKit

/// Alerts the user when its value changes by temporarily changing its background color.
public class HighlightChangeLabel: UILabel {

    public override var text: String? {
        didSet {
            guard oldValue != text else { return }

            highlightBackground()
        }
    }

    /// This is the color that is used to highlight a value change in this label.
    @objc dynamic var highlightedBackgroundColor: UIColor {
        get { return _highlightedBackgroundColor }
        set { _highlightedBackgroundColor = newValue }
    }
    private var _highlightedBackgroundColor: UIColor!

    /// If `true`, this will cause the next invocation of `highlightBackground()` to immediately return.
    ///
    /// - Note: This is set to `true` by default so that the label does not flash when first assigned a value.
    public var skipNextHighlight = true

    /// Causes the background of the label to be highlighted for `Animations.longAnimationDuration`.
    public func highlightBackground() {
        if skipNextHighlight {
            skipNextHighlight = false
            return
        }

        let oldBackgroundColor = layer.backgroundColor
        layer.backgroundColor = highlightedBackgroundColor.cgColor

        Animations.performAnimations(duration: Animations.longAnimationDuration) { [weak self] in
            guard let self = self else { return }
            self.layer.backgroundColor = oldBackgroundColor
        }
    }
}
