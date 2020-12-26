//
//  Layouts.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import FloatingPanel
import UIKit

/// A layout object used with `FloatingPanel` on `MapViewController`.
final class MapPanelLayout: NSObject, FloatingPanelLayout {
    init(initialPosition: FloatingPanelPosition) {
        self.initialPosition = initialPosition
    }

    func insetFor(position: FloatingPanelPosition) -> CGFloat? {
        switch position {
        case .tip: return 60.0
        case .half: return 250.0
        default: return nil
        }
    }

    var initialPosition: FloatingPanelPosition

    var supportedPositions: Set<FloatingPanelPosition> {
        [.tip, .half, .full]
    }
}

/// A layout object used with `FloatingPanel` on `MapViewController`.
final class MapPanelLandscapeLayout: FloatingPanelLayout {
    init(initialPosition: FloatingPanelPosition) {
        self.initialPosition = initialPosition
    }

    var initialPosition: FloatingPanelPosition

    public var supportedPositions: Set<FloatingPanelPosition> {
        return [.full, .half, .tip]
    }

    public func insetFor(position: FloatingPanelPosition) -> CGFloat? {
        switch position {
        case .full: return 16.0
        case .half: return 250.0
        case .tip: return 69.0
        default: return nil
        }
    }

    public func prepareLayout(surfaceView: UIView, in view: UIView) -> [NSLayoutConstraint] {
        return [
            surfaceView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 8.0),
            surfaceView.widthAnchor.constraint(equalToConstant: 291)
        ]
    }

    public func backdropAlphaFor(position: FloatingPanelPosition) -> CGFloat {
        return 0.0
    }
}
