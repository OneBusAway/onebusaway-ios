//
//  BackgroundDotAnnotationView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import UIKit

/// The subtle gray dot that stops and rental markers collapse into while a stop
/// sheet owns the map.
///
/// The sheet exists to show one stop's route lines and the vehicles running on
/// them; a downtown block's worth of full-size stop pins buries both. A dot still
/// says "there is a stop here" without competing for attention.
///
/// It is also inert. `isEnabled = false` is what stops MapKit from selecting an
/// annotation — `isUserInteractionEnabled` is the wrong knob, because MapKit
/// hit-tests annotation views itself — so a stray finger can't swap the sheet out
/// from under the rider.
final class BackgroundDotAnnotationView: MKAnnotationView {

    private enum Layout {
        static let diameter: CGFloat = 7
    }

    private let dot: UIView = {
        let dot = UIView()
        // A dynamic system color resolves itself across light/dark when it is a
        // view's `backgroundColor`. The same color as a `CALayer.backgroundColor`
        // would be a `CGColor`, frozen at the appearance it was created under.
        dot.backgroundColor = .systemGray
        dot.alpha = 0.8
        return dot
    }()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        bounds = CGRect(x: 0, y: 0, width: Layout.diameter, height: Layout.diameter)
        addSubview(dot)

        isEnabled = false
        canShowCallout = false
        // Dots are backdrop. Anything real on the map outranks them for collision.
        displayPriority = .defaultLow
        collisionMode = .circle
        // These stops remain reachable through search and the sheet itself; an
        // unlabelled, unselectable dot would only add noise to the rotor.
        isAccessibilityElement = false
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        dot.frame = bounds
        dot.layer.cornerRadius = bounds.width / 2.0
    }
}
