//
//  PanelApplicationRootView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The root SwiftUI view for the panel-based application interface.
/// This view uses VehiclesMapView as the main content, displaying a full-screen map
/// with floating panels for all content presentation.
public struct PanelApplicationRootView: View {
    let application: Application

    public init(application: Application) {
        self.application = application
    }

    public var body: some View {
        VehiclesMapView(application: application)
    }
}
