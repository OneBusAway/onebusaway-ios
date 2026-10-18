//
//  Application+Appearance.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import UIKit

// MARK: - Appearance and Themes

extension Application {
    /// Sets default styles for several UIAppearance proxies in order to customize the app's look and feel
    ///
    /// To override the values that are set in here, either customize the theme that this object is
    /// configured with at launch or simply don't call this method and set up your own `UIAppearance`
    /// proxies instead.
    func configureAppearanceProxies() {
        // `brandTint`, not `brand`: these colour text and controls, and `brand`
        // is too pale on white to read (2.76:1 in the OneBusAway app).
        let tint = ThemeColors.shared.brandTint
        for t in [UIWindow.self, UINavigationBar.self, UISearchBar.self, UISegmentedControl.self, UITabBar.self, UITextField.self, UIButton.self] {
            t.appearance().tintColor = tint
        }

        UISwitch.appearance().onTintColor = tint

        StopArrivalView.appearance().notificationCenter = notificationCenter

        MKMarkerAnnotationView.appearance().markerTintColor = ThemeColors.shared.brand

        UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: tint], for: .normal)
    }
}
