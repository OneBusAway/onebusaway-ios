//
//  Router.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/26/19.
//

import UIKit

public class ViewRouter: NSObject {
    private let application: Application
    
    public init(application: Application) {
        self.application = application
        super.init()
    }
    
    public func navigateTo(viewController: UIViewController, from fromController: UIViewController) {
        fromController.navigationController?.pushViewController(viewController, animated: true)
    }
}
