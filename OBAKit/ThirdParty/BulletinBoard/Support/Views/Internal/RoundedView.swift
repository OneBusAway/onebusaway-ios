/**
 *  BulletinBoard
 *  Copyright (c) 2017 - present Alexis Aubry. Licensed under the MIT license.
 */

import UIKit

/**
 * A view with continuous (“squircle”) rounded corners.
 *
 * OBA: upstream drew the corners with a `CAShapeLayer` mask driven by a custom
 * `CALayer` subclass. `CALayer.cornerCurve = .continuous` draws the same shape
 * natively and follows the layer's bounds without a mask rebuild.
 */

class RoundedView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The corner radius of the view.
    var cornerRadius: CGFloat {
        get { layer.cornerRadius }
        set { layer.cornerRadius = newValue }
    }

}
