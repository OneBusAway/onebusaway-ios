//
//  MapSnapshotterEnvironmentKey.swift
//  OBAKit
//
//  Created by Alan Chu on 2/22/23.
//

import SwiftUI
import OBAKitCore

private struct StopIconFactoryKey: EnvironmentKey {
    static public let defaultValue: StopIconFactory = {
        return StopIconFactory(iconSize: ThemeMetrics.defaultMapAnnotationSize, themeColors: ThemeColors.shared)
    }()
}

extension EnvironmentValues {
    var stopIconFactory: StopIconFactory {
        get { self[StopIconFactoryKey.self] }
        set { self[StopIconFactoryKey.self] = newValue }
    }
}
