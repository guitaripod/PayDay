import Combine
import PDFKit
import UIKit
import PayDayKit

/// Renders the document to PDF and offers the export paths: share the PDF,
/// share the compliant Factur-X hybrid + sidecar XML (Pro), and transmit over
/// Peppol (Pro + credits). Compliance status is shown honestly up front.
final class InvoicePreviewViewController: UIViewController {
    private var invoice: Invoice
    private let pdfView = PDFView()
    private let statusBar = UIView()
    private let statusLabel = UILabel()
    private var renderedPDF: Data?
    private var embed: FacturXEmbedder.Output?
    private var isPremium = false
    private let demoForceCompliant: Bool

    init(invoice: Invoice, demoForceCompliant: Bool = false) {
        self.invoice = invoice
        self.demoForceCompliant = demoForceCompliant
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = invoice.number
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = DesignSystem.Color.background
        let shareItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in self?.share() })
        shareItem.accessibilityLabel = String(localized: "Share")
        navigationItem.rightBarButtonItem = shareItem
        buildLayout()
        renderAsync()
    }

    private let spinner = UIActivityIndicatorView(style: .large)

    private func buildLayout() {
        statusBar.backgroundColor = DesignSystem.Color.surface
        statusLabel.font = DesignSystem.Typography.scaledSystem(13, .semibold, relativeTo: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(statusLabel)
        statusLabel.pinEdges(to: statusBar, insets: UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16))

        pdfView.autoScales = true
        pdfView.backgroundColor = DesignSystem.Color.background
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.color = DesignSystem.Color.secondary

        view.addSubview(statusBar)
        view.addSubview(pdfView)
        view.addSubview(spinner)
        spinner.startAnimating()
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: pdfView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: pdfView.centerYAnchor),
            statusBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: statusBar.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        if invoice.type.isEInvoiceable {
            let sendButton = DesignSystem.primaryButton(String(localized: "Send via Peppol"), symbol: "paperplane.fill")
            sendButton.addAction(UIAction { [weak self] _ in self?.sendPeppol() }, for: .touchUpInside)
            sendButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(sendButton)
            NSLayoutConstraint.activate([
                pdfView.bottomAnchor.constraint(equalTo: sendButton.topAnchor, constant: -12),
                sendButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                sendButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            ])
        } else {
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        }
    }

    private func renderAsync() {
        let invoice = self.invoice
        let accent = DesignSystem.Color.accent
        Task { [weak self] in
            // Render the human-readable PDF first and show it immediately — the
            // free, offline issuing path must never block on a network call
            // (the Pro check / Factur-X embed below). CLAUDE.md: never block issuing.
            let visual = await Task.detached(priority: .userInitiated) {
                InvoicePDFRenderer(style: .init(accent: accent)).render(invoice)
            }.value
            guard let self else { return }
            self.spinner.stopAnimating()
            self.renderedPDF = visual
            self.embed = FacturXEmbedder.Output(pdf: visual, embedded: false, sidecarXML: Data())
            if let document = PDFDocument(data: visual) {
                self.pdfView.document = document
            } else {
                self.statusLabel.text = String(localized: "Couldn't render this document. Try again.")
                self.statusLabel.textColor = DesignSystem.Color.overdue
            }
            self.updateStatus()

            // Then resolve Pro and upgrade to the embedded Factur-X if eligible.
            guard invoice.type.isEInvoiceable else { return }
            let premium = self.demoForceCompliant ? true : await AICreditsManager.store.client.isPremium()
            self.isPremium = premium
            guard premium else { self.updateStatus(); return }
            let profile = (try? await BusinessRepository.shared.load())?.defaultEInvoiceProfile ?? .en16931
            let embedded = await Task.detached(priority: .userInitiated) {
                FacturXEmbedder(profile: profile).embed(invoice: invoice, visualPDF: visual)
            }.value
            self.renderedPDF = embedded.pdf
            self.embed = embedded
            if let document = PDFDocument(data: embedded.pdf) {
                self.pdfView.document = document
            }
            self.updateStatus()
        }
    }

    private func updateStatus() {
        guard invoice.type.isEInvoiceable else {
            statusLabel.text = String(localized: "Estimate — not an e-invoice.")
            statusLabel.textColor = DesignSystem.Color.secondary
            return
        }
        let issues = InvoiceValidator.validate(invoice).filter { $0.severity == .error }
        if issues.isEmpty {
            let embedded = embed?.embedded == true
            if embedded {
                statusLabel.text = String(localized: "✓ EN 16931 valid · Factur-X embedded in PDF")
                statusLabel.textColor = DesignSystem.Color.paid
            } else if isPremium {
                statusLabel.text = String(localized: "✓ EN 16931 valid · structured XML attached on export")
                statusLabel.textColor = DesignSystem.Color.paid
            } else {
                statusLabel.text = String(localized: "✓ EN 16931 valid. Pro makes it a Factur-X e-invoice and sends it over Peppol straight into your client's accounting.",
                                          comment: "Preview status for a free user: the invoice is valid, and what Pro adds")
                statusLabel.textColor = DesignSystem.Color.sent
            }
        } else {
            let headline = String(
                localized: "⚠︎ \(issues.count) issues before this is a valid e-invoice:",
                comment: "Count of EN 16931 validation errors, followed by a bulleted list of them")
            statusLabel.text = headline + "\n• " + issues.prefix(3).map(\.message).joined(separator: "\n• ")
            statusLabel.textColor = DesignSystem.Color.overdue
        }
    }

    private func share() {
        guard ensureOwnSeller(), let pdf = renderedPDF else { return }
        var items: [Any] = []
        if let pdfURL = writeTemp(pdf, name: "\(exportFilename()).pdf") {
            items.append(pdfURL)
        }
        if let sidecar = embed?.sidecarXML, !sidecar.isEmpty, embed?.embedded == false,
           let xmlURL = writeTemp(sidecar, name: FacturXEmbedder.attachmentName) {
            items.append(xmlURL)
        }
        guard !items.isEmpty else {
            presentAlert(String(localized: "Couldn't export"),
                         String(localized: "The PDF couldn't be written for sharing. Try again."))
            return
        }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        sheet.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            guard completed, let self else { return }
            let id = self.invoice.id
            if self.invoice.status == .draft {
                Task {
                    if (try? await InvoiceRepository.shared.markSent(id: id)) != nil {
                        AppLogger.shared.info("share completed: \(id) marked sent", category: .invoice)
                    }
                }
            }
            ReviewPrompt.recordDelivery(from: self)
        }
        present(sheet, animated: true)
    }

    /// A filesystem-safe export name derived from the invoice number — "2026/014"
    /// must not be treated as a directory path when writing the temp PDF.
    private func exportFilename() -> String {
        let disallowed = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        let sanitized = String(invoice.number.unicodeScalars.map { disallowed.contains($0) ? "-" : Character($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "invoice-\(invoice.id.prefix(8))" : sanitized
    }

    private func sendPeppol() {
        guard ensureOwnSeller() else { return }
        Task {
            guard await AICreditsManager.store.client.isPremium() else {
                presentPaywall(reason: String(localized: "Peppol delivery is a Pay Day Pro feature."))
                return
            }
            // Peppol delivery is metered: each send costs credits (charged
            // server-side on an accepted transmission). Gate here so the user
            // tops up before sending rather than discovering it failed.
            await AICreditsManager.store.refresh()
            let peppolSendCost = 30
            if AICreditsManager.store.balance < peppolSendCost {
                CreditStorePresenter.present(from: self, shortfall: peppolSendCost - AICreditsManager.store.balance)
                return
            }
            guard !invoice.seller.peppolParticipant.isEmpty else {
                presentAlert(String(localized: "No sender Peppol ID"),
                             String(localized: "Add your Peppol ID in Business Settings before sending over the network."))
                return
            }
            let buyerPeppol = invoice.buyer.peppolParticipant
            guard !buyerPeppol.isEmpty else {
                presentAlert(String(localized: "No Peppol address"),
                             String(localized: "Add a Peppol ID to this client to send over the network."))
                return
            }
            guard InvoiceValidator.isCompliant(invoice), let ubl = try? UBLInvoiceWriter().xml(for: invoice) else {
                presentAlert(String(localized: "Not valid yet"),
                             String(localized: "Resolve the EN 16931 issues shown above before sending."))
                return
            }
            let recipient = PeppolRecipient(
                endpointID: buyerPeppol.endpointID,
                schemeID: buyerPeppol.schemeID,
                countryCode: invoice.buyer.address.countryCode)
            await transmit(ubl: ubl, recipient: recipient)
        }
    }

    @MainActor
    private func transmit(ubl: String, recipient: PeppolRecipient) async {
        let hud = UIAlertController(title: String(localized: "Sending…"), message: "\n", preferredStyle: .alert)
        present(hud, animated: true)
        let service = PeppolService()
        do {
            for try await event in service.send(ublXML: ubl, invoiceNumber: invoice.number, recipient: recipient) {
                switch event {
                case .validating: hud.message = String(localized: "Validating…")
                case .submitting: hud.message = String(localized: "Submitting to Peppol…")
                case .accepted: hud.message = String(localized: "Accepted by the network.")
                case .delivered(let id):
                    Haptics.success()
                    AppLogger.shared.info("delivered \(invoice.number): transmission \(id)", category: .peppol)
                    try? await InvoiceRepository.shared.markSent(id: invoice.id)
                    await AICreditsManager.store.refresh()
                    hud.dismiss(animated: true) {
                        self.presentAlert(String(localized: "Delivered"),
                                          String(localized: "Transmission \(id) accepted by Peppol.",
                                                 comment: "Peppol transmission identifier returned by the access point")) {
                            ReviewPrompt.recordDelivery(from: self)
                        }
                    }
                    return
                case .failed(let reason):
                    Haptics.error()
                    hud.dismiss(animated: true) { self.presentAlert(String(localized: "Send failed"), reason) }
                    return
                }
            }
        } catch {
            Haptics.error()
            hud.dismiss(animated: true) { self.presentAlert(String(localized: "Send failed"), error.localizedDescription) }
        }
    }

    /// True when the document goes out under the user's own business. Otherwise
    /// explains why it is held back and offers to put the user's business on it.
    private func ensureOwnSeller() -> Bool {
        guard !BusinessSetupGate.canDeliver(invoice) else { return true }
        AppLogger.shared.info("delivery held: \(invoice.id) has no own seller", category: .invoice)
        Haptics.warning()
        Task { @MainActor [weak self] in
            let profile = try? await BusinessRepository.shared.load()
            guard let self else { return }
            let configured = profile?.isConfigured == true
            let alert = UIAlertController(
                title: String(localized: "Add your business first"),
                message: String(localized: "This document doesn't carry your business details yet. Add them so it goes out under your own name and bank account.",
                                comment: "Shown when sharing or sending a document whose seller is the example business or empty"),
                preferredStyle: .alert)
            let actionTitle = configured
                ? String(localized: "Use My Business", comment: "Replaces the example seller on this document with the user's saved business")
                : String(localized: "Set Up Business")
            alert.addAction(UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
                guard let self else { return }
                if let profile, configured {
                    self.reissue(as: profile)
                } else {
                    BusinessSetupGate.presentSetup(from: self) { [weak self] saved in
                        guard saved else { return }
                        Task { @MainActor in
                            if let profile = try? await BusinessRepository.shared.load() { self?.reissue(as: profile) }
                        }
                    }
                }
            })
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
            present(alert, animated: true)
        }
        return false
    }

    /// Puts the user's business on this document, saves it, and re-renders so
    /// they see their own name on the PDF before sharing.
    private func reissue(as profile: BusinessProfile) {
        let updated = BusinessSetupGate.reissue(invoice, as: profile)
        Task { @MainActor in
            do {
                invoice = try await InvoiceRepository.shared.save(updated)
                AppLogger.shared.info("reissued \(invoice.id) under the user's business", category: .invoice)
                Haptics.success()
                renderedPDF = nil
                embed = nil
                spinner.startAnimating()
                renderAsync()
            } catch {
                AppLogger.shared.error("reissue save failed: \(error)", category: .db)
                presentAlert(String(localized: "Couldn't Save"), error.localizedDescription)
            }
        }
    }

    private func presentPaywall(reason: String) {
        let paywall = PaywallViewController(reason: reason)
        present(UINavigationController(rootViewController: paywall), animated: true)
    }

    private func presentAlert(_ title: String, _ message: String, onDismiss: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in onDismiss?() })
        present(alert, animated: true)
    }

    private func writeTemp(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); return url } catch {
            AppLogger.shared.error("temp export write failed for \(name): \(error)", category: .pdf)
            return nil
        }
    }
}
