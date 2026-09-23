import Foundation

/// Development evidence from explicitly registered synthetic tests only.
/// Never export a model, path, log, media payload, or arbitrary user fixture.
enum WorkflowEvidence {
    static func record(
        _ id: String, facts: [String: Bool], explanation: String
    ) throws {
        guard let path = ProcessInfo.processInfo.environment["MKV_MAGIC_WORKFLOW_EVIDENCE"] else {
            return
        }
        guard path.hasPrefix("/"),
            !id.isEmpty,
            id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { throw CocoaError(.fileWriteInvalidFileName) }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let data = try JSONSerialization.data(
            withJSONObject: [
                "schema": "mkv-magic.workflow-evidence.v1",
                "id": id,
                "facts": facts,
                "explanation": explanation,
            ], options: [.prettyPrinted, .sortedKeys])
        guard data.count <= 16_384 else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(
            to: directory.appendingPathComponent(id + ".json"), options: .withoutOverwriting)
    }
}
