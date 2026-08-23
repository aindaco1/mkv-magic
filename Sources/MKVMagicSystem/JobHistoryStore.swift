import Foundation
import MKVMagicCore

public enum JobHistoryStoreError: Error, Equatable, Sendable {
    case unsafePath
    case oversizedDocument
    case tooManyRecords
    case unexpectedFields
    case unsupportedSchema
    case malformedRecord
}

public protocol JobHistoryPersisting: Sendable {
    func load() async throws -> [MediaJobRecord]
    func save(_ records: [MediaJobRecord]) async throws
}

public actor JSONJobHistoryStore: JobHistoryPersisting {
    public static let currentSchema = "mkv-magic-job-history-v1"
    public static let maximumRecords = 10_000
    public static let maximumDocumentBytes = 16_777_216

    private let fileURL: URL

    public init(fileURL: URL) throws {
        let standardized = fileURL.standardizedFileURL
        guard standardized.isFileURL,
            standardized.path.hasPrefix("/"),
            !standardized.path.hasSuffix("/"),
            standardized.lastPathComponent == "job-history.json"
        else {
            throw JobHistoryStoreError.unsafePath
        }
        self.fileURL = standardized
    }

    public func load() async throws -> [MediaJobRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let values = try fileURL.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw JobHistoryStoreError.unsafePath
        }
        guard values.fileSize ?? 0 <= Self.maximumDocumentBytes else {
            throw JobHistoryStoreError.oversizedDocument
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard let topLevel = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(topLevel.keys) == Set(["records", "schema"])
        else {
            throw JobHistoryStoreError.unexpectedFields
        }
        let document = try decoder.decode(JobHistoryDocument.self, from: data)
        guard document.schema == Self.currentSchema else {
            throw JobHistoryStoreError.unsupportedSchema
        }
        try validate(document.records)
        return document.records
    }

    public func save(_ records: [MediaJobRecord]) async throws {
        try validate(records)
        let parent = fileURL.deletingLastPathComponent()
        let parentValues = try parent.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard parentValues.isDirectory == true, parentValues.isSymbolicLink != true else {
            throw JobHistoryStoreError.unsafePath
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let values = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw JobHistoryStoreError.unsafePath
            }
        }
        let data = try encoder.encode(
            JobHistoryDocument(schema: Self.currentSchema, records: records))
        guard data.count <= Self.maximumDocumentBytes else {
            throw JobHistoryStoreError.oversizedDocument
        }
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func validate(_ records: [MediaJobRecord]) throws {
        guard records.count <= Self.maximumRecords else {
            throw JobHistoryStoreError.tooManyRecords
        }
        var ids = Set<UUID>()
        for record in records {
            guard record.schemaVersion == MediaJobRecord.currentSchemaVersion,
                ids.insert(record.id).inserted,
                !record.inputs.isEmpty,
                !record.events.isEmpty,
                record.events.first?.state == .queued,
                record.events.first?.timestamp == record.createdAt
            else {
                throw JobHistoryStoreError.malformedRecord
            }
            var previousTimestamp = record.createdAt
            for event in record.events {
                guard event.timestamp >= previousTimestamp else {
                    throw JobHistoryStoreError.malformedRecord
                }
                previousTimestamp = event.timestamp
            }
            var replay = MediaJobRecord(
                schemaVersion: record.schemaVersion,
                id: record.id,
                createdAt: record.createdAt,
                workflowID: record.workflowID,
                workflowName: record.workflowName,
                inputs: record.inputs,
                outputDisplayName: record.outputDisplayName
            )
            do {
                for event in record.events.dropFirst() {
                    try replay.transition(
                        to: event.state,
                        at: event.timestamp,
                        message: event.message
                    )
                }
            } catch {
                throw JobHistoryStoreError.malformedRecord
            }
            guard replay.state == record.state, replay.updatedAt == record.updatedAt else {
                throw JobHistoryStoreError.malformedRecord
            }
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private struct JobHistoryDocument: Codable {
    let schema: String
    let records: [MediaJobRecord]
}
