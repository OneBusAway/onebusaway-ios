//
//  OperationController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/2/19.
//

import UIKit

/// A base class for view controllers that load data from an operation and display it on-screen.
class OperationController<OperationType, DataType>: UIViewController where OperationType: Operation {
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
