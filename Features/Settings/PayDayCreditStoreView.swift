import AICreditsCore
import AICreditsUI
import MidgarCredits
import SwiftUI

/// Pay Day's credit store: the wallet's packs and purchase through MidgarCredits, each pack rendered with its gold-coin
/// icon (asset `pack-<id>`), an explicit Done button, and the Sign in with Apple row that links the old account.
struct PayDayCreditStoreView: View {
    @State private var model: PayDayCreditStoreModel
    @ObservedObject private var accountLink: AICreditsStore
    @Environment(\.dismiss) private var dismiss

    init(model: PayDayCreditStoreModel, accountLink: AICreditsStore) {
        _model = State(initialValue: model)
        self.accountLink = accountLink
    }

    var body: some View {
        NavigationStack {
            List {
                if let shortfall = model.shortfall {
                    Section {
                        Text(String(localized: "You need \(shortfall) more credits to send this invoice."))
                            .font(.callout)
                    }
                }
                Section(String(localized: "Your balance")) {
                    HStack {
                        Text(String(localized: "\(model.balance ?? 0) credits")).font(.title3.weight(.semibold))
                        Spacer()
                        if model.isWorking { ProgressView() }
                    }
                }
                noticeSection
                Section(String(localized: "Credit packs")) {
                    packs
                }
                Section {
                    Button(String(localized: "Restore Purchases")) { Task { await model.restore() } }
                        .disabled(model.isWorking)
                    AppleWalletLinkSection()
                }
                Section {
                    Text(String(localized: "Credits cover each invoice you send over Peppol and optional AI drafting. The app is fully usable without them."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "Get Credits"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Done")) { dismiss() } }
            }
            .task { await model.observe() }
            .task { await model.load() }
            .task { await accountLink.bootstrap() }
            .alert(
                String(localized: "Something Went Wrong"),
                isPresented: Binding(get: { accountLink.error != nil }, set: { if !$0 { accountLink.error = nil } }),
                presenting: accountLink.error
            ) { _ in
                Button(String(localized: "OK"), role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
        }
        .environmentObject(accountLink)
    }

    @ViewBuilder
    private var noticeSection: some View {
        let showsConfirming = model.confirming > 0
        if showsConfirming || model.notice != nil {
            Section {
                if showsConfirming {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Your purchase is being confirmed")).font(.headline)
                        Text(String(localized: "Your credits arrive as soon as it is confirmed. You do not need to buy again."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                switch model.notice {
                case .awaitingApproval:
                    Text(String(localized: "Waiting for approval. Your credits arrive as soon as it is approved."))
                        .font(.callout)
                case .failure(let message):
                    Text(message).font(.callout).foregroundStyle(.red)
                case nil:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private var packs: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(String(localized: "Loading packs…")).foregroundStyle(.secondary)
            }
        case .unavailable:
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Credit packs are temporarily unavailable from the App Store. You can keep using the app fully — please try again later."))
                    .font(.callout).foregroundStyle(.secondary)
                Button(String(localized: "Try again")) { Task { await model.load() } }
            }
        case .ready:
            ForEach(model.offers) { offer in
                Button {
                    Task { if await model.buy(offer) == .credited { dismiss() } }
                } label: {
                    packRow(offer)
                }
                .disabled(model.isWorking)
            }
        }
    }

    private func packRow(_ offer: MidgarCreditsOffer) -> some View {
        HStack(spacing: 14) {
            Image("pack-\(offer.pack.id)")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: PayDayPacks.name(of: offer.pack)).font(.headline)
                Text(String(localized: "\(offer.pack.credits) credits"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.buyingPackID == offer.pack.id {
                ProgressView()
            } else {
                Text(offer.product.displayPrice).font(.callout.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
