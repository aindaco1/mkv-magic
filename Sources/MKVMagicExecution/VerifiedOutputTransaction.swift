import Darwin
import Foundation

public enum OutputTransactionError: Error, Equatable, Sendable {
    case unsafeSource
    case unsafeDestination
    case destinationExists
    case invalidState
    case cloneFailed(code: Int32)
    case commitFailed(code: Int32)
}

extension OutputTransactionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsafeSource:
            "The source is not a safe regular file."
        case .unsafeDestination:
            "The output location is not safe or writable."
        case .destinationExists:
            "An item already exists at the output location. Choose another name."
        case .invalidState:
            "The output transaction is not ready for that operation."
        case .cloneFailed(let code):
            "MKV Magic could not create its temporary working copy (code \(code))."
        case .commitFailed(let code):
            "The verified output could not be committed (code \(code))."
        }
    }
}

public actor VerifiedOutputTransaction {
    private enum State {
        case initialized
        case prepared
        case verified
        case committed
        case cancelled
    }

    public let sourceURL: URL
    public let destinationURL: URL

    private let fileManager = FileManager.default
    private var state = State.initialized
    private var replacementDirectoryURL: URL?
    private var temporaryOutputURL: URL?
    private var originalPermissions: Int = 0o644

    public init(sourceURL: URL, destinationURL: URL) {
        self.sourceURL = sourceURL.standardizedFileURL
        self.destinationURL = destinationURL.standardizedFileURL
    }

    public func prepareClone() throws -> URL {
        guard state == .initialized else { throw OutputTransactionError.invalidState }
        try validatePaths()

        let replacementDirectory: URL
        do {
            replacementDirectory = try fileManager.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: destinationURL,
                create: true
            )
        } catch {
            throw OutputTransactionError.unsafeDestination
        }
        let temporaryOutput = replacementDirectory.appendingPathComponent(
            temporaryFilename(),
            isDirectory: false
        )
        guard !fileManager.fileExists(atPath: temporaryOutput.path) else {
            try? fileManager.removeItem(at: replacementDirectory)
            throw OutputTransactionError.unsafeDestination
        }

        let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        originalPermissions = attributes[.posixPermissions] as? Int ?? 0o644
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE)
        guard copyfile(sourceURL.path, temporaryOutput.path, nil, flags) == 0 else {
            let code = errno
            try? fileManager.removeItem(at: replacementDirectory)
            throw OutputTransactionError.cloneFailed(code: code)
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: originalPermissions | 0o200],
                ofItemAtPath: temporaryOutput.path
            )
        } catch {
            try? fileManager.removeItem(at: replacementDirectory)
            throw OutputTransactionError.cloneFailed(code: EACCES)
        }

        replacementDirectoryURL = replacementDirectory
        temporaryOutputURL = temporaryOutput
        state = .prepared
        return temporaryOutput
    }

    public func markVerified() throws {
        guard state == .prepared, let temporaryOutputURL else {
            throw OutputTransactionError.invalidState
        }
        let values = try temporaryOutputURL.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true,
            values.isSymbolicLink != true,
            values.fileSize ?? 0 > 0
        else {
            throw OutputTransactionError.invalidState
        }
        state = .verified
    }

    public func commit() throws -> URL {
        guard state == .verified,
            let temporaryOutputURL,
            let replacementDirectoryURL
        else {
            throw OutputTransactionError.invalidState
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw OutputTransactionError.destinationExists
        }
        try fileManager.setAttributes(
            [.posixPermissions: originalPermissions],
            ofItemAtPath: temporaryOutputURL.path
        )
        guard renamex_np(temporaryOutputURL.path, destinationURL.path, UInt32(RENAME_EXCL)) == 0
        else {
            let code = errno
            if code == EEXIST { throw OutputTransactionError.destinationExists }
            throw OutputTransactionError.commitFailed(code: code)
        }
        try? fileManager.removeItem(at: replacementDirectoryURL)
        self.replacementDirectoryURL = nil
        self.temporaryOutputURL = nil
        state = .committed
        return destinationURL
    }

    public func cancel() {
        guard state != .committed, state != .cancelled else { return }
        if let replacementDirectoryURL {
            try? fileManager.removeItem(at: replacementDirectoryURL)
        }
        replacementDirectoryURL = nil
        temporaryOutputURL = nil
        state = .cancelled
    }

    private func validatePaths() throws {
        guard sourceURL.isFileURL,
            sourceURL.path.hasPrefix("/"),
            let sourceValues = try? sourceURL.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            sourceValues.isRegularFile == true,
            sourceValues.isSymbolicLink != true
        else {
            throw OutputTransactionError.unsafeSource
        }
        guard destinationURL.isFileURL,
            destinationURL.path.hasPrefix("/"),
            destinationURL != sourceURL,
            !destinationURL.lastPathComponent.isEmpty
        else {
            throw OutputTransactionError.unsafeDestination
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw OutputTransactionError.destinationExists
        }
        let parent = destinationURL.deletingLastPathComponent()
        guard
            let parentValues = try? parent.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey,
            ]),
            parentValues.isDirectory == true,
            parentValues.isSymbolicLink != true
        else {
            throw OutputTransactionError.unsafeDestination
        }
    }

    /// Keep third-party tools away from user-controlled or non-ASCII working-copy names.
    /// The verified file is still committed to the exact destination the user selected.
    private func temporaryFilename() -> String {
        let allowed = CharacterSet.alphanumerics
        let fileExtension =
            [destinationURL.pathExtension, sourceURL.pathExtension]
            .first { candidate in
                !candidate.isEmpty
                    && candidate.utf8.count <= 16
                    && candidate.unicodeScalars.allSatisfy {
                        $0.isASCII && allowed.contains($0)
                    }
            }?
            .lowercased() ?? "mkv"
        return "working-copy.\(fileExtension)"
    }
}
