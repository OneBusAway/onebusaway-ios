//
//  StopClusterPickerViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// A searchable modal sheet that lets a user pick one stop from a co-located
/// cluster of more than five stops.
///
/// Presented as `.pageSheet` (iPhone) or `.formSheet` (iPad) over `MapViewController`
/// when a tapped stop cluster contains more than five members.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/515
final class StopClusterPickerViewController: UITableViewController {

    // MARK: - Types

    private static let cellID = "StopClusterPickerCell"

    // MARK: - Properties

    /// Called when the user selects a stop. Receives the chosen `Stop`.
    var onStopSelected: ((Stop) -> Void)?

    /// Called when the user dismisses the picker without selecting a stop.
    var onCancel: (() -> Void)?

    private let stops: [Stop]
    private var filteredStops: [Stop]
    private let searchController = UISearchController(searchResultsController: nil)

    // MARK: - Presentation

    /// Returns `.formSheet` on iPad and `.pageSheet` on iPhone so large clusters
    /// present cleanly across compact and regular width classes.
    static func modalPresentationStyle(for idiom: UIUserInterfaceIdiom) -> UIModalPresentationStyle {
        idiom == .pad ? .formSheet : .pageSheet
    }

    // MARK: - Init

    /// - Parameter stops: The full list of stops in the cluster.
    init(stops: [Stop]) {
        self.stops = stops
        self.filteredStops = stops
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleFormat = OBALoc(
            "stop_cluster_picker.nav_title_fmt",
            value: "Select stop — %d stops nearby",
            comment: "Navigation title of the stop cluster picker sheet. %d is replaced by the number of stops."
        )
        let titleText = String.localizedStringWithFormat(titleFormat, stops.count)
        title = titleText
        navigationItem.accessibilityLabel = titleText

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = OBALoc(
            "stop_cluster_picker.search_placeholder",
            value: "Filter by name or route",
            comment: "Placeholder text in the stop cluster picker's search bar."
        )
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
    }

    // MARK: - Actions

    @objc private func close() {
        dismiss(animated: true) { [weak self] in
            self?.onCancel?()
        }
    }

    // MARK: - Filtering

    func applyFilter(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            filteredStops = stops
        } else {
            let lower = trimmed.lowercased()
            filteredStops = stops.filter { stop in
                if stop.name.lowercased().contains(lower) || stop.code.lowercased().contains(lower) {
                    return true
                }
                if let dir = Formatters.adjectiveFormOfCardinalDirection(stop.direction),
                   dir.lowercased().contains(lower) {
                    return true
                }
                return Self.routeIdentifiers(for: stop).contains { $0.lowercased().contains(lower) }
            }
        }
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredStops.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellID, for: indexPath)
        let stop = filteredStops[indexPath.row]
        configureCell(cell, for: stop)
        return cell
    }

    private func configureCell(_ cell: UITableViewCell, for stop: Stop) {
        var config = cell.defaultContentConfiguration()

        config.text = stop.name
        config.textProperties.adjustsFontForContentSizeCategory = true

        let directionAndCode = Self.directionAndCodeSubtitle(for: stop)
        let routeNames = Self.routeIdentifiers(for: stop)
        let subtitleParts = [directionAndCode, routeNames.count > 1 ? routeNames.joined(separator: ", ") : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        config.secondaryText = subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · ")
        config.secondaryTextProperties.adjustsFontForContentSizeCategory = true

        if let primaryRoute = Self.primaryRouteBadge(for: stop) {
            config.image = makeRouteBadge(text: primaryRoute.text, color: primaryRoute.color)
        } else {
            config.image = nil
        }

        cell.contentConfiguration = config
        let baseLabel = StopCluster.pickerTitle(for: stop)
        cell.accessibilityLabel = routeNames.isEmpty ? baseLabel : "\(baseLabel), \(routeNames.joined(separator: ", "))"
        cell.accessibilityTraits = .button
    }

    // MARK: - Helpers

    private static func routeIdentifiers(for stop: Stop) -> [String] {
        let resolvedRoutes = stop.routes ?? []
        if !resolvedRoutes.isEmpty {
            return resolvedRoutes
                .sorted { $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending }
                .map { $0.shortName.isEmpty ? $0.id : $0.shortName }
        }
        return stop.routeIDs
    }

    private static func primaryRouteBadge(for stop: Stop) -> (text: String, color: UIColor)? {
        let resolvedRoutes = stop.routes ?? []
        if let first = resolvedRoutes.sorted(by: { $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending }).first {
            let text = first.shortName.isEmpty ? first.id : first.shortName
            return (text, first.color ?? ThemeColors.shared.brand)
        }
        if let firstID = stop.routeIDs.first, !firstID.isEmpty {
            return (firstID, ThemeColors.shared.brand)
        }
        return nil
    }

    private static func directionAndCodeSubtitle(for stop: Stop) -> String? {
        guard !stop.code.isEmpty else {
            return Formatters.adjectiveFormOfCardinalDirection(stop.direction)
        }
        return Formatters.formattedCodeAndDirection(stop: stop)
    }

    /// Renders a small coloured pill with the route identifier as a `UIImage`.
    private func makeRouteBadge(text: String, color: UIColor) -> UIImage {
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let padding = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        let measured = (text as NSString).size(withAttributes: [.font: font])
        let size = CGSize(
            width: max(24, ceil(measured.width) + padding.left + padding.right),
            height: max(22, ceil(font.lineHeight) + padding.top + padding.bottom)
        )

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
            color.setFill()
            path.fill()

            let textColor = color.badgeTextColor(preferring: .white, minimumRatio: 4.5)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let textRect = CGRect(
                x: (size.width - measured.width) / 2,
                y: (size.height - font.lineHeight) / 2,
                width: measured.width,
                height: font.lineHeight
            )
            (text as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let stop = filteredStops[indexPath.row]
        dismiss(animated: true) { [weak self] in
            self?.onStopSelected?(stop)
        }
    }
}

// MARK: - UISearchResultsUpdating

extension StopClusterPickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        applyFilter(query: searchController.searchBar.text ?? "")
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension StopClusterPickerViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onCancel?()
    }
}
