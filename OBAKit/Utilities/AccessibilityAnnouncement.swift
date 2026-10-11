//
//  AccessibilityAnnouncement.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// Speaks transient feedback — a HUD, a toast, "Copied" — that VoiceOver would
/// otherwise never reach: these views appear and vanish without taking focus.
enum AccessibilityAnnouncement {

    /// Posts `message` as a VoiceOver announcement.
    ///
    /// Queued behind current speech rather than interrupting it. The confirmations
    /// this carries usually land as the activated control is still being read back,
    /// or alongside a screen change, and an unqueued announcement loses that race.
    static func post(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        let attributed = NSAttributedString(string: message, attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: attributed)
    }
}
