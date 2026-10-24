import UIKit

extension SettingsViewController {
    func shareApp() {
        let pitch = String(localized: "Pay Day — free invoices and EU-compliant e-invoicing (Peppol, Factur-X) on iPhone.",
                           comment: "Text shared alongside the App Store link")
        let sheet = UIActivityViewController(activityItems: [pitch, Self.appStoreURL], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        present(sheet, animated: true)
    }

    /// Deletes the server-side account and every on-device record before re-rooting into first-run. The row has
    /// already confirmed. On failure nothing on the device is erased and the row reports the error, so the person can
    /// retry.
    func deleteAccount() async throws {
        try await AccountService.deleteAccount()
        resetAfterDeletion()
    }

    private func resetAfterDeletion() {
        AppSettings.hasOnboarded = false
        Task { await AICreditsManager.store.bootstrap() }
        guard let window = view.window else { return }
        let onboarding = OnboardingViewController.makeFlow { finishedWindow in
            AppSettings.hasOnboarded = true
            finishedWindow?.rootViewController = RootViewController()
        }
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
            window.rootViewController = onboarding
        }
    }

    func presentAppearance() {
        let alert = UIAlertController(title: String(localized: "Appearance"), message: nil, preferredStyle: .actionSheet)
        for (title, mode) in [
            (String(localized: "System"), AppearanceMode.system),
            (String(localized: "Light"), .light),
            (String(localized: "Dark"), .dark),
        ] {
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                AppSettings.appearance = mode
                self.view.window?.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: mode.rawValue) ?? .unspecified
            })
        }
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }

    /// Lets the user review the AI-drafting disclosure and grant or withdraw consent at any time, satisfying the
    /// "obtain permission" requirement with a persistent, reversible control.
    func presentAIConsent() {
        let granted = AppSettings.aiConsentGranted
        let consent = AIConsentViewController(showsDecline: !granted) { [weak self] decision in
            AppSettings.aiConsentGranted = decision
            self?.refreshList()
        }
        present(UINavigationController(rootViewController: consent), animated: true)
    }
}
