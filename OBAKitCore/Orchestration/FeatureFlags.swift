//
//  FeatureFlags.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// UserDefaults keys for experimental, opt-in features. Read at app
/// construction; changes generally require a relaunch to take effect.
public enum FeatureFlags {
    /// Gates the SwiftUI map panel experience (full-screen map + floating
    /// sheet) over the classic UIKit tab bar.
    public static let useMapPanelExperienceKey = "OBAUseMapPanelExperience"
}
