import AppKit

struct ThirdPartyDocument: Equatable {
    let title: String
    let body: String
}

enum ThirdPartyDocumentLoaderError: Error, Equatable {
    case unsafeResourceRoot
    case unsafeDocument(String)
    case oversizedDocument(String)
    case invalidText(String)
    case unreadableLicenseDirectory
}

struct ThirdPartyDocumentLoader {
    static let maximumDocumentBytes = 2 * 1_024 * 1_024
    static let maximumTotalBytes = 8 * 1_024 * 1_024

    private struct RequiredDocument {
        let title: String
        let relativePath: String
    }

    private static let requiredDocuments = [
        RequiredDocument(
            title: "Third-Party Notices",
            relativePath: "THIRD_PARTY_NOTICES.md"
        ),
        RequiredDocument(
            title: "MKV Magic — GPL-3.0-or-later",
            relativePath: "Licenses/MKV-Magic-GPL-3.0.txt"
        ),
        RequiredDocument(
            title: "Sparkle — MIT",
            relativePath: "Licenses/Sparkle-MIT.txt"
        ),
    ]

    static func load(from resourceRoot: URL) throws -> [ThirdPartyDocument] {
        let fileManager = FileManager.default
        let root = resourceRoot.standardizedFileURL
        guard root.path.hasPrefix("/"), root.path != "/" else {
            throw ThirdPartyDocumentLoaderError.unsafeResourceRoot
        }
        let rootValues = try root.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw ThirdPartyDocumentLoaderError.unsafeResourceRoot
        }

        var totalBytes = 0
        var documents = try requiredDocuments.map { document in
            let url = root.appendingPathComponent(document.relativePath)
            return try loadDocument(
                title: document.title,
                url: url,
                resourceRoot: root,
                totalBytes: &totalBytes
            )
        }

        let toolLicenseRoot = root.appendingPathComponent("Tools/Licenses", isDirectory: true)
        if fileManager.fileExists(atPath: toolLicenseRoot.path) {
            _ = try validateContainedPath(toolLicenseRoot, beneath: root)
            let toolRootValues = try toolLicenseRoot.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey,
            ])
            guard
                toolRootValues.isDirectory == true,
                toolRootValues.isSymbolicLink != true
            else {
                throw ThirdPartyDocumentLoaderError.unsafeDocument("Tools/Licenses")
            }
            var enumerationError = false
            guard
                let enumerator = fileManager.enumerator(
                    at: toolLicenseRoot,
                    includingPropertiesForKeys: [
                        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                    ],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in
                        enumerationError = true
                        return false
                    }
                )
            else {
                throw ThirdPartyDocumentLoaderError.unreadableLicenseDirectory
            }
            var licenseURLs: [URL] = []
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [
                    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                ])
                if values.isSymbolicLink == true {
                    throw ThirdPartyDocumentLoaderError.unsafeDocument(
                        relativePath(for: url, beneath: root)
                    )
                }
                if values.isDirectory == true { continue }
                guard values.isRegularFile == true else {
                    throw ThirdPartyDocumentLoaderError.unsafeDocument(
                        relativePath(for: url, beneath: root)
                    )
                }
                licenseURLs.append(url)
            }
            guard !enumerationError else {
                throw ThirdPartyDocumentLoaderError.unreadableLicenseDirectory
            }
            for url in licenseURLs.sorted(by: { $0.path < $1.path }) {
                let relative = relativePath(for: url, beneath: toolLicenseRoot)
                documents.append(
                    try loadDocument(
                        title: "Bundled Tools — \(relative)",
                        url: url,
                        resourceRoot: root,
                        totalBytes: &totalBytes
                    )
                )
            }
        }
        return documents
    }

    static func applicationDocuments(bundle: Bundle = .main) -> [ThirdPartyDocument] {
        guard let resourceRoot = bundle.resourceURL,
            let documents = try? load(from: resourceRoot)
        else {
            return [
                ThirdPartyDocument(
                    title: "Notices Unavailable",
                    body: """
                        The packaged license documents could not be read. Reinstall MKV Magic from an official release and try again. No media or other user data was accessed.
                        """
                )
            ]
        }
        return documents
    }

    private static func loadDocument(
        title: String,
        url: URL,
        resourceRoot: URL,
        totalBytes: inout Int
    ) throws -> ThirdPartyDocument {
        let relative = try validateContainedPath(url, beneath: resourceRoot)
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ThirdPartyDocumentLoaderError.unsafeDocument(relative)
        }
        let fileSize = values.fileSize ?? (maximumDocumentBytes + 1)
        guard fileSize >= 0, fileSize <= maximumDocumentBytes else {
            throw ThirdPartyDocumentLoaderError.oversizedDocument(relative)
        }
        guard totalBytes <= maximumTotalBytes - fileSize else {
            throw ThirdPartyDocumentLoaderError.oversizedDocument(relative)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == fileSize, let body = String(data: data, encoding: .utf8) else {
            throw ThirdPartyDocumentLoaderError.invalidText(relative)
        }
        totalBytes += data.count
        return ThirdPartyDocument(title: title, body: body)
    }

    private static func relativePath(for url: URL, beneath root: URL) -> String {
        let rootPrefix = root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPrefix) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPrefix.count))
    }

    private static func validateContainedPath(_ url: URL, beneath root: URL) throws -> String {
        let relative = relativePath(for: url, beneath: root)
        let rootPrefix = root.standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(rootPrefix), !relative.isEmpty else {
            throw ThirdPartyDocumentLoaderError.unsafeDocument(url.lastPathComponent)
        }
        var current = root
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component))
            let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw ThirdPartyDocumentLoaderError.unsafeDocument(relative)
            }
        }
        let resolvedRootPrefix = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard
            url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(resolvedRootPrefix)
        else {
            throw ThirdPartyDocumentLoaderError.unsafeDocument(relative)
        }
        return relative
    }
}

