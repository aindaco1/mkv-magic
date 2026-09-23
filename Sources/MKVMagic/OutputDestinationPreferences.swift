import AppKit
import MKVMagicCore
import MKVMagicSystem

enum OutputDestinationMode: String, CaseIterable, Sendable {
    case besideSource
    case chosenFolder
    case askEveryTime

    var title: String {
        switch self {
        case .besideSource: "Beside source when access is available"
        case .chosenFolder: "In one chosen folder automatically"
        case .askEveryTime: "Ask where to save every time"
        }
    }
}

enum OutputDestinationPreferenceError: Error, Equatable {
    case unavailableChosenFolder
    case unsafeOutputName
    case noAvailableOutputName
}

extension OutputDestinationPreferenceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailableChosenFolder:
            "The chosen output folder is unavailable. Open Settings and choose it again."
        case .unsafeOutputName:
            "MKV Magic could not create a safe output filename."
        case .noAvailableOutputName:
            "MKV Magic could not find an unused output filename in that folder."
        }
    }
}

@MainActor
final class OutputDestinationPreferences {
    private enum Key {
        static let mode = "outputDestination.mode.v1"
        static let folderBookmark = "outputDestination.folderBookmark.v1"
        static let folderDisplayName = "outputDestination.folderDisplayName.v1"
        static let authorizedFolders = "outputDestination.authorizedFolders.v1"
        static let exportFolder = "outputDestination.exportFolder.v1"
    }

    private let defaults: UserDefaults
    private let bookmarkCodec: SecurityScopedBookmarkCodec

    init(
        defaults: UserDefaults = .standard,
        bookmarkCodec: SecurityScopedBookmarkCodec = SecurityScopedBookmarkCodec()
    ) {
        self.defaults = defaults
        self.bookmarkCodec = bookmarkCodec
    }

    var mode: OutputDestinationMode {
        get {
            defaults.string(forKey: Key.mode).flatMap(OutputDestinationMode.init(rawValue:))
                ?? .besideSource
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.mode)
        }
    }

    var chosenFolderDisplayName: String? {
        defaults.string(forKey: Key.folderDisplayName)
    }

    var hasChosenFolder: Bool {
        defaults.data(forKey: Key.folderBookmark) != nil
    }

    func chooseFolder(_ directoryURL: URL) throws {
        let reference = try bookmarkCodec.makeReference(
            for: directoryURL,
            access: .readWriteDirectory
        )
        defaults.set(reference.securityScopedBookmark, forKey: Key.folderBookmark)
        defaults.set(reference.displayName, forKey: Key.folderDisplayName)
        mode = .chosenFolder
    }

    func resolveChosenFolder() throws -> URL {
        guard let bookmark = defaults.data(forKey: Key.folderBookmark) else {
            throw OutputDestinationPreferenceError.unavailableChosenFolder
        }
        do {
            return try bookmarkCodec.resolve(
                MediaQueueFileReference(
                    displayName: chosenFolderDisplayName ?? "Output Folder",
                    securityScopedBookmark: bookmark
                ),
                access: .readWriteDirectory
            )
        } catch {
            throw OutputDestinationPreferenceError.unavailableChosenFolder
        }
    }

    func rememberAuthorizedFolder(_ url: URL, forExports: Bool = false) throws {
        let reference = try bookmarkCodec.makeReference(for: url, access: .readWriteDirectory)
        let previous = defaults.array(forKey: Key.authorizedFolders) as? [Data] ?? []
        let retained = previous.filter { bookmark in
            guard let resolved = try? resolveBookmark(bookmark) else { return false }
            return resolved.standardizedFileURL != url.standardizedFileURL
        }
        defaults.set(
            Array(([reference.securityScopedBookmark] + retained).prefix(16)),
            forKey: Key.authorizedFolders)
        if forExports { defaults.set(reference.securityScopedBookmark, forKey: Key.exportFolder) }
    }

    func authorizedFolder(matching url: URL) -> URL? {
        (defaults.array(forKey: Key.authorizedFolders) as? [Data] ?? []).compactMap {
            try? resolveBookmark($0)
        }.first { $0.standardizedFileURL == url.standardizedFileURL }
    }

    func exportFolder() -> URL? {
        defaults.data(forKey: Key.exportFolder).flatMap { try? resolveBookmark($0) }
    }

    private func resolveBookmark(_ data: Data) throws -> URL {
        try bookmarkCodec.resolve(
            MediaQueueFileReference(
                displayName: "Output Folder",
                securityScopedBookmark: data), access: .readWriteDirectory)
    }
}

final class OutputDirectorySecurityScope: @unchecked Sendable {
    private let access: SecurityScopedResourceAccess
    var directoryURL: URL { access.url }

