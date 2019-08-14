//
//  AlarmModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class AlarmModelOperation: DataOperation {
    public var apiOperation: Operation?
    public private(set) var alarm: Alarm?

    public override func main() {
        super.main()

        guard
            let apiOperation = apiOperation as? CreateAlarmOperation,
            let data = apiOperation.data else {
            return
        }

        let decoder = JSONDecoder.obacoServiceDecoder()

        alarm = try? decoder.decode(Alarm.self, from: data)
    }
}
