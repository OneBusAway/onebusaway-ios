//
//  LocalizationKeys.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-23.
//

import OBAKitCore

// MARK: - LocalizationKeys Enum

/// The widget's copy lives in OBAKitCore's `WidgetStrings`, so it is translated
/// with the rest of that module; this extension ships no `Localizable.strings`.
/// Kept as a forwarding shim for existing call sites — prefer `WidgetStrings`.
internal enum LocalizationKeys {

    static var tapForMoreInformation: String { WidgetStrings.tapForMoreInformation }

    static var emptyStateString: String { WidgetStrings.emptyState }

}
