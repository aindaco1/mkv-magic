import AppKit
import MKVMagicCore
import MKVMagicSystem

enum EncodingBenchmarkPresentation {
    static let consentExplanation =
        "MKV Magic creates a three-second 640×360 10-bit synthetic clip in a private "
        + "temporary folder, then encodes it with the bundled AV1 and HEVC tools. It never "
        + "reads your media or uses the network. CPU and GPU use will briefly increase."

    static func results(_ report: EncodingBenchmarkReport?) -> String {
        guard let report else {
            return "No encoding test has been saved for this version of the bundled tools.\n\n"
                + "Until you run one, MKV Magic recommends AV1 when it is available."
        }
        var lines = ["Recommended: \(report.recommendedPreset.displayName)", ""]
        for attempt in report.attempts {
            switch (attempt.outcome, attempt.metrics) {
            case (.completed, .some(let metrics)):
                let psnr =
                    metrics.averagePSNR.map {
                        String(format: "%.2f dB PSNR", $0)
                    } ?? "PSNR unavailable"
                lines.append(
                    "\(attempt.preset.displayName): \(String(format: "%.1f", metrics.framesPerSecond)) fps at \(report.sourceHeight)p"
                )
                lines.append(
                    "  Estimated 1080p speed: \(String(format: "%.2f", metrics.estimated1080pRealtimeFactor))× real time"
                )
                lines.append(
                    "  Output: \(String(format: "%.2f", Double(metrics.outputBitrate) / 1_000_000)) Mb/s · \(psnr)"
                )
            case (.timedOut, _):
                lines.append("\(attempt.preset.displayName): stopped after the safe time limit")
            case (.failed, _):
                lines.append("\(attempt.preset.displayName): test encode failed")
            default:
                lines.append("\(attempt.preset.displayName): result unavailable")
            }
            lines.append("")
        }
        lines.append(
            "This recommendation changes the initial selection only. Every verified encoder remains available."
        )
        return lines.joined(separator: "\n")
    }
}

@MainActor
final class EncodingBenchmarkWindowController: NSWindowController, NSWindowDelegate {
    init(
        report: EncodingBenchmarkReport?,
        onRun: @escaping @MainActor @Sendable () async throws -> EncodingBenchmarkReport
    ) {
        let content = EncodingBenchmarkViewController(report: report, onRun: onRun)
        let window = NSWindow(contentViewController: content)
        window.title = "MKV Magic Encoding Test"
        window.setContentSize(NSSize(width: 610, height: 500))
        window.minSize = NSSize(width: 540, height: 440)
        window.tabbingMode = .disallowed
        window.configureMKVMagicKeyboardNavigation(
            startingAt: content.preferredInitialFirstResponder
        )
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        (contentViewController as? EncodingBenchmarkViewController)?.cancel()
    }
}

@MainActor
final class EncodingBenchmarkViewController: NSViewController {
    private let onRun: @MainActor @Sendable () async throws -> EncodingBenchmarkReport
    private let resultsText = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let activityIndicator = ActivityIndicatorPresentation.make(
        label: "Encoding test activity",
        help: "Shows while MKV Magic runs the private local encoding benchmark."
    )
    private let runButton = NSButton(title: "Run Encoding Test", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)
    private var report: EncodingBenchmarkReport?
    private var task: Task<Void, Never>?

    var preferredInitialFirstResponder: NSView { runButton }

    init(
        report: EncodingBenchmarkReport?,
        onRun: @escaping @MainActor @Sendable () async throws -> EncodingBenchmarkReport
    ) {
        self.report = report
        self.onRun = onRun
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Choose the faster practical default")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString: EncodingBenchmarkPresentation.consentExplanation
        )
        explanation.textColor = .secondaryLabelColor
        let timing = NSTextField(
            wrappingLabelWithString:
                "Most Macs finish in a few seconds. A very slow AV1 encoder can run for up to "
                + "90 seconds before MKV Magic safely falls back to the completed result."
        )
        timing.textColor = .secondaryLabelColor

        resultsText.isEditable = false
        resultsText.isSelectable = true
        resultsText.drawsBackground = false
        resultsText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultsText.textContainerInset = NSSize(width: 8, height: 8)
        resultsText.string = EncodingBenchmarkPresentation.results(report)
        resultsText.setAccessibilityLabel("Encoding test results")
        resultsText.setAccessibilityHelp(
            "Read-only local AV1 and HEVC speed, size, and quality results."
        )
        let resultsScroll = NSScrollView()
        resultsScroll.documentView = resultsText
        resultsScroll.hasVerticalScroller = true
        resultsScroll.borderType = .bezelBorder

        runButton.target = self
        runButton.action = #selector(runTest)
        runButton.keyEquivalent = "\r"
        runButton.setAccessibilityLabel("Run local encoding test")
        runButton.setAccessibilityHelp(
            "Explicitly start a short synthetic local test without reading private media."
        )
        if report != nil { runButton.title = "Run Again" }
        cancelButton.target = self
        cancelButton.action = #selector(cancelTest)
        cancelButton.isHidden = true
        cancelButton.setAccessibilityHelp("Stop the running synthetic encoding test safely.")
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        closeButton.keyEquivalent = "\u{1b}"
        closeButton.setAccessibilityHelp("Close and keep the current saved recommendation.")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setAccessibilityLabel("Encoding test status")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let controls = NSStackView(views: [
            activityIndicator, statusLabel, spacer, cancelButton, closeButton, runButton,
        ])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10

        let stack = NSStackView(views: [
            heading, explanation, timing, resultsScroll, controls,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.contentWidthConstraint(for: explanation),
            stack.contentWidthConstraint(for: timing),
            stack.contentWidthConstraint(for: resultsScroll),
            resultsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 190),
            stack.contentWidthConstraint(for: controls),
        ])
        view = root
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    @objc private func runTest() {
        guard task == nil else { return }
        setRunning(true)
        statusLabel.stringValue = "Creating and encoding a private synthetic clip…"
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var failureMessage: String?
            do {
                let report = try await onRun()
                self.report = report
                resultsText.string = EncodingBenchmarkPresentation.results(report)
                statusLabel.stringValue = "Saved for this Mac and bundled FFmpeg version."
                runButton.title = "Run Again"
            } catch let error as CommandRunnerError where error == .cancelled {
                statusLabel.stringValue = "Encoding test cancelled; previous recommendation kept."
            } catch is CancellationError {
                statusLabel.stringValue = "Encoding test cancelled; previous recommendation kept."
            } catch {
                failureMessage = UserFacingErrorPresentation.message(
                    failure: "Could not complete the encoding test.",
                    recovery: "The previous recommendation is unchanged; try the test again.",
                    error: error
                )
            }
            task = nil
            setRunning(false)
            if let failureMessage {
                AccessibleStatusPresentation.present(
                    failureMessage,
                    in: statusLabel,
                    returningFocusTo: runButton
                )
            }
        }
    }

    @objc private func cancelTest() {
        task?.cancel()
        statusLabel.stringValue = "Cancelling…"
    }

    @objc private func closeWindow() {
        view.window?.performClose(nil)
    }

    private func setRunning(_ isRunning: Bool) {
        ActivityIndicatorPresentation.set(activityIndicator, active: isRunning)
        runButton.isEnabled = !isRunning
        closeButton.isEnabled = !isRunning
        cancelButton.isHidden = !isRunning
        closeButton.keyEquivalent = isRunning ? "" : "\u{1b}"
        cancelButton.keyEquivalent = isRunning ? "\u{1b}" : ""
    }
}
