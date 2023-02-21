//
//  TaskController.swift
//  OBAKit
//
//  Created by Alan Chu on 2/7/23.
//

import UIKit
import SwiftUI

/// A base class for view controllers that load data from an operation and display it on-screen.
class TaskController<DataType>: UIViewController, AppContext {
    let application: Application

    public var data: DataType? {
        return try? result?.get()
    }

    public var error: Error? {
        if case let .failure(error) = self.result {
            return error
        } else {
            return nil
        }
    }

    private var result: Result<DataType, Error>? {
        didSet {
            updateUI()
        }
    }

    private var task: Task<Void, Error>?

    public init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        task?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.task = Task {
            do {
                self.result = .success(try await loadData())
            } catch {
                self.result = .failure(error)
            }
        }
    }

    open func loadData() async throws -> DataType {
        fatalError("\(#function) has not been implemented")
    }

    @MainActor
    open func updateUI() {

    }
}
