//
//  Collections.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/22/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

extension Set {
    public var allObjects: [Element] {
        return map {$0}
    }
}
