//
//  DroppedPin.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import SwiftUI

/// The map panel's long-press pin: the counterpart of the UIKit map's
/// `MapRegionManager.userPressedMap(_:)`.
enum DroppedPin {
    /// The place a pin dropped at `coordinate` opens: unnamed until the place
    /// sheet looks it up, so it takes the UIKit pin's name meanwhile.
    static func mapItem(at coordinate: CLLocationCoordinate2D) -> MKMapItem {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = UserDroppedPin.defaultTitle
        return mapItem
    }

    /// Holding still for half a second, then lifting: `onDrop` gets where the
    /// finger was, in the map's local space. Half a second is
    /// `UILongPressGestureRecognizer`'s default, which the UIKit map uses.
    static func gesture(onDrop: @escaping (CGPoint) -> Void) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
                onDrop(drag.location)
            }
    }
}
