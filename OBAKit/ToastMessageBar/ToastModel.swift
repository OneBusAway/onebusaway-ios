//
//  ToastModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//


import OBAKitCore
import SwiftUI

public struct Toast: Equatable {
    let message: String
    let type: ToastType
    let duration: TimeInterval

    public enum ToastType {
        case success
        case error

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success:
                return ThemeColors.shared.brand.toColor()
            case .error:
                return .red
            }
        }
    }

    init(message: String, type: ToastType, duration: TimeInterval = 3.0) {
        self.message = message
        self.type = type
        self.duration = duration
    }
}
