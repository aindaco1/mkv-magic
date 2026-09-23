import AppKit
import MKVMagicReporting
import MKVMagicSystem

@MainActor
final class DiagnosticReportWindowController: NSWindowController {
    init(
        reports: [DiagnosticIssueReport],
        snapshot: DiagnosticSnapshot? = nil,
        submit: @escaping @MainActor (DiagnosticIssueReport) async throws -> ReportReceipt = {
            try await ReportSubmissionClient().send($0)
        },
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        let content = DiagnosticReportViewController(
            reports: reports, snapshot: snapshot, submit: submit, openURL: openURL)
        let window = NSWindow(contentViewController: content)
        window.title = "Report a Problem — MKV Magic"
        window.setContentSize(NSSize(width: 760, height: 650))
        window.minSize = NSSize(width: 680, height: 600)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.configureMKVMagicKeyboardNavigation(
            startingAt: content.preferredInitialFirstResponder)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class DiagnosticReportViewController: NSViewController {
    private let reports: [DiagnosticIssueReport]
    private let submit: @MainActor (DiagnosticIssueReport) async throws -> ReportReceipt
    private let openURL: (URL) -> Bool
    private let snapshot: DiagnosticSnapshot?
    private let picker = NSPopUpButton()
    private let detail = NSTextView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let send = NSButton(title: "Send Reviewed Report", target: nil, action: nil)
    private let issue = NSButton(title: "View GitHub Issue", target: nil, action: nil)
    private let export = NSButton(title: "Export Local Diagnostics…", target: nil, action: nil)
    private var receipts: [UUID: ReportReceipt] = [:]
    private var submitting = false
    var preferredInitialFirstResponder: NSView { reports.isEmpty ? export : picker }

    init(
        reports: [DiagnosticIssueReport], snapshot: DiagnosticSnapshot? = nil,
        submit: @escaping @MainActor (DiagnosticIssueReport) async throws -> ReportReceipt,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.reports = Array(reports.prefix(20))
        self.snapshot = snapshot
        self.submit = submit
        self.openURL = openURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let heading = NSTextField(labelWithString: "Review a diagnostic report")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let notice = NSTextField(
            wrappingLabelWithString:
                "Review the metadata below, then choose Send Reviewed Report. Reports become public GitHub issues; similar reports are grouped. Media, filenames, subtitle text, and raw logs are never sent. Sending is optional."
        )
        picker.target = self
        picker.action = #selector(selectReport)
        picker.lineBreakMode = .byTruncatingMiddle
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        picker.setAccessibilityLabel("Diagnostic report to review")
        ReadOnlyTextViewPresentation.configure(detail, drawsBackground: true)
        detail.setAccessibilityLabel("Exact sanitized report JSON")
        let scroll = ReadOnlyTextViewPresentation.scrollView(
            containing: detail, borderType: .bezelBorder)
        send.target = self
        send.action = #selector(beginSubmission)
        send.setAccessibilityHelp(
            "Submit only the reviewed metadata to MKV Magic's GitHub issue relay.")
        issue.target = self
        issue.action = #selector(openIssue)
        issue.isHidden = true
        export.target = self
        export.action = #selector(exportDiagnostics)
        export.isEnabled = snapshot != nil
        let storage = NSTextField(
            wrappingLabelWithString:
                snapshot == nil || snapshot?.storageUnavailable == true
                ? "Local diagnostic storage is unavailable. An empty list does not mean nothing failed."
                : "Local log: \(snapshot?.events.count ?? 0) events; \(snapshot?.droppedEventCount ?? 0) writes lost; \(snapshot?.skippedInvalidRecordCount ?? 0) invalid records skipped; \(snapshot?.omittedEventCount ?? 0) older events omitted from export."
        )
        let actions = NSStackView(views: [issue, NSView(), send])
        actions.orientation = .horizontal
        for item in [heading, notice, picker, storage, export, status, actions] {
            item.setContentHuggingPriority(.required, for: .vertical)
            item.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        let stack = NSStackView(views: [
            heading, notice, picker, scroll, storage, export, status, actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        let root = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            picker.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            notice.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            storage.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
        refresh()
    }

    private func refresh() {
        picker.removeAllItems()
        for (index, report) in reports.enumerated() {
            picker.addItem(
                withTitle:
                    "\(index + 1). \(report.kind.rawValue) — \(report.action.rawValue) / \(report.stage.rawValue) / \(report.failure.rawValue)"
            )
        }
        picker.isEnabled = !reports.isEmpty
        send.isEnabled = !reports.isEmpty
        selectReport()
    }

    @objc private func selectReport() {
        guard reports.indices.contains(picker.indexOfSelectedItem) else {
            ReadOnlyTextViewPresentation.present(
                "No recent reportable failure. Reproduce the problem and reopen this window. You can also export the local diagnostics below.",
                in: detail)
            return
        }
        let report = reports[picker.indexOfSelectedItem]
        ReadOnlyTextViewPresentation.present(
            String(decoding: (try? report.encoded()) ?? Data(), as: UTF8.self), in: detail)
        send.isEnabled = !submitting && receipts[report.id] == nil
        issue.isHidden = receipts[report.id] == nil
        if let receipt = receipts[report.id] {
            presentStatus(
                "Sent successfully. Reports are grouped in GitHub issue #\(receipt.issueNumber).")
            return
        }
        presentStatus(
            report.kind == .interruptedOperation
                ? "An unfinished operation is not proof of a crash; the app may have been force-quit."
                : "Not sent. Review this exact payload before sending.")
    }

    @objc private func beginSubmission() {
        Task { await sendReport() }
    }

    func sendReport() async {
        guard !submitting, reports.indices.contains(picker.indexOfSelectedItem) else { return }
        let report = reports[picker.indexOfSelectedItem]
        guard receipts[report.id] == nil else { return }
        submitting = true
        send.isEnabled = false
        picker.isEnabled = false
        presentStatus("Sending reviewed report…")
        defer {
            submitting = false
            picker.isEnabled = true
            send.isEnabled = receipts[report.id] == nil
        }
        do {
            let receipt = try await submit(report)
            // Validate injected and XPC senders at the same presentation seam.
            receipts[report.id] = try ReportReceipt.validated(
                JSONEncoder().encode(receipt), for: report.id)
            issue.isHidden = false
            presentStatus(
                "Sent successfully. Reports are grouped in GitHub issue #\(receipt.issueNumber).")
        } catch {
            presentStatus(
                "Submission was not confirmed. Check your connection and try Send again. Retrying uses the same report ID to avoid duplicate counting. You can still export diagnostics locally."
            )
        }
    }

    @objc private func openIssue() {
        guard reports.indices.contains(picker.indexOfSelectedItem),
            let receipt = receipts[reports[picker.indexOfSelectedItem].id]
        else { return }
        if !openURL(receipt.issueURL) {
            presentStatus(
                "Report sent to GitHub issue #\(receipt.issueNumber), but the issue could not be opened."
            )
        }
    }

    @objc private func exportDiagnostics() {
        guard let snapshot else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MKV-Magic-Local-Diagnostics.json"
        panel.message = "Save bounded diagnostic events locally. This does not submit anything."
        do {
            guard let destination = try OutputSavePanel.choose(panel) else { return }
            defer { _ = destination.directoryAccess }
            try PrivacySafeSupportReportWriter.writeDiagnostics(snapshot, to: destination.url)
            presentStatus(
                "\(OutputSavePanel.exportMessage(for: destination.url)) Nothing was submitted."
            )
        } catch {
            presentStatus(
                "Could not save diagnostics. Choose another writable location and try again.")
        }
    }

    private func presentStatus(_ message: String) {
        AccessibleStatusPresentation.present(message, in: status)
    }
}
