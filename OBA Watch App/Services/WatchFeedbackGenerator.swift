import WatchKit
import SwiftUI

public class WatchFeedbackGenerator {
    public static let shared = WatchFeedbackGenerator()
    
    private let enabledKey = "watch_haptic_on_reload"
    
    public func play(_ type: WKHapticType) {
        guard WatchAppState.userDefaults.bool(forKey: enabledKey) else { return }
        WKInterfaceDevice.current().play(type)
    }
    
    public func success() {
        play(.success)
    }
    
    public func error() {
        play(.failure)
    }
    
    public func click() {
        play(.click)
    }
}
