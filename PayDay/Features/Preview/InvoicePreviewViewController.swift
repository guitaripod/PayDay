import Combine
import PDFKit
import UIKit
import PayDayKit

/// Renders the document to PDF and offers the export paths: share the PDF,
/// share the compliant Factur-X hybrid + sidecar XML (Pro), and transmit over
/// Peppol (Pro + credits). Compliance status is shown honestly up front.
final class InvoicePreviewViewController: UIViewController {
    private let invoice: Invoice
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
        view.backgroundColor = DesignSystem.Color.background
        let shareItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in self?.share() })
        shareItem.accessibilityLabel = "Share"
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

        let sendButton = DesignSystem.primaryButton("Send via Peppol", symbol: "paperplane.fill")
        sendButton.addAction(UIAction { [weak self] _ in self?.sendPeppol() }, for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.isHidden = !invoice.type.isEInvoiceable

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.color = DesignSystem.Color.secondary

        view.addSubview(statusBar)
        view.addSubview(pdfView)
        view.addSubview(sendButton)
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
            pdfView.bottomAnchor.constraint(equalTo: sendButton.topAnchor, constant: -12),
            sendButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            sendButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    private func renderAsync() {
        let invoice = self.invoice
        Task {
            let premium = demoForceCompliant ? true : await AICreditsManager.store.client.isPremium()
            self.isPremium = premium
            let profile = (try? await BusinessRepository.shared.load())?.defaultEInvoiceProfile ?? .en16931
            let accent = DesignSystem.Color.accent
            let output: FacturXEmbedder.Output = await Task.detached(priority: .userInitiated) {
                let visual = InvoicePDFRenderer(style: .init(accent: accent)).render(invoice)
                // Compliant Factur-X (embedded XML) is a Pro feature; free users
                // still get a clean professional PDF.
                if invoice.type.isEInvoiceable && premium {
                    return FacturXEmbedder(profile: profile).embed(invoice: invoice, visualPDF: visual)
                }
                return FacturXEmbedder.Output(pdf: visual, embedded: false, sidecarXML: Data())
            }.value
            self.spinner.stopAnimating()
            self.renderedPDF = output.pdf
            self.embed = output
            if let document = PDFDocument(data: output.pdf) {
                self.pdfView.document = document
            } else {
                self.statusLabel.text = "Couldn't render this document. Try again."
                self.statusLabel.textColor = DesignSystem.Color.overdue
            }
            self.updateStatus()
        }
    }

    private func updateStatus() {
        guard invoice.type.isEInvoiceable else {
            statusLabel.text = "Estimate — not an e-invoice."
            statusLabel.textColor = DesignSystem.Color.secondary
            return
        }
        let issues = InvoiceValidator.validate(invoice).filter { $0.severity == .error }
        if issues.isEmpty {
            let embedded = embed?.embedded == true
            if embedded {
                statusLabel.text = "✓ EN 16931 compliant · Factur-X embedded in PDF"
                statusLabel.textColor = DesignSystem.Color.paid
            } else if isPremium {
                statusLabel.text = "✓ EN 16931 compliant · structured XML attached on export"
                statusLabel.textColor = DesignSystem.Color.paid
            } else {
                statusLabel.text = "✓ This invoice is EN 16931 ready — unlock Pro to export a compliant Factur-X / Peppol e-invoice."
                statusLabel.textColor = DesignSystem.Color.sent
            }
        } else {
            statusLabel.text = "⚠︎ \(issues.count) issue\(issues.count == 1 ? "" : "s") before this is a compliant e-invoice:\n• " + issues.prefix(3).map(\.message).joined(separator: "\n• ")
            statusLabel.textColor = DesignSystem.Color.overdue
        }
    }

    private func share() {
        guard let pdf = renderedPDF else { return }
        let pdfURL = writeTemp(pdf, name: "\(invoice.number).pdf")
        var items: [Any] = [pdfURL].compactMap { $0 }
        if let sidecar = embed?.sidecarXML, !sidecar.isEmpty, embed?.embedded == false,
           let xmlURL = writeTemp(sidecar, name: FacturXEmbedder.attachmentName) {
            items.append(xmlURL)
        }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }

    private func sendPeppol() {
        Task {
            guard await AICreditsManager.store.client.isPremium() else {
                presentPaywall(reason: "Peppol delivery is a Pay Day Pro feature.")
                return
            }
            guard invoice.buyer.peppolEndpointID.contains(":") else {
                presentAlert("No Peppol address", "Add a Peppol ID to this client to send over the network.")
                return
            }
            guard InvoiceValidator.isCompliant(invoice), let ubl = try? UBLInvoiceWriter().xml(for: invoice) else {
                presentAlert("Not compliant yet", "Resolve the EN 16931 issues shown above before sending.")
                return
            }
            let recipient = PeppolRecipient(
                endpointID: invoice.buyer.peppolEndpointID,
                schemeID: invoice.buyer.peppolSchemeID,
                countryCode: invoice.buyer.address.countryCode)
            await transmit(ubl: ubl, recipient: recipient)
        }
    }

    @MainActor
    private func transmit(ubl: String, recipient: PeppolRecipient) async {
        let hud = UIAlertController(title: "Sending…", message: "\n", preferredStyle: .alert)
        present(hud, animated: true)
        let service = PeppolService()
        do {
            for try await event in service.send(ublXML: ubl, recipient: recipient) {
                switch event {
                case .validating: hud.message = "Validating…"
                case .submitting: hud.message = "Submitting to Peppol…"
                case .accepted: hud.message = "Accepted by the network."
                case .delivered(let id):
                    Haptics.success()
                    hud.dismiss(animated: true) { self.presentAlert("Delivered", "Transmission \(id) accepted by Peppol.") }
                    return
                case .failed(let reason):
                    Haptics.error()
                    hud.dismiss(animated: true) { self.presentAlert("Send failed", reason) }
                    return
                }
            }
        } catch {
            Haptics.error()
            hud.dismiss(animated: true) { self.presentAlert("Send failed", error.localizedDescription) }
        }
    }

    private func presentPaywall(reason: String) {
        let paywall = PaywallViewController(reason: reason)
        present(UINavigationController(rootViewController: paywall), animated: true)
    }

    private func presentAlert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func writeTemp(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); return url } catch { return nil }
    }
}
