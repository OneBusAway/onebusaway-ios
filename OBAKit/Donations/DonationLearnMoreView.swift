//
//  DonationRequestView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/28/23.
//

import SwiftUI
import UIKit
import OBAKitCore

enum DonationRecurrence: String, CaseIterable, Identifiable {
    case oneTime
    case recurring

    var id: Self { self }
}

struct DonationLearnMoreView: View {
    let closedWithDonation: ((Bool) -> Void)
    @State var showFullExplanation = false
    @State private var recurrenceSelection = DonationRecurrence.oneTime
    @State private var selectedAmountInCents: Int = 2750
    @State private var customAmount = ""
    @EnvironmentObject var donationModel: DonationModel
    @EnvironmentObject var analyticsModel: AnalyticsModel

    private var otherAmountSelected: Binding<Bool> {
        Binding(
            get: { selectedAmountInCents == -1 },
            set: { _ in /* nop */ }
        )
    }

    private var showThankYouMessage: Binding<Bool> {
        Binding(
            get: { donationModel.result == .completed },
            set: { _ in /* nop */ }
        )
    }

    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button("Close") {
                analyticsModel.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.donationCanceled, value: nil)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .zIndex(2)

            VStack {
                List {
                    buildHeaderImageSection()
                    buildExplanationSection()
                    buildDonationSection()
                    buildPhotoCreditSection()
                }
                .listStyle(.plain)
                .edgesIgnoringSafeArea(.all)
                .zIndex(1)

                buildDonateButton()
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .interactiveDismissDisabled() // disabled to make sure that we can always get analytics data for a user-initiated dismissal.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onFirstAppear {
            analyticsModel.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.donationLearnMoreShown, value: nil)
        }
        .alert("Enter an amount in U.S. dollars", isPresented: otherAmountSelected) {
            buildOtherAmountAlert()
        }
        .onChange(of: donationModel.donationComplete) { newValue in
            guard newValue else { return }

            let shouldDismiss: Bool

            switch donationModel.result {
            case .completed:
                shouldDismiss = true
            case .failed:
                shouldDismiss = true
            case .canceled, .none:
                shouldDismiss = false
            }

            if shouldDismiss {
                closedWithDonation(donationModel.result == .completed)
                dismiss()
            }
        }
    }

    private func buildDonateButton() -> some View {
        Button(donateButtonTitle) {
            Task {
                await donationModel.donate(selectedAmountInCents, recurring: recurrenceSelection == .recurring)
            }
        }
        .frame(maxWidth: .infinity)
        .padding([.leading, .trailing, .top], 30)
        .padding([.bottom], 40)
        .background(Color.accentColor)
        .foregroundColor(.white)
        .fontWeight(.bold)
        .font(.title2)
    }

    private func buildOtherAmountAlert() -> some View {
        Group {
            TextField("Enter an amount in U.S. dollars", text: $customAmount)
                .keyboardType(.numberPad)
            Button("OK") {
                let amount = Int(customAmount)
                if let amount, amount > 0 {
                    selectedAmountInCents = Int(Double(amount) * 100.0)
                    donationAmountsInCents.append(selectedAmountInCents)
                    donationAmountsInCents.sort()
                }
                customAmount = ""
            }
        }
    }

    func buildPhotoCreditSection() -> some View {
        Text("Photo by Timothy Neesam / License CC-BY-ND 2.0 (https://flickr.com/photos/neesam)")
            .font(.footnote)
            .foregroundStyle(.gray)
            .listRowSeparator(.hidden)
    }

    func buildExplanationSection() -> some View {
        Group {
            Text("Here's why we need your help").font(.title2).bold()
            Text("""
            We have big plans to improve OneBusAway, but we can't do it without your help. This app is currently built with 100% volunteer labor, and we need you to help us fund future development.

            We can't wait to bring you exciting new features, like a trip planner, Apple Watch app, and much more!

            As a key project of the Open Transit Software Foundation, a 501(c)(3) non-profit, we rely on the goodwill of users like you to keep running and making this software better.

            Every year, only a small fraction of our users donate, but every contribution, big or small, helps ensure that OneBusAway remains free, updated, and accessible to everyone. A small donation, even just the cost of one week of commuting, $27.50, can make all the difference.

            Your tax-deductible contribution ensures that OneBusAway remains free and accessible for everyone. Let's shape the future of transit together!

            Thank you,
            The OneBusAway Team
            """)
            .lineLimit(showFullExplanation ? nil : 3)

            if !showFullExplanation {
                Button {
                    showFullExplanation = true
                } label: {
                    Text("Expand...")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .listRowSeparator(.hidden)
    }

    @State var donationAmountsInCents: [Int] = [
        275,
        1000,
        2750,
        7500,
        15000
    ]

    func buildDonationSection() -> some View {
        Section {
            Text("Make a Donation").font(.title2).bold()

            Picker("Donation Recurrence", selection: $recurrenceSelection) {
                Text("Just Once")
                    .tag(DonationRecurrence.oneTime)
                Text("Every Month")
                    .tag(DonationRecurrence.recurring)
            }
            .pickerStyle(.segmented)

            Picker(selection: $selectedAmountInCents) {
                ForEach(donationAmountsInCents, id: \.self) { amt in
                    if let formatted = format(cents: amt) {
                        Text(formatted).tag(amt)
                    }
                }
                Text("Other Amount").tag(-1)
            } label: {
                Text("Amount")
                    .font(.title2)
                    .bold()
            }
            .pickerStyle(.wheel)
        }
        .listRowSeparator(.hidden)
    }

    private var donateButtonTitle: String {
        guard let formattedValue = format(cents: selectedAmountInCents) else {
            return Strings.donate
        }

        let fmt = OBALoc("donation_learn_more.donate_amount_button_fmt", value: "Donate %@", comment: "The title of the Donate button. It will read something like 'Donate $50'.")
        return String(format: fmt, formattedValue)
    }

    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    func format(cents: Int) -> String? {
        guard cents > 0 else { return nil }

        return currencyFormatter.string(from: (Double(cents) / 100.0) as NSNumber)
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

//  #Preview {
//    abxoxo - needs environment object added.
//    DonationLearnMoreView()
//  }
