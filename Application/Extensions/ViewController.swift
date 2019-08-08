//
//  ViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/8/19.
//

import UIKit

protocol AppContext where Self: UIViewController {
    var application: Application { get }
}
