import Foundation

public enum MediaFileDiscoveryError: Error, Equatable, Sendable {
    case unsafeRoot
    case enumerationFailed
    case tooManyFiles(limit: Int)
}

extension MediaFileDiscoveryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsafeRoot:
            "The selection contains a symbolic link or an item MKV Magic cannot safely read."
        case .enumerationFailed:
            "macOS could not finish reading the selected folder."
        case .tooManyFiles(let limit):
            "The selection contains more than \(limit) supported files. Choose a smaller folder."
        }
    }
}

public protocol MediaFileDiscovering: Sendable {
    func discover(_ roots: [URL]) async throws -> [URL]
}

public struct LocalMediaFileDiscovery: MediaFileDiscovering {
    public static let defaultFileLimit = 10_000

    private let fileLimit: Int

    public init(fileLimit: Int = LocalMediaFileDiscovery.defaultFileLimit) {
        self.fileLimit = fileLimit
    }

    public func discover(_ roots: [URL]) async throws -> [URL] {
        guard fileLimit > 0 else { throw MediaFileDiscoveryError.tooManyFiles(limit: fileLimit) }
        return try await Task.detached {
            try Self.discoverSynchronously(roots, fileLimit: fileLimit)
        }.value
    }

    private static func discoverSynchronously(_ roots: [URL], fileLimit: Int) throws -> [URL] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        ]
        var files = Set<URL>()
        for rawRoot in roots {
            let root = rawRoot.standardizedFileURL
            guard root.isFileURL, root.path.hasPrefix("/"),
                let values = try? root.resourceValues(forKeys: Set(keys)),
                values.isSymbolicLink != true
            else {
                throw MediaFileDiscoveryError.unsafeRoot
            }
            if values.isRegularFile == true {
                try insert(root, into: &files, limit: fileLimit)
                continue
            }
            guard values.isDirectory == true else {
                throw MediaFileDiscoveryError.unsafeRoot
            }
            var enumerationFailed = false
            guard
                let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in
                        enumerationFailed = true
                        return false
                    }
                )
            else {
                throw MediaFileDiscoveryError.enumerationFailed
            }
            while let candidate = enumerator.nextObject() as? URL {
                guard let candidateValues = try? candidate.resourceValues(forKeys: Set(keys)) else {
                    throw MediaFileDiscoveryError.enumerationFailed
                }
                if candidateValues.isSymbolicLink == true {
                    if candidateValues.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                guard candidateValues.isRegularFile == true,
                    supportedExtensions.contains(candidate.pathExtension.lowercased())
                else {
                    continue
                }
                try insert(candidate.standardizedFileURL, into: &files, limit: fileLimit)
            }
            if enumerationFailed {
                throw MediaFileDiscoveryError.enumerationFailed
            }
        }
        return files.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private static func insert(_ url: URL, into files: inout Set<URL>, limit: Int) throws {
        files.insert(url)
        if files.count > limit { throw MediaFileDiscoveryError.tooManyFiles(limit: limit) }
    }

    private static let supportedExtensions = Set([
        "3g2", "3gp", "aac", "ac3", "aiff", "alac", "ass", "avi", "dts", "eac3",
        "flac", "flv", "idx", "m2ts", "m4a", "m4v", "mka", "mks", "mkv", "mov",
        "mp3", "mp4", "mpeg", "mpg", "mts", "ogg", "ogm", "opus", "srt", "ssa",
        "sub", "ts", "vob", "vtt", "wav", "webm", "webvtt",
    ])
}
