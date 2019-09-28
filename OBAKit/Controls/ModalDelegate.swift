//
//  ModalDelegate.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/13/19.
//

import UIKit

public protocol ModalDelegate: NSObjectProtocol {
    func dismissModalController(_ controller: UIViewController)
}
