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
/// Support), not `UserDefaults`, in a directory excluded from device
/// backups. That keeps the value truly per-install: it's never swept up in a
/// backup, so restoring a backup to a second device (or restoring to the
/// same device after a reinstall) can't leave two devices sharing one ID,
/// and the file is removed automatically when the app is uninstalled.
enum AnalyticsInstallID {
    private static let fileName = "install-id"

    /// This install's ID, read (or created) once per process — the value can't
    /// change while the app runs, so later region changes and activations skip
    /// the file I/O.
    static let current = persisted()

    /// `Analytics/` inside the app's private Application Support directory, or
    /// nil if that can't be resolved (the ID is then not persisted rather than
    /// written somewhere the OS may purge).
    static let defaultDirectory: URL? = try? FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
    ).appendingPathComponent("Analytics", isDirectory: true)

    /// Returns the ID stored in `directory`, generating and storing a new one
    /// when it's missing or invalid. Never throws: analytics must never crash
    /// or block the app, so a persistence failure still returns an ID for
    /// this run.
    static func persisted(directory: URL? = defaultDirectory) -> String {
        guard let directory else { return UUID().uuidString }
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)

        if let data = try? Data(contentsOf: fileURL),
           let contents = String(data: data, encoding: .utf8) {
            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if UUID(uuidString: trimmed) != nil {
                return trimmed
            }
        }

        let newID = UUID().uuidString
        persist(newID, to: fileURL)
        return newID
    }

    /// Writes `id`, creating the directory on first use and excluding the
    /// whole directory from backups so anything stored here stays per-device.
    private static func persist(_ id: String, to fileURL: URL) {
        var directory = fileURL.deletingLastPathComponent()
        do {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                try directory.setResourceValues(resourceValues)
            }
            try id.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            // Analytics must never crash or block on a persistence failure.
        }
    }
}
