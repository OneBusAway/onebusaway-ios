//
//  LogViewerViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// Displays application logs with share functionality
class LogViewerViewController: UIViewController, AppContext {

    let application: Application

    // MARK: - UI Elements

    private lazy var textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.backgroundColor = ThemeColors.shared.systemBackground
        tv.textColor = ThemeColors.shared.label
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    // MARK: - Init

    init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)

        title = OBALoc("log_viewer_controller.title", value: "Logs", comment: "Title of the Logs viewer controller")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: Icons.share,
            style: .plain,
            target: self,
            action: #selector(shareLogs)
        )

        setupViews()
        loadLogs()
    }

    private func setupViews() {
        view.addSubview(textView)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Log Loading

    private func loadLogs() {
        activityIndicator.startAnimating()
        textView.text = ""

        Task {
            let logContent = await loadLogContentAsync()

            await MainActor.run {
                activityIndicator.stopAnimating()

                if logContent.isEmpty {
                    textView.text = OBALoc(
                        "log_viewer_controller.no_logs",
                        value: "No logs available.",
                        comment: "Message shown when there are no logs to display"
                    )
                } else {
                    textView.text = logContent
                }
            }
        }
    }

    private func loadLogContentAsync() async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let content = Logger.combinedLogContent()
                continuation.resume(returning: content)
            }
        }
    }

    // MARK: - Actions

    @objc private func shareLogs() {
        let logContent = Logger.combinedLogContent()

        guard !logContent.isEmpty else {
            let alert = UIAlertController(
                title: OBALoc(
                    "log_viewer_controller.no_logs_to_share.title",
                    value: "No Logs",
                    comment: "Title for alert when there are no logs to share"
                ),
                message: OBALoc(
                    "log_viewer_controller.no_logs_to_share.message",
                    value: "There are no log files to share.",
                    comment: "Message for alert when there are no logs to share"
                ),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction.cancelAction)
            present(alert, animated: true)
            return
        }

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("app-logs.txt")
        do {
            try logContent.write(to: tmpURL, atomically: true, encoding: .utf8)
        } catch {
            Logger.error("Failed to write logs to temp file: \(error)")
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [tmpURL],
            applicationActivities: nil
        )

        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }

        present(activityVC, animated: true)
    }
}
