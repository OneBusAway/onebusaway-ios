//
//  Layouts.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/4/19.
//

import FloatingPanel

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
        return [.full, .tip]
    }

    public func insetFor(position: FloatingPanelPosition) -> CGFloat? {
        switch position {
        case .full: return 16.0
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

/// A layout object used with `FloatingPanel` that restricts the panel to a single `FloatingPanelPosition`.
final class SinglePositionMapPanelLayout: NSObject, FloatingPanelLayout {
    let positionInset: CGFloat?

    init(position: FloatingPanelPosition, positionInset: CGFloat) {
        self.initialPosition = position
        self.positionInset = positionInset
    }

    func insetFor(position: FloatingPanelPosition) -> CGFloat? {
        return self.positionInset
    }

    var initialPosition: FloatingPanelPosition

    var supportedPositions: Set<FloatingPanelPosition> {
        [self.initialPosition]
    }

    var positionReference: FloatingPanelLayoutReference {
        .fromSafeArea
    }
}
