//
//  Layouts.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/4/19.
//

import FloatingPanel

/// A layout object used with `FloatingPanel` on `MapViewController`.
class MapPanelLayout: NSObject, FloatingPanelLayout {
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
