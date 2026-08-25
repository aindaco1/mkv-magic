import Foundation

public struct MatroskaAttachmentRemoval: Codable, Equatable, Hashable, Sendable {
    public let attachmentUIDs: Set<UInt64>

    public init(attachmentUIDs: Set<UInt64>) {
        self.attachmentUIDs = attachmentUIDs
    }
}

public struct MatroskaAttachmentRemovalResolution: Equatable, Sendable {
    public let removedAttachments: [MediaAttachment]
    public let retainedAttachments: [MediaAttachment]

    public init(
        removedAttachments: [MediaAttachment],
        retainedAttachments: [MediaAttachment]
    ) {
        self.removedAttachments = removedAttachments
        self.retainedAttachments = retainedAttachments
    }
}

public enum MatroskaAttachmentRemovalPolicyError: Error, Equatable, Sendable {
    case unsupportedSource
    case emptySelection
    case unstableAttachmentIdentity
    case attachmentNotFound
    case allContentRemoved
}

extension MatroskaAttachmentRemovalPolicyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Attachment removal requires an inspected Matroska file."
        case .emptySelection:
            "Select at least one attachment to remove."
        case .unstableAttachmentIdentity:
            "Every attachment must have one stable unique Matroska UID and ID."
        case .attachmentNotFound:
            "A selected attachment is no longer present in the inspected file."
        case .allContentRemoved:
            "At least one media track or attachment must remain in the output."
        }
    }
}

public enum MatroskaAttachmentRemovalPolicy {
    public static func removableAttachments(in asset: MediaAsset) -> [MediaAttachment] {
        (try? validatedAttachments(in: asset)) ?? []
    }

    public static func resolve(
        _ removal: MatroskaAttachmentRemoval,
        in asset: MediaAsset
    ) throws -> MatroskaAttachmentRemovalResolution {
        guard !removal.attachmentUIDs.isEmpty else {
            throw MatroskaAttachmentRemovalPolicyError.emptySelection
        }
        let attachments = try validatedAttachments(in: asset)
        let removed = attachments.filter { attachment in
            attachment.uid.map(removal.attachmentUIDs.contains) ?? false
        }
        guard removed.count == removal.attachmentUIDs.count else {
            throw MatroskaAttachmentRemovalPolicyError.attachmentNotFound
        }
        let retained = attachments.filter { attachment in
            !removed.contains(where: { $0.uid == attachment.uid })
        }
        guard !retained.isEmpty || asset.tracks.contains(where: { $0.kind != .attachment }) else {
            throw MatroskaAttachmentRemovalPolicyError.allContentRemoved
        }
        return MatroskaAttachmentRemovalResolution(
            removedAttachments: removed,
            retainedAttachments: retained
        )
    }

    /// Resolves the portable cleanup intent without storing attachment IDs in
    /// the saved recipe. Only attachments explicitly identified as images by
    /// their inspected MIME type are selected; fonts and unknown types remain.
    public static func imageAttachmentRemoval(
        in asset: MediaAsset
    ) throws -> MatroskaAttachmentRemoval? {
        guard MatroskaEditingPolicy.supports(asset) else {
            throw MatroskaAttachmentRemovalPolicyError.unsupportedSource
        }
        guard !asset.attachments.isEmpty else { return nil }
        let images = try validatedAttachments(in: asset).filter { attachment in
            attachment.mimeType?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .hasPrefix("image/") == true
        }
        let identifiers = Set(images.compactMap(\.uid))
        return identifiers.isEmpty
            ? nil : MatroskaAttachmentRemoval(attachmentUIDs: identifiers)
    }

    private static func validatedAttachments(in asset: MediaAsset) throws -> [MediaAttachment] {
        guard MatroskaEditingPolicy.supports(asset), !asset.attachments.isEmpty else {
            throw MatroskaAttachmentRemovalPolicyError.unsupportedSource
        }
        let attachmentIDs = asset.attachments.map(\.id)
        let attachmentUIDs = asset.attachments.compactMap(\.uid)
        guard attachmentIDs.allSatisfy({ $0 >= 0 }),
            Set(attachmentIDs).count == attachmentIDs.count,
            attachmentUIDs.count == asset.attachments.count,
            Set(attachmentUIDs).count == attachmentUIDs.count
        else {
            throw MatroskaAttachmentRemovalPolicyError.unstableAttachmentIdentity
        }
        return asset.attachments.sorted { $0.id < $1.id }
    }
}
