import Foundation

public enum MatroskaAttachmentExtractionPolicy {
    public static let maximumAttachmentBytes: Int64 = 536_870_912

    public static func extractableAttachments(in asset: MediaAsset) -> [MediaAttachment] {
        guard MatroskaEditingPolicy.supports(asset), !asset.attachments.isEmpty else { return [] }
        let attachmentIDs = asset.attachments.map(\.id)
        guard attachmentIDs.allSatisfy({ $0 >= 0 }),
            Set(attachmentIDs).count == attachmentIDs.count
        else { return [] }
        let attachmentUIDs = asset.attachments.compactMap(\.uid)
        guard Set(attachmentUIDs).count == attachmentUIDs.count else { return [] }
        return asset.attachments.filter { attachment in
            guard attachment.uid != nil, let size = attachment.size else { return false }
            return (1...maximumAttachmentBytes).contains(size)
        }.sorted { $0.id < $1.id }
    }
}
