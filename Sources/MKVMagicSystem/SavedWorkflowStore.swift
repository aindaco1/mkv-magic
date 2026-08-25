import Foundation
import MKVMagicCore

public enum SavedWorkflowStoreError: Error, Equatable, Sendable {
    case unsafePath
    case oversizedDocument
    case tooManyWorkflows
    case tooManySteps
    case duplicateWorkflowIdentifier
    case duplicateStepIdentifier
    case duplicateAction
    case unexpectedFields
    case unsupportedSchema
    case malformedWorkflow
}

extension SavedWorkflowStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsafePath: "The workflow path is not a safe regular file location."
        case .oversizedDocument: "The workflow file is larger than MKV Magic allows."
        case .tooManyWorkflows: "The workflow library contains too many workflows."
        case .tooManySteps: "A workflow contains too many steps."
        case .duplicateWorkflowIdentifier: "Two workflows have the same identifier."
        case .duplicateStepIdentifier: "Two workflow steps have the same identifier."
        case .duplicateAction: "Each workflow action can appear only once."
        case .unexpectedFields: "The workflow contains unexpected fields."
        case .unsupportedSchema: "The workflow uses an unsupported schema version."
        case .malformedWorkflow: "The workflow file is malformed."
        }
    }
}

public protocol SavedWorkflowPersisting: Sendable {
    func load() async throws -> [SavedWorkflow]
    func save(_ workflows: [SavedWorkflow]) async throws
}

