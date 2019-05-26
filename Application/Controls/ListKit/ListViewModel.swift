//
//  ListViewModel.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/26/19.
//

import Foundation
import IGListKit

public typealias ListRowTapHandler = ((ListViewModel) -> Void)

/// Base class for all OBAKit ListKit view models.
public class ListViewModel: NSObject {
    public let tapped: ListRowTapHandler?
    
    public init(tapped: ListRowTapHandler?) {
        self.tapped = tapped
    }
    
    override public var debugDescription: String {
        let desc = super.debugDescription
        let props: [String: Any] = ["tapped": tapped as Any]
        return "\(desc) \(props)"
    }
}
