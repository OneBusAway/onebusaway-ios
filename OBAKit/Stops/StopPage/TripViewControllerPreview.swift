//
//  TripViewControllerPreview.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Lazily-built UIKit preview for row long-presses; the `TripViewController` is
/// constructed only when SwiftUI actually presents the context-menu preview.
struct TripViewControllerPreview: UIViewControllerRepresentable {
    let departure: ArrivalDeparture
    let application: Application

    func makeUIViewController(context: Context) -> TripViewController {
        TripViewController(application: application, arrivalDeparture: departure)
    }

    func updateUIViewController(_ uiViewController: TripViewController, context: Context) {}
}
