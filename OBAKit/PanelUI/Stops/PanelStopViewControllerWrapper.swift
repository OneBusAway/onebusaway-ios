//
//  PanelStopViewControllerWrapper.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import OBAKitCore

///  A PanelUI wrapper around StopViewController with a leading close button.
struct PanelStopViewControllerWrapper: UIViewControllerRepresentable {
    let application: Application
    let stop: Stop
    var onArrivalDepartureTapped: ((ArrivalDeparture) -> Void)?
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let stopVC = StopViewController(application: application, stop: stop)
        stopVC.onArrivalDepartureTapped = onArrivalDepartureTapped

        let closeButton = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: context.coordinator,
            action: #selector(Coordinator.close)
        )
        closeButton.accessibilityLabel = OBALoc(
            "panel_stop_view_controller_wrapper.close_button.accessibility_label",
            value: "Close",
            comment: "Accessibility label for the close button on the stop panel."
        )
        stopVC.navigationItem.leftBarButtonItem = closeButton

        let navController = UINavigationController(rootViewController: stopVC)
        navController.navigationBar.prefersLargeTitles = true

        return navController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // Refresh callbacks so the coordinator always has the latest closures
        context.coordinator.onClose = onClose
        if let stopVC = uiViewController.viewControllers.first as? StopViewController {
            stopVC.onArrivalDepartureTapped = onArrivalDepartureTapped
        }
    }

    final class Coordinator {
        var onClose: () -> Void

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        @objc func close() {
            onClose()
        }
    }
}
