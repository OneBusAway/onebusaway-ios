//
//  MapControlsCluster.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Bottom-trailing vertical cluster grouping the map-type toggle above the
/// current-location button. Sits above the floating sheet so it moves with the
/// sheet's collapsed height (see `MapPanelRootView`).
struct MapControlsCluster: View {
    let mapType: MapBaseType
    let isLocationButtonVisible: Bool
    let onToggleMapType: () -> Void
    let onCenterOnUser: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            MapTypeButton(mapType: mapType, onTap: onToggleMapType)
            CurrentLocationButton(isVisible: isLocationButtonVisible, onTap: onCenterOnUser)
        }
    }
}
