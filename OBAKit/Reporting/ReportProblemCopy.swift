//
//  ReportProblemCopy.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore

/// User-facing copy for the Report Problem hub screen.
enum ReportProblemCopy {
    static var stopProblemHeader: String {
        OBALoc(
            "report_problem_controller.stop_problem.header",
            value: "Problem with the Stop",
            comment: "Section header for reporting incorrect stop names, numbers, locations, or missing routes or trips, not app bugs."
        )
    }

    static var vehicleProblemHeader: String {
        OBALoc(
            "report_problem_controller.trip_problem.header",
            value: "Problem with a Trip",
            comment: "Section header for reporting a problem with a specific trip or vehicle service. Feedback helps improve transit data."
        )
    }
}
