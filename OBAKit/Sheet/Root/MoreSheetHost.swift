//
//  MoreSheetHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// UIKit wiring wrapper: presents the existing `MoreViewController` inside
/// a `UINavigationController` so its `navigationItem` bar buttons render
/// correctly when reached via `AppSheetRoute.more`.
///
/// Deliberately minimal — a future SwiftUI `MoreView` will replace this
/// wrapper in `AppSheetViewFactory` without touching the coordinator or
/// route enum.
struct MoreSheetHost: UIViewControllerRepresentable {
    let application: Application

    func makeUIViewController(context: Context) -> UINavigationController {
        let more = MoreViewController(application: application)
        return UINavigationController(rootViewController: more)
    }

    // `MoreViewController` reads `application` and its stores directly, so
    // nothing SwiftUI-side changes over the sheet's lifetime.
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }
}
