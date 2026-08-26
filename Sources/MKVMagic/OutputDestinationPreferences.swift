import Foundation
import MKVMagicCore
import MKVMagicSystem

enum OutputDestinationMode: String, CaseIterable, Sendable {
    case besideSource
    case chosenFolder
    case askEveryTime

    var title: String {
        switch self {
        case .besideSource: "Beside each source automatically"
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
}

final class OutputDirectorySecurityScope: @unchecked Sendable {
    let directoryURL: URL
    private let accessed: Bool

    init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
        accessed = self.directoryURL.startAccessingSecurityScopedResource()
    }

    deinit {
        if accessed { directoryURL.stopAccessingSecurityScopedResource() }
    }
}

struct ResolvedOutputDestination: @unchecked Sendable {
    let url: URL
    let directoryAccess: OutputDirectorySecurityScope?
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
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> OutputDestinationResolution {
        guard MediaQueueOutputFilenamePolicy.isSafe(suggestedFilename) else {
            throw OutputDestinationPreferenceError.unsafeOutputName
        }
        guard preferences.mode != .askEveryTime else { return .askEveryTime }

        let directoryURL: URL
        switch preferences.mode {
        case .besideSource:
            directoryURL = defaultDirectory(for: sourceURL)
        case .chosenFolder:
            directoryURL = try preferences.resolveChosenFolder()
        case .askEveryTime:
            return .askEveryTime
        }
        let access = OutputDirectorySecurityScope(directoryURL: directoryURL)
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
