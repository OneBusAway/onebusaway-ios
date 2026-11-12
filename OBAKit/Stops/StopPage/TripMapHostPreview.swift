//
//  TripMapHostPreview.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Lazily-built UIKit preview for row long-presses; the `TripMapHostViewController`
/// is constructed only when SwiftUI actually presents the context-menu preview.
struct TripMapHostPreview: UIViewControllerRepresentable {
    let departure: ArrivalDeparture
    let application: Application

    /// The map alone: a 320 by 400 glance has no room for the panel as well.
    func makeUIViewController(context: Context) -> TripMapHostViewController {
        let host = application.viewRouter.makeTripController(tripConvertible: TripConvertible(arrivalDeparture: departure))
        host.enterPreviewMode()
        return host
    }

    func updateUIViewController(_ uiViewController: TripMapHostViewController, context: Context) {}
}
