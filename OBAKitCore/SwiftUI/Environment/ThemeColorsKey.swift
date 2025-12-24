//
//  ThemeColorsKey.swift
//  OBAKitCore
//
//  Created by Alan Chu on 2/9/23.
//

import SwiftUI

private struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue: ThemeColors = ThemeColors(bundle: .main, traitCollection: nil)
}

extension EnvironmentValues {
    public var themeColors: ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}
