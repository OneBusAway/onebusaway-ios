//
//  MapViewController+Camera.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import UIKit

/// Where the camera goes while a sheet owns the bottom of the screen.
///
/// An extension rather than more of `MapViewController`: framing is one concern
/// with one shared question — which part of the map is still visible — and the
/// class it hangs off is already at SwiftLint's body-length ceiling.
extension MapViewController {

    /// Keeps the tapped stop visible in the strip of map above the sheet. Without
    /// this the pin can end up behind the sheet — nothing recenters today.
    func centerMapAboveSheet(on coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }

        let mapView = mapRegionManager.mapView
        mapView.setVisibleMapRect(
            StopSheetLayout.framingRect(around: coordinate),
            edgePadding: sheetCameraInsets(),
            animated: true
        )
    }

    /// The strip of map a trip can be framed into: what the sheet at its `.half`
    /// detent and the floating toolbar leave uncovered.
    ///
    /// The sheet's height is computed rather than measured for the reason
    /// `StopSheetLayout.halfDetentInset` documents — the panel is private, and
    /// its surface frame isn't final while it is animating, which is exactly
    /// when a trip page is being pushed.
    func sheetCameraInsets() -> UIEdgeInsets {
        let mapView = mapRegionManager.mapView
        let safeArea = mapView.safeAreaInsets
        let sheet = safeArea.bottom + StopSheetLayout.halfDetentInset(
            safeAreaHeight: mapView.safeAreaLayoutGuide.layoutFrame.height
        )

        // The toolbar follows the *trailing* edge, which is the left one in a
        // right-to-left layout. MapKit's padding is physical, so which edge it
        // covers is read off the toolbar's frame rather than assumed.
        let toolbarFrame = mapView.convert(toolbar.bounds, from: toolbar)
        let isOnLeft = toolbarFrame.midX < mapView.bounds.midX

        return MapCameraInsets.insets(
            mapSize: mapView.bounds.size,
            safeArea: safeArea,
            bottomObstruction: sheet,
            leftObstruction: isOnLeft ? toolbarFrame.maxX : 0,
            rightObstruction: isOnLeft ? 0 : mapView.bounds.maxX - toolbarFrame.minX
        )
    }
}
