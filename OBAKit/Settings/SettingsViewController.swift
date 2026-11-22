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
    let application: Application
    var onClose: (() -> Void)?

    init(application: Application, onClose: (() -> Void)? = nil) {
        self.application = application
        self.onClose = onClose
        let viewModel = SettingsViewModel(application: application)
        super.init(rootView: SettingsView(viewModel: viewModel))

        title = Strings.settings
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissModal))

        viewModel.showErrorToast = { [weak application] message in
            application?.showNotice(message)
        }
        viewModel.share = { [weak self] result in
            self?.share(result)
        }
        viewModel.dismissSettings = { [weak self] completion in
            guard let self else {
                completion()
                return
            }
            if let onClose = self.onClose {
                onClose()
                completion()
            } else if presentingViewController != nil {
                dismiss(animated: true, completion: completion)
            } else {
                completion()
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    private func share(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            // Required on iPad, where the share sheet is a popover.
            activity.popoverPresentationController?.sourceView = view
            activity.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY, width: 0, height: 0)
            present(activity, animated: true)
        case .failure(let error):
            Task { await AlertPresenter.show(error: error, presentingController: self) }
        }
    }

    @objc private func dismissModal() {
        if let onClose {
            onClose()
        } else {
            dismiss(animated: true, completion: nil)
        }
    }
}
