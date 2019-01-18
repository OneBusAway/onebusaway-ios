//
//  ShapeModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class ShapeModelOperation: RESTModelOperation {
    public private(set) var shape: String?

    override public func main() {
        super.main()
        shape = decodeModels(type: PolylineEntity.self).first?.points
    }
}