public actor JSONSavedWorkflowStore: SavedWorkflowPersisting {
    public static let librarySchema = "mkv-magic-workflow-library-v1"
    public static let maximumWorkflows = 256
    public static let maximumStepsPerWorkflow = 64
    public static let maximumDocumentBytes = 1_048_576
    public static let maximumNameBytes = 256

    private let fileURL: URL

    public init(fileURL: URL) throws {
        let standardized = fileURL.standardizedFileURL
        guard standardized.isFileURL,
            standardized.path.hasPrefix("/"),
            !standardized.path.hasSuffix("/"),
            standardized.lastPathComponent == "workflows.json"
        else {
            throw SavedWorkflowStoreError.unsafePath
        }
        self.fileURL = standardized
    }

    public func load() async throws -> [SavedWorkflow] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return SavedWorkflowPresetCatalog.firstRunWorkflows
        }
        let data = try readRegularFile(at: fileURL, maximumBytes: Self.maximumDocumentBytes)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SavedWorkflowStoreError.malformedWorkflow
        }
        guard let document = object as? [String: Any],
            Set(document.keys) == Set(["schema", "workflows"]),
            document["schema"] as? String == Self.librarySchema,
            let workflowObjects = document["workflows"] as? [[String: Any]]
        else {
            if let document = object as? [String: Any],
                document["schema"] as? String != Self.librarySchema
            {
                throw SavedWorkflowStoreError.unsupportedSchema
            }
            throw SavedWorkflowStoreError.unexpectedFields
        }
        try Self.validateJSONWorkflows(workflowObjects)
        let decoded: SavedWorkflowLibrary
        do {
            decoded = try decoder.decode(SavedWorkflowLibrary.self, from: data)
        } catch {
            throw SavedWorkflowStoreError.malformedWorkflow
        }
        let migrated = try Self.migrate(decoded.workflows)
        try Self.validate(migrated)
        return migrated
    }

    public func save(_ workflows: [SavedWorkflow]) async throws {
        try Self.validate(workflows)
        let parent = fileURL.deletingLastPathComponent()
        try ensureSafeDirectory(parent)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try readRegularFile(at: fileURL, maximumBytes: Self.maximumDocumentBytes)
        }
        let data = try encoder.encode(
            SavedWorkflowLibrary(schema: Self.librarySchema, workflows: workflows)
        )
        guard data.count <= Self.maximumDocumentBytes else {
            throw SavedWorkflowStoreError.oversizedDocument
        }
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public static func encodePortableFile(_ workflow: SavedWorkflow) throws -> Data {
        try validate([workflow])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(workflow)
        guard data.count <= maximumDocumentBytes else {
            throw SavedWorkflowStoreError.oversizedDocument
        }
        return data
    }

    public static func decodePortableFile(_ data: Data) throws -> SavedWorkflow {
        guard data.count <= maximumDocumentBytes else {
            throw SavedWorkflowStoreError.oversizedDocument
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SavedWorkflowStoreError.malformedWorkflow
        }
        guard let workflowObject = object as? [String: Any] else {
            throw SavedWorkflowStoreError.malformedWorkflow
        }
        try validateJSONWorkflows([workflowObject])
        let decoded: SavedWorkflow
        do {
            decoded = try JSONDecoder().decode(SavedWorkflow.self, from: data)
        } catch {
            throw SavedWorkflowStoreError.malformedWorkflow
        }
        let workflow = try migrate([decoded])[0]
        try validate([workflow])
        return workflow
    }

    public static func loadPortableFile(at fileURL: URL) throws -> SavedWorkflow {
        let standardized = fileURL.standardizedFileURL
        guard standardized.isFileURL,
            standardized.path.hasPrefix("/"),
            standardized.pathExtension == "mkvmagic-workflow"
        else {
            throw SavedWorkflowStoreError.unsafePath
        }
        let values = try standardized.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw SavedWorkflowStoreError.unsafePath
        }
        guard values.fileSize ?? 0 <= maximumDocumentBytes else {
            throw SavedWorkflowStoreError.oversizedDocument
        }
        return try decodePortableFile(
            Data(contentsOf: standardized, options: [.mappedIfSafe])
        )
    }

    public static func writePortableFile(_ workflow: SavedWorkflow, to fileURL: URL) throws {
        let standardized = fileURL.standardizedFileURL
        guard standardized.isFileURL,
            standardized.path.hasPrefix("/"),
            standardized.pathExtension == "mkvmagic-workflow"
        else {
            throw SavedWorkflowStoreError.unsafePath
        }
        let parent = standardized.deletingLastPathComponent()
        let parentValues = try parent.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard parentValues.isDirectory == true, parentValues.isSymbolicLink != true else {
            throw SavedWorkflowStoreError.unsafePath
        }
        if FileManager.default.fileExists(atPath: standardized.path) {
            let values = try standardized.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw SavedWorkflowStoreError.unsafePath
            }
        }
        try encodePortableFile(workflow).write(to: standardized, options: [.atomic])
    }

    private static func validate(_ workflows: [SavedWorkflow]) throws {
        guard workflows.count <= maximumWorkflows else {
            throw SavedWorkflowStoreError.tooManyWorkflows
        }
        var workflowIDs = Set<UUID>()
        for workflow in workflows {
            guard workflowIDs.insert(workflow.id).inserted else {
                throw SavedWorkflowStoreError.duplicateWorkflowIdentifier
            }
            guard workflow.schemaVersion == SavedWorkflow.currentSchemaVersion else {
                throw SavedWorkflowStoreError.unsupportedSchema
            }
            let name = workflow.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.utf8.count <= maximumNameBytes, !workflow.steps.isEmpty else {
                throw SavedWorkflowStoreError.malformedWorkflow
            }
            guard workflow.steps.count <= maximumStepsPerWorkflow else {
                throw SavedWorkflowStoreError.tooManySteps
            }
            guard Set(workflow.steps.map(\.id)).count == workflow.steps.count else {
                throw SavedWorkflowStoreError.duplicateStepIdentifier
            }
            guard Set(workflow.steps.map(\.action)).count == workflow.steps.count else {
                throw SavedWorkflowStoreError.duplicateAction
            }
        }
    }

    private static func migrate(_ workflows: [SavedWorkflow]) throws -> [SavedWorkflow] {
        do {
            return try workflows.map { try SavedWorkflowMigrator().migrate($0) }
        } catch {
            throw SavedWorkflowStoreError.unsupportedSchema
        }
    }

    private static func validateJSONWorkflows(_ workflows: [[String: Any]]) throws {
        let workflowKeys = Set(["id", "schemaVersion", "name", "steps"])
        let stepKeys = Set(["id", "isEnabled", "action"])
        for workflow in workflows {
            guard Set(workflow.keys) == workflowKeys,
                let steps = workflow["steps"] as? [[String: Any]]
            else {
                throw SavedWorkflowStoreError.unexpectedFields
            }
            for step in steps where Set(step.keys) != stepKeys {
                throw SavedWorkflowStoreError.unexpectedFields
            }
        }
    }

    private func readRegularFile(at url: URL, maximumBytes: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw SavedWorkflowStoreError.unsafePath
        }
        guard values.fileSize ?? 0 <= maximumBytes else {
            throw SavedWorkflowStoreError.oversizedDocument
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func ensureSafeDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw SavedWorkflowStoreError.unsafePath
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private var decoder: JSONDecoder { JSONDecoder() }
}

private struct SavedWorkflowLibrary: Codable {
    let schema: String
    let workflows: [SavedWorkflow]
}
