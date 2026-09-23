import Darwin
import Foundation

/// Commit small local exports without replacing a file created after name
/// selection. Media outputs keep their richer verified-output transaction.
public enum LocalExportWriter {
    public static func write(_ data: Data, to destination: URL) throws {
        guard destination.isFileURL, destination.path.hasPrefix("/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let manager = FileManager.default
        let parent = try destination.deletingLastPathComponent().resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard parent.isDirectory == true, parent.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let directory = try manager.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: destination, create: true)
        defer { try? manager.removeItem(at: directory) }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent("export")
        try data.write(to: temporary, options: .withoutOverwriting)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
