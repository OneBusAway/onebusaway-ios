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
final class MapPanelLayout: FloatingPanelBottomLayout {
    static let EstimatedDrawerTipStateHeight: CGFloat = 72

    override var initialState: FloatingPanelState {
        return _initialState
    }

    private var _initialState: FloatingPanelState
    init(initialState: FloatingPanelState) {
        self._initialState = initialState
    }
}

/// A layout object used with `FloatingPanel` on `MapViewController`.
final class MapPanelLandscapeLayout: FloatingPanelLayout {
    static let WidthSize: CGFloat = 291

    var position: FloatingPanelPosition = .bottom

    var initialState: FloatingPanelState
    init(initialState: FloatingPanelState) {
        self.initialState = initialState
    }

    var anchors: [FloatingPanelState: FloatingPanelLayoutAnchoring] {
        return [
            .full: FloatingPanelLayoutAnchor(absoluteInset: 18.0, edge: .top, referenceGuide: .safeArea),
            .half: FloatingPanelLayoutAnchor(fractionalInset: 0.5, edge: .bottom, referenceGuide: .safeArea),
            .tip: FloatingPanelLayoutAnchor(absoluteInset: 69.0, edge: .bottom, referenceGuide: .safeArea)
        ]
    }

    func prepareLayout(surfaceView: UIView, in view: UIView) -> [NSLayoutConstraint] {
        return [
            surfaceView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 8.0),
            surfaceView.widthAnchor.constraint(equalToConstant: MapPanelLandscapeLayout.WidthSize)
        ]
    }

    func backdropAlpha(for state: FloatingPanelState) -> CGFloat {
        return 0.0
    }
}
