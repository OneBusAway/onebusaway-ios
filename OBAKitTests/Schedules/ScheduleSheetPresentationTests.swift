//
//  ScheduleSheetPresentationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKit

/// iPadOS 18 crashes a `DatePicker` hosted in a `.pageSheet` SwiftUI
/// `UIHostingController` (#908, Link light rail schedule). Phone keeps
/// `.pageSheet`; iPad uses `.formSheet`.
@Suite(.serialized)
struct ScheduleSheetPresentationTests {

    @Test func `Phone presents the schedule as a page sheet`() {
        #expect(ScheduleSheetPresentation.modalStyle(for: .phone) == .pageSheet)
    }

    @Test func `iPad presents the schedule as a form sheet`() {
        #expect(ScheduleSheetPresentation.modalStyle(for: .pad) == .formSheet)
    }
}
