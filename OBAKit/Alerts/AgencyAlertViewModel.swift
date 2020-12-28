//
//  AgencyAlertViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 10/10/20.
//

import OBAKitCore
import Foundation

extension AgencyAlert {
    /// The view model used for displaying `AgencyAlert` in an `OBAListView`.
    struct ListViewModel: OBAListViewItem {
        let id: String
        let title: String
        let body: String
        let localizedURL: URL?

        /// Truncated summary for UILabel performance. Agencies often provide long
        /// summaries, which causes poor UI performance for us. See #264 & #266.
        var subtitle: String { return String(body.prefix(256)) }
        var onSelectAction: OBAListViewAction<ListViewModel>?

        var contentConfiguration: OBAContentConfiguration {
            var config = OBAListRowConfiguration(
                text: title,
                secondaryText: subtitle,
                appearance: .subtitle,
                accessoryType: .disclosureIndicator)

            config.image = Icons.readAlert.applyingSymbolConfiguration(.init(textStyle: .body))
            config.textConfig.numberOfLines = 2
            config.secondaryTextConfig.numberOfLines = 3

            config.textConfig.accessibilityNumberOfLines = 5
            config.secondaryTextConfig.accessibilityNumberOfLines = 8
            return config
        }

        init(_ agencyAlert: AgencyAlert, forLocale locale: Locale, onSelectAction: OBAListViewAction<ListViewModel>? = nil) {
            self.id = agencyAlert.id
            self.title = agencyAlert.titleForLocale(locale) ?? ""
            self.body = agencyAlert.bodyForLocale(locale) ?? ""
            self.localizedURL = agencyAlert.URLForLocale(locale)
            self.onSelectAction = onSelectAction
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: ListViewModel, rhs: ListViewModel) -> Bool {
            return lhs.title == rhs.title &&
                lhs.body == rhs.body &&
                lhs.localizedURL == rhs.localizedURL
        }
    }

    var listViewModel: ListViewModel {
        return ListViewModel(self, forLocale: Locale.current)
    }
}
