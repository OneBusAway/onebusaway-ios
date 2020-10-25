//
//  AgencyAlertViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 10/10/20.
//

import OBAKitCore

extension AgencyAlert {
    struct ListViewModel: OBAListViewItem {
        var id: String
        var title: String
        var body: String
        var localizedURL: URL?

        var subtitle: String { return String(body.prefix(256)) }
        var onSelectAction: OBAListViewAction<ListViewModel>?

        var contentConfiguration: OBAContentConfiguration {
            var config = OBAListRowConfiguration(
                text: title,
                secondaryText: subtitle,
                appearance: .subtitle,
                accessoryType: .disclosureIndicator)

            config.image = UIImage(systemName: "exclamationmark.circle")?.applyingSymbolConfiguration(.init(textStyle: .body))
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
