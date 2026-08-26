import Foundation
import MKVMagicCore
import MKVMagicSystem

public enum MKVPropertyEditError: Error, Equatable, Sendable {
    case invalidTitle
    case invalidTrackName
    case invalidLanguage
    case missingTrack
    case noChanges
    case toolFailed(exitCode: Int32, message: String)
}

extension MKVPropertyEditError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidTitle:
            "The segment title is too large or contains an unsupported null character."
        case .invalidTrackName:
            "The track name is too large or contains an unsupported null character."
        case .invalidLanguage:
            "Use a BCP 47 language tag such as en, en-US, es, or und."
        case .missingTrack:
            "The selected track is no longer present in the inspected file."
        case .noChanges:
            "The selected track already has those metadata values."
        case .toolFailed(let exitCode, let message):
            "mkvpropedit could not edit the temporary output (code \(exitCode)): \(message)"
        }
    }
}

public struct MKVPropertyEditor<Runner: CommandRunning>: Sendable {
    private let executableURL: URL
    private let runner: Runner

    public init(executableURL: URL, runner: Runner) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public func editSegmentTitle(
        at fileURL: URL,
        title: String?,
        clearAllTags: Bool = false
    ) async throws {
        if let title {
            guard !title.contains("\0"), title.utf8.count <= 4_096 else {
                throw MKVPropertyEditError.invalidTitle
            }
        }
        var arguments =
            clearAllTags ? ["--abort-on-warnings", fileURL.path] : [fileURL.path]
        arguments.append(contentsOf: ["--edit", "info"])
        if let title {
            arguments.append(contentsOf: ["--set", "title=\(title)"])
        } else {
            arguments.append(contentsOf: ["--delete", "title"])
        }
        if clearAllTags {
            arguments.append(contentsOf: ["--tags", "all:"])
        }
        try await run(arguments: arguments)
    }

    public func clearAllTags(at fileURL: URL) async throws {
        try await run(
            arguments: ["--abort-on-warnings", fileURL.path, "--tags", "all:"]
        )
    }

    public func editTrackMetadata(
        at fileURL: URL,
        originalTrack: MediaTrack,
        edit: TrackMetadataEdit
    ) async throws {
        var arguments = [
            fileURL.path,
            "--normalize-language-ietf", "canonical",
            "--abort-on-warnings",
        ]
        arguments.append(contentsOf: try trackEditArguments(original: originalTrack, edit: edit))
        try await run(arguments: arguments)
    }

    /// Applies every reviewed property change in one mkvpropedit process.
    /// The caller supplies inspected source tracks because portable workflows
    /// deliberately retain no file-specific track identity.
    public func editWorkflowProperties(
        at fileURL: URL,
        originalTracks: [MediaTrack],
        edits: [TrackMetadataEdit],
        removesSegmentTitle: Bool,
        clearAllTags: Bool
    ) async throws {
        guard !edits.isEmpty || removesSegmentTitle || clearAllTags else {
            throw MKVPropertyEditError.noChanges
        }
        guard Set(edits.map(\.trackUID)).count == edits.count else {
            throw MKVPropertyEditError.missingTrack
        }
        var arguments = [
            fileURL.path,
            "--normalize-language-ietf", "canonical",
            "--abort-on-warnings",
        ]
        if removesSegmentTitle {
            arguments.append(contentsOf: ["--edit", "info", "--delete", "title"])
        }
        if clearAllTags {
            arguments.append(contentsOf: ["--tags", "all:"])
        }
        for edit in edits {
            guard
                let originalTrack = originalTracks.first(where: { $0.uid == edit.trackUID }),
                originalTracks.filter({ $0.uid == edit.trackUID }).count == 1
            else {
                throw MKVPropertyEditError.missingTrack
            }
            arguments.append(
                contentsOf: try trackEditArguments(original: originalTrack, edit: edit)
            )
        }
        try await run(arguments: arguments)
    }

