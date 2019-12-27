//
//  SituationAlertPresenter.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/27/19.
//

import UIKit
import OBAKitCore

class SituationAlertPresenter: NSObject {

    static func buildAlert(from situation: Situation, application: Application) -> UIAlertController {
        let alert = UIAlertController(title: situation.summary.value, message: situation.situationDescription.value, preferredStyle: .alert)

        if let url = situation.url {
            alert.addAction(title: NSLocalizedString("situation_alert_presenter.service_alerts.learn_more", value: "Learn More", comment: "Button shows you more information.")) { _ in
                application.open(url, options: [:], completionHandler: nil)
            }
        }

        alert.addAction(UIAlertAction.dismissAction)

        return alert
    }
}