    init?(
        directoryURL: URL,
        startAccessing: @Sendable (URL) -> Bool = {
            $0.startAccessingSecurityScopedResource()
        },
        stopAccessing: @escaping @Sendable (URL) -> Void = {
            $0.stopAccessingSecurityScopedResource()
        }
    ) {
        guard
            let access = SecurityScopedResourceAccess(
                url: directoryURL, startAccessing: startAccessing, stopAccessing: stopAccessing)
        else { return nil }
        self.access = access
    }
}

struct ResolvedOutputDestination: @unchecked Sendable {
    let url: URL
    let directoryAccess: OutputDirectorySecurityScope?
}

/// NSSavePanel grants the output file, not necessarily its parent directory.
/// Verified temporary copies and durable queue bookmarks both need that folder.
@MainActor
enum OutputDirectoryAuthorization {
    static func authorize(
        destinationURL: URL,
        requestAccess: @MainActor (URL) -> URL? = requestFolder,
        acquire: (URL) -> OutputDirectorySecurityScope? = {
            OutputDirectorySecurityScope(directoryURL: $0)
        }
    ) throws -> OutputDirectorySecurityScope? {
        let parent = destinationURL.deletingLastPathComponent()
        if let existing = acquire(parent) { return existing }
        guard let selected = requestAccess(parent) else { return nil }
        guard selected.standardizedFileURL == parent.standardizedFileURL,
            let access = acquire(selected)
        else { throw OutputDestinationPreferenceError.unavailableChosenFolder }
        return access
    }

    private static func requestFolder(_ directory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Allow Access to Output Folder"
        panel.message =
            "Select the output folder \(directory.lastPathComponent) so MKV Magic can create a temporary verified copy and save this job in the queue. Your originals stay unchanged."
        panel.prompt = "Allow Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }
}

enum OutputDestinationResolution: @unchecked Sendable {
    case askEveryTime
    case automatic(ResolvedOutputDestination)
}

enum OutputDestinationPolicy {
    static func defaultDirectory(for sourceURL: URL) -> URL {
        sourceURL.standardizedFileURL.deletingLastPathComponent()
    }

    @MainActor
    static func resolve(
        sourceURL: URL,
        suggestedFilename: String,
        preferences: OutputDestinationPreferences,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        directoryAccessProvider: (URL) -> OutputDirectorySecurityScope? = {
            OutputDirectorySecurityScope(directoryURL: $0)
        }
    ) throws -> OutputDestinationResolution {
        guard MediaQueueOutputFilenamePolicy.isSafe(suggestedFilename) else {
            throw OutputDestinationPreferenceError.unsafeOutputName
        }
        guard preferences.mode != .askEveryTime else { return .askEveryTime }

        let directoryURL: URL
        let access: OutputDirectorySecurityScope
        switch preferences.mode {
        case .besideSource:
            let parent = defaultDirectory(for: sourceURL)
            directoryURL = preferences.authorizedFolder(matching: parent) ?? parent
            guard let grantedAccess = directoryAccessProvider(directoryURL) else {
                return .askEveryTime
            }
            access = grantedAccess
        case .chosenFolder:
            directoryURL = try preferences.resolveChosenFolder()
            guard let grantedAccess = directoryAccessProvider(directoryURL) else {
                throw OutputDestinationPreferenceError.unavailableChosenFolder
            }
            access = grantedAccess
        case .askEveryTime:
            return .askEveryTime
        }
        let outputURL = try availableOutputURL(
            filename: suggestedFilename,
            directoryURL: directoryURL,
            fileExists: fileExists
        )
        return .automatic(
            ResolvedOutputDestination(url: outputURL, directoryAccess: access)
        )
    }

    static func savePanelMessage(detail: String? = nil) -> String {
        let location = "Choose the output location. You can change this behavior in Settings."
        guard let detail, !detail.isEmpty else { return location }
        return "\(location) \(detail)"
    }

    static func availableOutputURL(
        filename: String,
        directoryURL: URL,
        fileExists: (String) -> Bool
    ) throws -> URL {
        guard
            let initial = MediaQueueOutputFilenamePolicy.outputURL(
                filename: filename,
                in: directoryURL
            )
        else {
            throw OutputDestinationPreferenceError.unsafeOutputName
        }
        guard fileExists(initial.path) else { return initial }

        let filenameURL = URL(fileURLWithPath: filename)
        let fileExtension = filenameURL.pathExtension
        let base = filenameURL.deletingPathExtension().lastPathComponent
        for ordinal in 2...10_000 {
            let candidateName =
                fileExtension.isEmpty
                ? "\(base) \(ordinal)"
                : "\(base) \(ordinal).\(fileExtension)"
            guard
                let candidate = MediaQueueOutputFilenamePolicy.outputURL(
                    filename: candidateName,
                    in: directoryURL
                )
            else {
                throw OutputDestinationPreferenceError.unsafeOutputName
            }
            if !fileExists(candidate.path) { return candidate }
        }
        throw OutputDestinationPreferenceError.noAvailableOutputName
    }
}
