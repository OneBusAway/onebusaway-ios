//
//  ShapeModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import OBAModelKit

public class ShapeModelOperation: RESTModelOperation {
    public private(set) var shape: String?

    override public func main() {
        super.main()
        let polylineEntity = decodeModels(type: PolylineEntity.self).first
        shape = polylineEntity?.points
    }
}
