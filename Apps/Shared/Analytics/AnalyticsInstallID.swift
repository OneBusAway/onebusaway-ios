//
//  AnalyticsInstallID.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A random, anonymous, per-install identifier for analytics backends that
/// derive their own "visitor"/session ID from client IP + User-Agent (e.g.
/// Umami). Those backends mint a new visitor on every IP change (wifi ↔
/// cellular) unless the event payload supplies a stable `id`; this type is
/// that `id`.
///
/// Deliberately NOT derived from any device identifier (no
/// `identifierForVendor`, no IDFA/`ASIdentifierManager`): the value is
/// generated locally with `UUID()`, so a reinstall mints a fresh ID — the
/// same per-install semantics Google Analytics uses, and it carries no App
/// Tracking Transparency implications.
///
/// The ID is persisted to a file in the app's private container (Application
/// Support), not `UserDefaults`, and that file is excluded from device
/// backups. That keeps the value truly per-install: it's never swept up in a
/// backup, so restoring a backup to a second device (or restoring to the
/// same device after a reinstall) can't leave two devices sharing one ID,
/// and the file is removed automatically when the app is uninstalled.
enum AnalyticsInstallID {
    private static let fileName = "install-id"

    /// The directory the install ID file lives in: `Analytics/` inside the
    /// app's private Application Support directory.
    static var defaultDirectory: URL {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? FileManager.default.temporaryDirectory

        return appSupport.appendingPathComponent("Analytics", isDirectory: true)
    }

    /// Returns the persisted install ID, generating and storing one on first
    /// call. Stable across calls (and across app launches) for a given
    /// `directory`.
    ///
    /// Never throws: analytics must never crash or block the app. If the
    /// existing file can't be read, is empty, or doesn't contain a valid
    /// UUID, a fresh ID is generated. If persisting a newly-generated ID
    /// fails, the generated ID is still returned (it just won't survive to
    /// the next launch).
    static func persisted(directory: URL = defaultDirectory) -> String {
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)

        if let data = try? Data(contentsOf: fileURL),
           let contents = String(data: data, encoding: .utf8) {
            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if UUID(uuidString: trimmed) != nil {
                return trimmed
            }
        }

        let newID = UUID().uuidString
        persist(newID, to: fileURL, in: directory)
        return newID
    }

    private static func persist(_ id: String, to fileURL: URL, in directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try id.write(to: fileURL, atomically: true, encoding: .utf8)

            var excludedURL = fileURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try excludedURL.setResourceValues(resourceValues)
        } catch {
            // Analytics must never crash or block on a persistence failure;
            // the caller still gets `id` back for this run.
        }
    }
}
