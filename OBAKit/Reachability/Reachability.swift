//
//  Reachability.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 9/18/19.
//

import Foundation
import UIKit
import BLTNBoard
import Connectivity
import OBAKitCore

/// This class knows how to present a modal alert that tells the user that their Internet connection is compromised and unable to retrieve data.
class ReachabilityBulletin: NSObject {
    private let bulletinManager: BLTNItemManager
    private let connectivityPage: BLTNPageItem

    override init() {
        connectivityPage = BLTNPageItem(title: OBALoc("reachability_bulletin.title", value: "No Internet", comment: "Title of the alert that appears when the app can't connect to the server."))
        bulletinManager = BLTNItemManager(rootItem: connectivityPage)

        super.init()

        connectivityPage.isDismissable = true
        connectivityPage.image = Icons.noInternet
        connectivityPage.actionButtonTitle = Strings.dismiss
        connectivityPage.actionHandler = { [weak self] _ in
            self?.dismiss()
        }

        bulletinManager.edgeSpacing = .compact
    }

    func showStatus(_ status: ConnectivityStatus, in application: UIApplication) {
        let validStatuses: [ConnectivityStatus] = [.connectedViaWiFiWithoutInternet, .connectedViaCellularWithoutInternet, .notConnected]

        guard validStatuses.contains(status) else {
            return
        }

        switch status {
        case .connectedViaWiFiWithoutInternet:
            connectivityPage.descriptionText = OBALoc("reachability_bulletin.description.wifi_no_internet", value: "We can't access the Internet via your WiFi connection.\r\n\r\nTry turning off WiFi or connecting to a different network.", comment: "Reachability bulletin for a WiFi network that can't access the Internet.")
        case .connectedViaCellularWithoutInternet:
            connectivityPage.descriptionText = OBALoc("reachability_bulletin.description.cellular_no_internet", value: "We can't access the Internet via your cellular connection.\r\n\r\nTry connecting to WiFi or moving to a new area.", comment: "Reachability bulletin for a cellular connection that can't access the Internet.")
        case .notConnected:
            connectivityPage.descriptionText = OBALoc("reachability_bulletin.description.not_connected", value: "We can't access the Internet. Try connecting via WiFi or cellular data.", comment: "Reachability bulletin for a phone with no connection.")
        default:
            connectivityPage.descriptionText = nil
        }

        bulletinManager.showBulletin(in: application)
    }

    func dismiss() {
        guard bulletinManager.isShowingBulletin else { return }

        bulletinManager.dismissBulletin()
    }
}
