//
//  OnDemandPickerView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import OBAKitCore
import SwiftUI
import UIKit

struct OnDemandPickerRow: Identifiable, Equatable {
    let match: OnDemandServiceMatch
    let title: String
    /// Status in the card style; nil for `.unknown`.
    let statusLine: String?
    /// Area names (or the zone count) · booking tag.
    let detailLine: String
    let color: UIColor

    var id: String { match.id }
}

/// Spec 3.5: the picker's text and rows, sorted by soonest usable.
struct OnDemandPickerModel: Equatable {
    let title: String
    let subtitle: String
    let rows: [OnDemandPickerRow]
    let footer: String
    let source: ProbeSource
    let coordinate: CLLocationCoordinate2D
    let locality: String?

    init(request: OnDemandPickerRequest, locality: String?, colors: [String: UIColor], copy: OnDemandCopy) {
        let candidates = request.scope == .insideOnly ? request.matches.filter(\.isInside) : request.matches
        let sorted = sortedSoonestUsable(candidates)
        rows = sorted.map { match in
            let serviceCopy = copy.forService(match.service)
            return OnDemandPickerRow(
                match: match,
                title: match.service.name,
                statusLine: serviceCopy.statusText(match.availability.status, style: .card),
                detailLine: serviceCopy.pickerSecondLine(
                    areaNames: match.service.areas.compactMap(\.name),
                    areaCount: match.service.areas.count,
                    availability: match.availability
                ),
                color: colors[match.id] ?? OnDemandServiceColors.baseColor(for: match.service)
            )
        }
        title = OnDemandCopy.pickerTitle(count: sorted.count, nearby: request.scope == .nearby)
        subtitle = Self.subtitle(source: request.source, locality: locality)
        footer = Strings.onDemandPickerFooter
        source = request.source
        coordinate = request.coordinate
        self.locality = locality
    }

    static func subtitle(source: ProbeSource, locality: String?) -> String {
        switch (source, locality) {
        case (.rider, let locality?): return String(format: Strings.onDemandPickerSubtitleLocationFormat, locality)
        case (.mapCenter, let locality?): return String(format: Strings.onDemandPickerSubtitleCenterFormat, locality)
        case (.point, let locality?): return String(format: Strings.onDemandPickerSubtitlePointFormat, locality)
        case (.rider, nil): return Strings.onDemandPickerYourLocation
        case (.mapCenter, nil): return Strings.onDemandPickerMapCenter
        case (.point, nil): return Strings.onDemandPickerSelectedPlace
        }
    }

    /// The location facts for a row's detail page.
    func locationCheck(for match: OnDemandServiceMatch) -> OnDemandLocationCheck {
        OnDemandLocationCheck(source: source, isInside: match.isInside, locality: locality, coordinate: coordinate)
    }

    static func == (lhs: OnDemandPickerModel, rhs: OnDemandPickerModel) -> Bool {
        lhs.title == rhs.title && lhs.subtitle == rhs.subtitle && lhs.rows == rhs.rows && lhs.source == rhs.source
    }
}

struct OnDemandPickerView: View {
    let model: OnDemandPickerModel
    let onHighlight: (String?) -> Void
    let onSelect: (OnDemandServiceMatch, OnDemandLocationCheck) -> Void
    let onClose: () -> Void

    private static let iconSize: CGFloat = 40

    var body: some View {
        List {
            Section {
                ForEach(model.rows) { row in
                    Button {
                        onHighlight(row.id)
                        onSelect(row.match, model.locationCheck(for: row.match))
                    } label: {
                        rowContent(row)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                header
            } footer: {
                Text(model.footer).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        // No `.onDisappear { onHighlight(nil) }`: in the classic shell it fires
        // when a row pushes the detail and would clear the highlight the row
        // just set. Each host clears it on close or dismissal instead.
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.title2.weight(.bold)).foregroundStyle(.primary).textCase(nil)
                Text(model.subtitle).font(.subheadline).foregroundStyle(.secondary).textCase(nil)
            }
            Spacer()
            Button(Strings.close, systemImage: "xmark") { onClose() }
                .labelStyle(.iconOnly)
                .font(.body.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .padding(.bottom, 8)
    }

    private func rowContent(_ row: OnDemandPickerRow) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(uiColor: row.color))
                Image(systemName: "car.fill").foregroundStyle(.white)
            }
            .frame(width: Self.iconSize, height: Self.iconSize)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.headline)
                if let status = row.statusLine {
                    OnDemandStatusText(status).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(row.detailLine).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
