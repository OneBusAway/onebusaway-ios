//
//  NearbyStopsSheetHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import MapKit
import OBAKitCore

/// UIKit wiring wrapper for `AppSheetRoute.nearbyStops`, mirroring
/// `StopDetailSheetHost`. Replace with a native list when one exists.
struct NearbyStopsSheetHost: UIViewControllerRepresentable {
    let application: Application
    let coordinate: CLLocationCoordinate2D

    func makeUIViewController(context: Context) -> UINavigationController {
        let dismiss = context.environment.dismiss
        return Self.makeNavigationController(application: application, coordinate: coordinate, onClose: { dismiss() })
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }

    /// Factory seam mirroring `StopDetailSheetHost`, so tests can drive the wiring
    /// without a `UIHostingController`.
    static func makeNavigationController(
        application: Application,
        coordinate: CLLocationCoordinate2D,
        onClose: @escaping () -> Void
    ) -> UINavigationController {
        let controller = NearbyStopsViewController(coordinate: coordinate, application: application)
        let closeButton = UIBarButtonItem(primaryAction: UIAction(title: Strings.close) { _ in onClose() })
        for state: UIControl.State in [.normal, .highlighted] {
            closeButton.setTitleTextAttributes([.foregroundColor: UIColor.label], for: state)
        }
        controller.navigationItem.leftBarButtonItem = closeButton
        return UINavigationController(rootViewController: controller)
    }
}
