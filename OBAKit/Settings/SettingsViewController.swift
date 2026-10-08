//
//  SettingsViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// Hosts `SettingsView`, and owns what it can't: the Done button, error toasts
/// and the share sheet for exported data.
class SettingsViewController: UIHostingController<SettingsView> {
    private let application: Application
    private let viewModel: SettingsViewModel

    init(application: Application) {
        self.application = application
        let viewModel = SettingsViewModel(application: application)
        self.viewModel = viewModel

        super.init(rootView: SettingsView(viewModel: viewModel, exportData: {}))
        // The export button needs `self`, which doesn't exist until `super.init` returns.
        rootView = SettingsView(viewModel: viewModel, exportData: { [weak self] in self?.exportData() })

        title = Strings.settings
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissModal))

        viewModel.showErrorToast = { [weak self] message in
            guard let self else { return }
            self.showErrorToast(message, using: self.application.toastManager)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    private func exportData() {
        do {
            let url = try viewModel.exportUserDefaults()
            present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
        } catch {
            Task { await AlertPresenter.show(error: error, presentingController: self) }
        }
    }

    @objc private func dismissModal() {
        dismiss(animated: true, completion: nil)
    }
}
