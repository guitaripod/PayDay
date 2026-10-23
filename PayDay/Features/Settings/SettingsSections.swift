import MidgarUI
import UIKit

extension SettingsViewController {
    private static let supportAddress = "support@midgarcorp.cc"
    private static let privacyURL = URL(string: LegalLinks.privacy)!
    private static let termsURL = URL(string: LegalLinks.terms)!

    func makeSections() -> [MidgarSettingsSection] {
        [businessSection(), proSection(), appSection(), aboutSection(), accountSection()]
    }

    private func businessSection() -> MidgarSettingsSection {
        MidgarSettingsSection(
            id: "business",
            title: String(localized: "Your business"),
            rows: [
                destination("business", String(localized: "Business details"), "building.2"),
                destination("payment", String(localized: "Payment & IBAN"), "creditcard"),
                destination("defaults", String(localized: "Invoice defaults"), "slider.horizontal.3"),
            ])
    }

    private func proSection() -> MidgarSettingsSection {
        MidgarSettingsSection(id: "pro", title: String(localized: "Pay Day Pro"), rows: [proRow, creditsRow])
    }

    private var proRow: MidgarSettingsRow {
        if isPremium {
            return MidgarSettingsRow(
                id: "pro", title: String(localized: "Pay Day Pro — Active"), systemImage: "checkmark.seal.fill")
        }
        return .custom(id: "pro", title: String(localized: "Upgrade to Pro"), systemImage: "seal") { [weak self] in
            guard let self else { return }
            present(UINavigationController(rootViewController: PaywallViewController()), animated: true)
        }
    }

    private var creditsRow: MidgarSettingsRow {
        .custom(id: "credits", title: String(localized: "Credits"), detail: "\(balance)", systemImage: "bolt.fill") {
            [weak self] in
            guard let self else { return }
            CreditStorePresenter.present(from: self)
        }
    }

    private func appSection() -> MidgarSettingsSection {
        MidgarSettingsSection(
            id: "app",
            title: String(localized: "App"),
            rows: [
                .custom(id: "appearance", title: String(localized: "Appearance"), systemImage: "circle.lefthalf.filled") {
                    [weak self] in self?.presentAppearance()
                },
                .custom(
                    id: "aiDrafting", title: String(localized: "AI drafting"),
                    detail: AppSettings.aiConsentGranted ? String(localized: "Allowed") : String(localized: "Off"),
                    systemImage: "sparkles"
                ) { [weak self] in self?.presentAIConsent() },
            ])
    }

    private func aboutSection() -> MidgarSettingsSection {
        MidgarSettingsSection(
            id: "about",
            title: String(localized: "About"),
            rows: [
                .link(id: "rate", title: String(localized: "Rate Pay Day"), systemImage: "star", url: Self.writeReviewURL),
                .custom(
                    id: "share", title: String(localized: "Share Pay Day"), systemImage: "square.and.arrow.up",
                    showsDisclosure: false
                ) { [weak self] in self?.shareApp() },
                .privacyPolicy(url: Self.privacyURL),
                .termsOfUse(url: Self.termsURL),
                .support(address: Self.supportAddress),
                .version(),
            ])
    }

    private func accountSection() -> MidgarSettingsSection {
        MidgarSettingsSection(
            id: "account",
            title: String(localized: "Account"),
            rows: [
                .deleteAccount(
                    confirmation: .init(
                        title: String(localized: "Delete account?"),
                        message: String(
                            localized: "This permanently deletes your account, credit balance, and every invoice, estimate, and client on this device. This cannot be undone."),
                        confirmTitle: String(localized: "Delete account"))
                ) { [weak self] in try await self?.deleteAccount() }
            ])
    }

    private func destination(_ id: String, _ title: String, _ symbol: String) -> MidgarSettingsRow {
        .custom(id: id, title: title, systemImage: symbol) { [weak self] in
            self?.showDetailScreen(BusinessSettingsViewController())
        }
    }
}
