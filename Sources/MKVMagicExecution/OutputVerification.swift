import Foundation
import MKVMagicCore

public enum OutputVerificationError: Error, Equatable, Sendable {
    case emptyOutput
    case titleMismatch
    case containerChanged
    case durationChanged
    case tracksChanged
    case chaptersChanged
    case attachmentsChanged
    case tagsChanged
    case segmentIdentityChanged
}

extension OutputVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyOutput: "The output is empty."
        case .titleMismatch: "The output segment title does not match the preview."
        case .containerChanged: "The output container changed unexpectedly."
        case .durationChanged: "The output duration changed during a metadata-only edit."
        case .tracksChanged: "One or more tracks changed during a metadata-only edit."
        case .chaptersChanged: "The chapters changed during a metadata-only edit."
        case .attachmentsChanged: "The attachments changed during a metadata-only edit."
        case .tagsChanged: "Unrelated tags changed during a metadata-only edit."
        case .segmentIdentityChanged: "The Matroska segment identity changed unexpectedly."
        }
    }
}

public struct SegmentTitleOutputVerifier: Sendable {
    public init() {}

    public func verify(original: MediaAsset, output: MediaAsset, expectedTitle: String?) throws {
        guard output.fileSize ?? 0 > 0 else { throw OutputVerificationError.emptyOutput }
        guard output.metadata.titleValue == expectedTitle else {
            throw OutputVerificationError.titleMismatch
        }
        guard output.container == original.container else {
            throw OutputVerificationError.containerChanged
        }
        guard Self.durationsMatch(original.duration, output.duration) else {
            throw OutputVerificationError.durationChanged
        }
        guard output.tracks == original.tracks else {
            throw OutputVerificationError.tracksChanged
        }
        guard output.chapters.chapterSnapshots == original.chapters.chapterSnapshots,
            output.chapterEntryCount == original.chapterEntryCount
        else {
            throw OutputVerificationError.chaptersChanged
        }
        guard output.attachments == original.attachments else {
            throw OutputVerificationError.attachmentsChanged
        }
        guard output.metadata.removingTitle == original.metadata.removingTitle,
            output.globalTagCount == original.globalTagCount,
            output.trackTagCount == original.trackTagCount
        else {
            throw OutputVerificationError.tagsChanged
        }
        guard output.segmentUID == original.segmentUID else {
            throw OutputVerificationError.segmentIdentityChanged
        }
    }

    private static func durationsMatch(_ lhs: MediaTime?, _ rhs: MediaTime?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (.some(let lhs), .some(let rhs)):
            abs(lhs.nanoseconds - rhs.nanoseconds) <= 1_000_000
        default: false
        }
    }
}

private struct ChapterSnapshot: Equatable {
    let title: String
    let start: MediaTime
    let end: MediaTime?
    let language: String?
    let children: [ChapterSnapshot]
}

extension Array where Element == ChapterNode {
    fileprivate var chapterSnapshots: [ChapterSnapshot] {
        map {
            ChapterSnapshot(
                title: $0.title,
                start: $0.start,
                end: $0.end,
                language: $0.language,
                children: $0.children.chapterSnapshots
            )
        }
    }
}

extension Dictionary where Key == String, Value == String {
    fileprivate var titleValue: String? {
        first { $0.key.caseInsensitiveCompare("title") == .orderedSame }?.value
    }

    fileprivate var removingTitle: [String: String] {
        filter { $0.key.caseInsensitiveCompare("title") != .orderedSame }
    }
}
