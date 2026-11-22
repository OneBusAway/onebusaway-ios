//
//  DonationRequestView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/28/23.
//

import SwiftUI
import UIKit
import OBAKitCore

struct DonationLearnMoreView: View {
    @State var showFullExplanation = false
    @EnvironmentObject var donationModel: DonationModel
    @EnvironmentObject var analyticsModel: AnalyticsModel

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(Strings.close) {
                analyticsModel.analytics?.reportEvent(pageURL: "app://localhost/donations", label: AnalyticsLabels.donationCanceled, value: nil)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(uiColor: ThemeColors.shared.brandAccent))
            .padding()
            .zIndex(2)

            List {
                buildHeaderImageSection()
                buildExplanationSection()
                buildDonateButton()
                buildPhotoCreditSection()
            }
            .listStyle(.plain)
        }
        .interactiveDismissDisabled() // disabled to make sure that we can always get analytics data for a user-initiated dismissal.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onFirstAppear {
            analyticsModel.analytics?.reportEvent(pageURL: "app://localhost/donations", label: AnalyticsLabels.donationLearnMoreShown, value: nil)
        }
    }

    private func buildDonateButton() -> some View {
        Button {
            donationModel.donate()
        } label: {
            Text(OBALoc("donation_learn_more.donate_button", value: "Donate on our Website", comment: "Button at the bottom of the donation explanation screen that opens the donation page on the project's website."))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .buttonStyle(.borderedProminent)
        .tint(Color(uiColor: ThemeColors.shared.brandAccent))
        .fontWeight(.bold)
        .font(.title2)
    }

    func buildPhotoCreditSection() -> some View {
        Text(OBALoc("donation_learn_more.photo_credit", value: "Photo by Timothy Neesam / License CC-BY-ND 2.0 (https://flickr.com/photos/neesam)", comment: "Credit for the header photo on the donation explanation screen. Keep the photographer's name, the license name and the URL unchanged."))
            .font(.footnote)
            .foregroundStyle(.gray)
            .listRowSeparator(.hidden)
    }

    /// Built as a `String` so the app name can be interpolated — this framework also
    /// ships as KiedyBus.
    private var explanationText: String {
        String(
            format: OBALoc(
                "donation_learn_more.explanation_fmt",
                value: "We have big plans to improve %1$@, but we can't do it without your help. This app is currently built with 100%% volunteer labor, and we need you to help us fund future development.\n\nAs a key project of the Open Transit Software Foundation, a 501(c)(3) non-profit, we rely on the goodwill of users like you to keep running and making this software better.\n\nEvery year, only a small fraction of our users donate, but every contribution, big or small, helps ensure that %1$@ remains free, updated, and accessible to everyone. A small donation, even just the cost of one week of commuting, $27.50, can make all the difference.\n\nYour tax-deductible contribution ensures that %1$@ remains free and accessible for everyone. Let's shape the future of transit together!\n\nThank you,\nThe %1$@ Team",
                comment: "Full explanation on the donation explanation screen. %1$@ is the app name and appears four times. $27.50 is an amount in US dollars; keep it in dollars. 501(c)(3) is a US tax status; keep it unchanged."
            ),
            Bundle.main.appName
        )
    }

    func buildExplanationSection() -> some View {
        Group {
            Text(OBALoc("donation_learn_more.header", value: "Here's why we need your help", comment: "Heading above the explanation on the donation explanation screen.")).font(.title2).bold()
            Text(explanationText)
            .lineLimit(showFullExplanation ? nil : 3)

            if !showFullExplanation {
                Button {
                    showFullExplanation = true
                } label: {
                    Text(OBALoc("donation_learn_more.read_more", value: "Read More...", comment: "Button on the donation explanation screen that expands the truncated explanation to its full length."))
                        .foregroundColor(.accentColor)
                }
            }
        }
        .listRowSeparator(.hidden)
    }

    func buildHeaderImageSection() -> some View {
        GeometryReader { geometry in
            Image("wmata")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .frame(height: 300)
        .padding(-20)
        .listRowSeparator(.hidden)
    }
}
