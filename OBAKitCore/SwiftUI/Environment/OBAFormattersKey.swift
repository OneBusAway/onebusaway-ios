//
//  OBAFormattersKey.swift
//  OBAKitCore
//
//  Created by Alan Chu on 5/25/21.
//

import SwiftUI

private struct OBAFormattersKey: EnvironmentKey {
    static var defaultValue: Formatters {
        Formatters.default
    }
}

extension EnvironmentValues {
    public var obaFormatters: Formatters {
        get { self[OBAFormattersKey.self] }
        set { self[OBAFormattersKey.self] = newValue }
    }
}
