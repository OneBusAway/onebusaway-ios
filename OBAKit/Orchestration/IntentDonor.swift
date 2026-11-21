//
//  IntentDonor.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import OBAKitCore

/// Donates App Intents, so Siri can learn what a rider does and suggest it (#1556).
/// Tests substitute a fake that records each donation.
protocol IntentDonor {
    func donateOpenStop(_ stop: StopEntity)
}

/// Donates through `IntentDonationManager`.
struct SystemIntentDonor: IntentDonor {
    func donateOpenStop(_ stop: StopEntity) {
        var intent = OpenStopIntent()
        intent.target = stop
        Task {
            do {
                try await IntentDonationManager.shared.donate(intent: intent)
            } catch {
                Logger.error("Couldn't donate Open Stop for \(stop.id): \(error)")
            }
        }
    }
}
