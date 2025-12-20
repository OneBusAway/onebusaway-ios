//
//  ScheduleTip.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/10/25.
//

import TipKit
import OBAKitCore

/// A tip that introduces users to the schedule/timetable feature.
struct ScheduleTip: Tip {
    var title: Text {
        Text(Strings.scheduleTipTitle)
    }

    var message: Text? {
        Text(Strings.scheduleTipMessage)
    }

    var image: Image? {
        Image(systemName: "calendar")
    }
}
