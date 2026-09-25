//
//  OnDemandServiceViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI
import UIKit

/// UIKit host for `OnDemandServiceView`, so `ViewRouter` can push it and the
/// map can present it as a sheet like the rental detail.
///
/// `now` is the device wall clock, taken once at construction: the deadline
/// line is a snapshot, and the page is short-lived enough that a timer would
/// be noise (spec §6.3).
final class OnDemandServiceViewController: UIHostingController<OnDemandServiceView> {

    init(application: Application, service: OnDemandService) {
        // A nil zone still yields hours and contact details; only the
        // deadline line drops out.
        let summary = OnDemandServiceSummary(service: service, timeZone: service.timeZone, now: Date(), locale: .current)
        super.init(rootView: OnDemandServiceView(
            service: service,
            summary: summary,
            onOpenURL: { [weak application] url in application?.open(url, options: [:], completionHandler: nil) }
        ))
        title = service.name
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