@MainActor
final class ThirdPartySoftwareWindowController: NSWindowController {
    init(documents: [ThirdPartyDocument] = ThirdPartyDocumentLoader.applicationDocuments()) {
        let content = ThirdPartySoftwareViewController(documents: documents)
        let window = NSWindow(contentViewController: content)
        window.title = "Third-Party Software"
        window.setContentSize(NSSize(width: 700, height: 560))
        window.minSize = NSSize(width: 560, height: 420)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.configureMKVMagicKeyboardNavigation(
            startingAt: content.preferredInitialFirstResponder
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class ThirdPartySoftwareViewController: NSViewController {
    private let documents: [ThirdPartyDocument]
    private let documentPicker = NSPopUpButton()
    private let documentText = NSTextView()

    var preferredInitialFirstResponder: NSView { documentPicker }

    init(documents: [ThirdPartyDocument]) {
        precondition(!documents.isEmpty)
        self.documents = documents
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let heading = NSTextField(labelWithString: "Third-Party Software")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let introduction = NSTextField(
            wrappingLabelWithString:
                "Review the notices and full license texts shipped inside this copy of MKV Magic."
        )
        introduction.textColor = .secondaryLabelColor

        documentPicker.addItems(withTitles: documents.map(\.title))
        documentPicker.target = self
        documentPicker.action = #selector(selectDocument)
        documentPicker.setAccessibilityLabel("License document")
        documentPicker.setAccessibilityHelp(
            "Choose the packaged notice or license text to read."
        )

        documentText.isEditable = false
        documentText.isRichText = false
        documentText.isSelectable = true
        documentText.drawsBackground = false
        documentText.font = .systemFont(ofSize: 13)
        documentText.textContainerInset = NSSize(width: 8, height: 8)
        documentText.setAccessibilityLabel("Selected license text")
        documentText.setAccessibilityHelp(
            "The complete local text of the selected packaged document."
        )
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = documentText

        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        close.keyEquivalent = "\u{1b}"
        close.setAccessibilityLabel("Close Third-Party Software")
        close.setAccessibilityHelp("Closes the local license viewer.")

        let actions = NSStackView(views: [NSView(), close])
        actions.orientation = .horizontal
        let stack = NSStackView(
            views: [heading, introduction, documentPicker, scroll, actions]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentPicker.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            documentPicker.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        view = root
        selectDocument()
    }

    @objc private func selectDocument() {
        let index = max(0, documentPicker.indexOfSelectedItem)
        documentText.string = documents[index].body
        documentText.scrollToBeginningOfDocument(nil)
    }

    @objc private func closeWindow() {
        view.window?.performClose(nil)
    }
}
