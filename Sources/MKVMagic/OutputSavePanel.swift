import AppKit

/// One destination decision for every output and export. Panel configuration
/// supplies the suggested name/type; only Ask Every Time presents a save panel.
@MainActor
enum OutputSavePanel {
    static func exportMessage(for url: URL) -> String {
        "Exported \(url.lastPathComponent) in \(url.deletingLastPathComponent().lastPathComponent)."
    }

    static func choose(
        _ panel: NSSavePanel,
        sourceURL: URL? = nil,
        preferences: OutputDestinationPreferences = OutputDestinationPreferences(),
        acquire: @MainActor (URL) -> OutputDirectorySecurityScope? = {
            OutputDirectorySecurityScope(directoryURL: $0)
        },
        presentSave: @MainActor (NSSavePanel) -> URL? = {
            $0.runModal() == .OK ? $0.url : nil
        },
        requestExportFolder: @MainActor () -> URL? = chooseExportFolder
    ) throws -> ResolvedOutputDestination? {
        if preferences.mode != .askEveryTime {
            if let sourceURL {
                switch try OutputDestinationPolicy.resolve(
                    sourceURL: sourceURL,
                    suggestedFilename: panel.nameFieldStringValue, preferences: preferences,
                    directoryAccessProvider: acquire)
                {
                case .automatic(let destination): return destination
                case .askEveryTime: break  // Folder permission is missing, not a filename choice.
                }
            }
            let directory: URL?
            if preferences.mode == .chosenFolder {
                directory = try preferences.resolveChosenFolder()
            } else {
                directory =
                    sourceURL.map(OutputDestinationPolicy.defaultDirectory)
                    ?? preferences.exportFolder() ?? requestExportFolder()
            }
            guard let directory else { return nil }
            let proposed = try OutputDestinationPolicy.availableOutputURL(
                filename: panel.nameFieldStringValue, directoryURL: directory,
                fileExists: { FileManager.default.fileExists(atPath: $0) })
            return try authorized(
                proposed, capabilityURL: directory, preferences: preferences,
                forExports: sourceURL == nil, acquire: acquire)
        }
        guard let url = presentSave(panel) else { return nil }
        return try authorized(
            url,
            capabilityURL: preferences.authorizedFolder(matching: url.deletingLastPathComponent()),
            preferences: preferences, forExports: sourceURL == nil,
            acquire: acquire)
    }

    private static func authorized(
        _ url: URL, capabilityURL: URL?, preferences: OutputDestinationPreferences,
        forExports: Bool,
        acquire: @MainActor (URL) -> OutputDirectorySecurityScope?
    ) throws -> ResolvedOutputDestination? {
        let held = capabilityURL.flatMap(acquire)
        guard
            let access = try held
                ?? OutputDirectoryAuthorization.authorize(destinationURL: url, acquire: acquire)
        else { return nil }
        try preferences.rememberAuthorizedFolder(access.directoryURL, forExports: forExports)
        // Recheck after permission is active; a denied existence check must not
        // turn an automatic export into an overwrite of an existing user file.
        let output = try OutputDestinationPolicy.availableOutputURL(
            filename: url.lastPathComponent, directoryURL: access.directoryURL,
            fileExists: { FileManager.default.fileExists(atPath: $0) })
        return ResolvedOutputDestination(url: output, directoryAccess: access)
    }

    private static func chooseExportFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Default Export Folder"
        panel.message =
            "Choose a folder for reports and workflow exports. MKV Magic will remember it. Media outputs still follow your output setting."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
