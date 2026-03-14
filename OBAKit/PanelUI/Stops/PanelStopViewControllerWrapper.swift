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
    /// Called when the close button is tapped.
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onClose: onClose)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let stopVC = StopViewController(application: application, stop: stop)
        stopVC.onArrivalDepartureTapped = onArrivalDepartureTapped
        stopVC.navigationItem.largeTitleDisplayMode = .always
        stopVC.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: context.coordinator,
            action: #selector(Coordinator.close)
        )

        let navController = UINavigationController(rootViewController: stopVC)
        navController.navigationBar.prefersLargeTitles = true

        return navController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
    }

    final class Coordinator {
        let dismiss: DismissAction
        let onClose: (() -> Void)?

        init(dismiss: DismissAction, onClose: (() -> Void)?) {
            self.dismiss = dismiss
            self.onClose = onClose
        }

        @objc func close() {
            if let onClose {
                onClose()
            } else {
                dismiss()
            }
        }
    }
}
