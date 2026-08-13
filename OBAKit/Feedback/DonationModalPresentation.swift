//
//  DonationModalPresentation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit

extension UIViewController {

    /// Presents donation UI and charges the shared ask budget only once the
    /// presentation has actually happened.
    ///
    /// Donation modals are raised from three unrelated places — the More tab, the stop
    /// page, and a push notification — and each has to charge `PromptCoordinator` for the
    /// session's one interruption. Doing that before `present` is wrong in a way nothing
    /// catches: UIKit silently no-ops, without calling the completion handler, when the
    /// presenter is detached or mid-transition, so a modal the rider never saw would
    /// suppress the review prompt for 14 days. Routing all three through here means a
    /// fourth call site can't get the ordering wrong.
    func presentDonationModal(_ rootView: some View, coordinator: PromptCoordinator) {
        present(UIHostingController(rootView: rootView), animated: true) {
            coordinator.noteShown(.donationModal)
        }
    }
}
