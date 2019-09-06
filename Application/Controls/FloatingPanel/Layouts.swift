//
//  Layouts.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/4/19.
//

import FloatingPanel

class RemovablePanelLayout: FloatingPanelIntrinsicLayout {
    var supportedPositions: Set<FloatingPanelPosition> {
        return [.full, .half]
    }

    func insetFor(position: FloatingPanelPosition) -> CGFloat? {
        switch position {
        case .half: return 130.0
        default: return nil  // Must return nil for .full
        }
    }
}

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
