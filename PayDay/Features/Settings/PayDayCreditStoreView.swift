import AICreditsCore
import AICreditsUI
import SwiftUI

/// Pay Day's credit store: same AICredits store/purchase/restore plumbing as the
/// package's CreditStoreView, but renders each pack with its gold-coin icon
/// (asset `pack-<id>`) and adds an explicit Done button.
struct PayDayCreditStoreView: View {
    @ObservedObject var store: AICreditsStore
    @Environment(\.dismiss) private var dismiss
    let shortfall: Int?

    var body: some View {
        NavigationStack {
            List {
                if let shortfall, shortfall > 0 {
                    Section {
                        Text("You need \(shortfall) more credits to send this invoice.")
                            .font(.callout)
                    }
                }
                Section("Your balance") {
                    HStack {
                        Text("\(store.balance) credits").font(.title3.weight(.semibold))
                        Spacer()
                        if store.isWorking { ProgressView() }
                    }
                }
                Section("Credit packs") {
                    ForEach(store.catalog?.packs ?? []) { pack in
                        Button { Task { if await store.purchase(pack) { dismiss() } } } label: {
                            packRow(pack)
                        }
                        .disabled(store.isWorking)
                    }
                }
                Section {
                    Button("Restore Purchases") { Task { await store.restore() } }
                    AppleWalletLinkSection()
                }
                Section {
                    Text("Credits cover each invoice you send over Peppol and optional AI drafting. The app is fully usable without them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Get Credits")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await store.loadCatalog() }
            .alert(
                "Something Went Wrong",
                isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } }),
                presenting: store.error
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private func packRow(_ pack: PurchasablePack) -> some View {
        HStack(spacing: 14) {
            Image("pack-\(pack.id)")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.pack.name).font(.headline)
                Text("\(pack.pack.totalCredits) credits"
                    + (pack.pack.bonusCredits > 0 ? " (+\(pack.pack.bonusCredits) bonus)" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(pack.localizedPrice ?? "—").font(.callout.weight(.semibold))
        }
    }
}
