//
//  OperationController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// A base class for view controllers that load data from an operation and display it on-screen.
class OperationController<OperationType, DataType>: UIViewController, AppContext where OperationType: Operation {
    let application: Application

    var operation: OperationType?
    var data: DataType? {
        didSet {
            updateUI()
        }
    }

    /// This is the default initializer for `OperationController`.
    /// - Parameter application: The application object
    public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        operation?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.operation = loadData()
    }

    /// Override this method in subclasses to load data. Base class implementation is a no-op.
    open func loadData() -> OperationType? {
        return nil
    }

    /// Override this method in subclasses to update the UI. Base class implementation is a no-op.
    open func updateUI() {
        // nop
    }
}
