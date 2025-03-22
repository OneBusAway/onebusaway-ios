//
//  HapticFeedback.swift
//  OBAKit
//
//  Created by Prince Yadav on 08/03/25.
//


import SwiftUI
import WatchKit

// Haptic feedback utility for consistent feedback throughout the app
enum HapticFeedback {
    case light
    case medium
    case heavy
    case success
    case error
    case warning
    case selection
    
    func play() {
        // Check if haptic feedback is enabled in settings
        let enableHapticFeedback = UserDefaults.standard.bool(forKey: "enableHapticFeedback")
        guard enableHapticFeedback else { return }
        
        switch self {
        case .light:
            WKInterfaceDevice.current().play(.click)
        case .medium:
            WKInterfaceDevice.current().play(.click)
        case .heavy:
            WKInterfaceDevice.current().play(.click)
        case .success:
            WKInterfaceDevice.current().play(.success)
        case .error:
            WKInterfaceDevice.current().play(.failure)
        case .warning:
            WKInterfaceDevice.current().play(.notification)
        case .selection:
            WKInterfaceDevice.current().play(.click)
        }
    }
}

// Extension to make it easier to use haptic feedback
extension View {
    func onTapWithHaptic(_ feedback: HapticFeedback, action: @escaping () -> Void) -> some View {
        self.onTapGesture {
            feedback.play()
            action()
        }
    }
}

