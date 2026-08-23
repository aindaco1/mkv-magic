import Foundation
import MKVMagicSystem

enum AppHistoryLocationError: Error, Equatable {
    case unsafeApplicationSupport
}

enum AppHistoryLocation {
    static func makeStore(
        fileManager: FileManager = .default,
        applicationSupportURL explicitApplicationSupportURL: URL? = nil
    ) throws -> JSONJobHistoryStore {
        let applicationSupportURL: URL
        if let explicitApplicationSupportURL {
            applicationSupportURL = explicitApplicationSupportURL.standardizedFileURL
        } else {
            applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).standardizedFileURL
        }
        guard applicationSupportURL.isFileURL,
            applicationSupportURL.path.hasPrefix("/"),
            try isSafeDirectory(applicationSupportURL)
        else {
            throw AppHistoryLocationError.unsafeApplicationSupport
        }

        let appDirectory = applicationSupportURL.appendingPathComponent(
            "com.dustwave.mkvmagic",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: appDirectory.path) {
            guard try isSafeDirectory(appDirectory) else {
                throw AppHistoryLocationError.unsafeApplicationSupport
            }
        } else {
            try fileManager.createDirectory(
                at: appDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: appDirectory.path
        )
        return try JSONJobHistoryStore(
            fileURL: appDirectory.appendingPathComponent("job-history.json"))
    }

    private static func isSafeDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values.isDirectory == true && values.isSymbolicLink != true
    }
}
