/**
 *  BulletinBoard
 *  Copyright (c) 2017 - present Alexis Aubry. Licensed under the MIT license.
 */

import UIKit

/**
 * A button that provides a visual feedback when the user interacts with it.
 *
 * This style of button works best with a solid `backgroundColor`.
 */

class HighlightButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHighlighting()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configureHighlighting()
    }

    private func configureHighlighting() {
        // OBA: upstream highlighted on `.touchUpInside`, the same event that
        // unhighlights, so the button never dimmed while pressed.
        addTarget(self, action: #selector(highlight), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(unhighlight), for: [.touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel])
    }

    @objc private func highlight() {
        let animations = {
            self.alpha = 0.5
        }

        UIView.transition(with: self, duration: 0.1, animations: animations)
    }

    @objc private func unhighlight() {
        let animations = {
            self.alpha = 1
        }

        UIView.transition(with: self, duration: 0.1, animations: animations)
    }
}
