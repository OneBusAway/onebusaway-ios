//
//  MapContainerView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import UIKit

/// The map screen's root view. It puts the map views last in VoiceOver order.
///
/// The map is the bottom subview, so by default VoiceOver reads every annotation
/// on it before the status pill, the toolbar and the nearby-stops panel. With
/// bikes and scooters on, that was 50 to 190 elements downtown before a rider
/// reached a stop. The order is worked out each time VoiceOver asks, so views
/// added later, such as a survey card or a semi-modal panel, are included.
final class MapContainerView: UIView {
    override var accessibilityElements: [Any]? {
        get { subviews.filter { !($0 is MKMapView) } + subviews.filter { $0 is MKMapView } }
        // Required to override a settable property; the order is always derived.
        set {}
    }
}
