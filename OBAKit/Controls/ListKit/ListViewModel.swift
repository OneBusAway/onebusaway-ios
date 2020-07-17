//
//  ListViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import IGListKit

typealias ListRowActionHandler = ((ListViewModel) -> Void)

/// Base class for all OBAKit ListKit view models.
class ListViewModel: NSObject {
    public var tapped: ListRowActionHandler?
    public var deleted: ListRowActionHandler?
    public var object: Any?

    public init(tapped: ListRowActionHandler?) {
        self.tapped = tapped
    }

    override public var debugDescription: String {
        let desc = super.debugDescription
        let props: [String: Any] = ["tapped": tapped as Any, "object": object as Any]
        return "\(desc) \(props)"
    }
}