    private func trackEditArguments(
        original originalTrack: MediaTrack,
        edit: TrackMetadataEdit
    ) throws -> [String] {
        guard originalTrack.uid == edit.trackUID else { throw MKVPropertyEditError.missingTrack }
        if let name = edit.name {
            guard !name.contains("\0"), name.utf8.count <= 4_096 else {
                throw MKVPropertyEditError.invalidTrackName
            }
        }
        let language = try TrackLanguageTag.canonical(edit.language)
        var arguments = ["--edit", "track:=\(edit.trackUID)"]
        if edit.name != originalTrack.title {
            if let name = edit.name {
                arguments.append(contentsOf: ["--set", "name=\(name)"])
            } else {
                arguments.append(contentsOf: ["--delete", "name"])
            }
        }
        let originalLanguage = try TrackLanguageTag.canonical(originalTrack.language ?? "und")
        if language != originalLanguage {
            arguments.append(contentsOf: ["--set", "language=\(language)"])
        }
        appendFlagChange(
            name: "flag-default", original: originalTrack.isDefault,
            desired: edit.isDefault, to: &arguments)
        appendFlagChange(
            name: "flag-forced", original: originalTrack.isForced,
            desired: edit.isForced, to: &arguments)
        appendFlagChange(
            name: "flag-enabled", original: originalTrack.isEnabled,
            desired: edit.isEnabled, to: &arguments)
        appendFlagChange(
            name: "flag-commentary", original: originalTrack.isCommentary,
            desired: edit.isCommentary, to: &arguments)
        appendFlagChange(
            name: "flag-hearing-impaired", original: originalTrack.isHearingImpaired,
            desired: edit.isHearingImpaired, to: &arguments)
        appendFlagChange(
            name: "flag-visual-impaired", original: originalTrack.isVisualImpaired,
            desired: edit.isVisualImpaired, to: &arguments)
        appendFlagChange(
            name: "flag-original", original: originalTrack.isOriginal,
            desired: edit.isOriginal, to: &arguments)
        appendFlagChange(
            name: "flag-text-descriptions", original: originalTrack.isTextDescription,
            desired: edit.isTextDescription, to: &arguments)
        guard arguments.count > 2 else { throw MKVPropertyEditError.noChanges }
        return arguments
    }

    private func appendFlagChange(
        name: String,
        original: Bool,
        desired: Bool,
        to arguments: inout [String]
    ) {
        guard original != desired else { return }
        arguments.append(contentsOf: ["--set", "\(name)=\(desired ? 1 : 0)"])
    }

    private func run(arguments: [String]) async throws {
        let result = try await runner.run(
            CommandRequest(
                executableURL: executableURL,
                arguments: arguments,
                timeout: 120,
                outputLimit: 1_048_576
            )
        )
        guard result.exitCode == 0,
            !result.standardOutput.wasTruncated,
            !result.standardError.wasTruncated
        else {
            throw MKVPropertyEditError.toolFailed(
                exitCode: result.exitCode,
                message: result.conciseFailureMessage
            )
        }
    }
}

public enum TrackLanguageTag {
    public static func canonical(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 35,
            trimmed.unicodeScalars.allSatisfy({ scalar in
                scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
            })
        else {
            throw MKVPropertyEditError.invalidLanguage
        }
        let rawParts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard let first = rawParts.first, (2...8).contains(first.count),
            first.allSatisfy(\.isLetter),
            rawParts.allSatisfy({ !$0.isEmpty && $0.count <= 8 })
        else {
            throw MKVPropertyEditError.invalidLanguage
        }

        var parts = rawParts.map(String.init)
        var primary =
            bibliographicPrimaryLanguage[parts[0].lowercased()]
            ?? parts[0].lowercased()
        if primary != "und" {
            let preferred = Locale.Language(identifier: primary).minimalIdentifier
            if preferred.count == 2 { primary = preferred }
        }
        parts[0] = primary
        for index in parts.indices.dropFirst() {
            let part = parts[index]
            if part.count == 4, part.allSatisfy(\.isLetter) {
                parts[index] = part.prefix(1).uppercased() + part.dropFirst().lowercased()
            } else if part.count == 2, part.allSatisfy(\.isLetter) {
                parts[index] = part.uppercased()
            } else {
                parts[index] = part.lowercased()
            }
        }
        return parts.joined(separator: "-")
    }

    private static let bibliographicPrimaryLanguage = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho",
        "cze": "ces", "dut": "nld", "fre": "fra", "geo": "kat", "ger": "deu",
        "gre": "ell", "ice": "isl", "mac": "mkd", "mao": "mri", "may": "msa",
        "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod", "wel": "cym",
    ]
}
