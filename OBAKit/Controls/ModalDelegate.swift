//
//  ModalDelegate.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

public protocol ModalDelegate: NSObjectProtocol {
    func dismissModalController(_ controller: UIViewController)
}
