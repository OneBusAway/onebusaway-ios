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

    /// How far the finger may travel after the press and still drop a pin:
    /// `UILongPressGestureRecognizer`'s default `allowableMovement`.
    static let allowableMovement: CGFloat = 10

    /// Whether a press that then moved by `translation` before lifting is still
    /// a long press. Farther, and the rider was panning the map after holding.
    static func isStationary(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) <= allowableMovement
    }

    /// Holding still for half a second, then lifting: `onDrop` gets where the
    /// finger pressed, in the map's local space. Half a second is
    /// `UILongPressGestureRecognizer`'s default, which the UIKit map uses.
    static func gesture(onDrop: @escaping (CGPoint) -> Void) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onEnded { value in
                guard case .second(true, let drag?) = value,
                      isStationary(translation: drag.translation) else { return }
                onDrop(drag.startLocation)
            }
    }
}
