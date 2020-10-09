//
//  OBAContentView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/8/20.
//

import Foundation

public protocol OBAContentView {
    func apply(_ config: OBAContentConfiguration)
}

public protocol OBAContentConfiguration {
    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type { get }
}
