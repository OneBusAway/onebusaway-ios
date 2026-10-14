//
//  OnDemandServiceHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI
import UIKit

/// Renders `AppSheetRoute.onDemandService` in the map panel's sheet.
///
/// Hosts `OnDemandServiceViewController` rather than `OnDemandServiceView`
/// directly: the controller owns the booking line's refreshes (on appear, on
/// returning to the foreground, at the next boundary), which the pushed page
/// and the UIKit map's sheet rely on too.
struct OnDemandServiceHost: UIViewControllerRepresentable {
    let application: Application
    let service: OnDemandService
    let locationCheck: OnDemandLocationCheck?
    /// The probe's full geometry, for a service from the point probe.
    let geometry: OnDemandDetailGeometry?

    func makeUIViewController(context: Context) -> OnDemandServiceViewController {
        OnDemandServiceViewController(application: application, service: service, locationCheck: locationCheck, geometry: geometry)
    }

    // The route carries one service for the sheet's lifetime; the controller
    // refreshes its own summary.
    func updateUIViewController(_ uiViewController: OnDemandServiceViewController, context: Context) { }
}
