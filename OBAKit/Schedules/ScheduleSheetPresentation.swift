//
//  ScheduleSheetPresentation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// How the schedule sheet is presented. iPadOS 18 crashes a SwiftUI
/// `DatePicker` inside a `.pageSheet` `UIHostingController` (#908).
enum ScheduleSheetPresentation {
    static func modalStyle(for idiom: UIUserInterfaceIdiom) -> UIModalPresentationStyle {
        idiom == .pad ? .formSheet : .pageSheet
    }
}
