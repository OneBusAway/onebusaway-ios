//
//  OBAListViewDelegate.swift
//  OBAKit
//
//  Created by Alan Chu on 3/4/21.
//

public protocol OBAListViewDelegate: class {
    /// Tells the delegate that the OBAListView finished applying data.
    /// - parameter listView: The OBAListView that finished applying data.
    func didApplyData(_ listView: OBAListView)
}

// MARK: - Default implementation

extension OBAListViewDelegate {
    public func didApplyData(_ listView: OBAListView) {
        // nop.
    }
}
