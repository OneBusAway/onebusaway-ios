//
//  ListViewModel.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/26/19.
//

import Foundation
import IGListKit

public typealias ListRowActionHandler = ((ListViewModel) -> Void)

/// Base class for all OBAKit ListKit view models.
public class ListViewModel: NSObject {
    public let tapped: ListRowActionHandler?
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
