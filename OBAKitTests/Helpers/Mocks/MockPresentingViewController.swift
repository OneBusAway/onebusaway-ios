//
//  MockPresentingViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/17/25.
//

import UIKit

// Mock view controller that tracks presentation calls
class MockPresentingViewController: UIViewController {
    var presentedAlert: UIAlertController?
    var presentCallCount = 0

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentCallCount += 1
        if let alert = viewControllerToPresent as? UIAlertController {
            presentedAlert = alert
        }
        // Call completion immediately since we're not actually presenting
        completion?()
    }
}
