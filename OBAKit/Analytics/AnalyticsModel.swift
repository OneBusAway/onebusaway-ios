//
//  AnalyticsModel.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/16/23.
//

import SwiftUI

class AnalyticsModel: ObservableObject {
    init(_ analytics: Analytics?) {
        self.analytics = analytics
    }

    let analytics: Analytics?
}
