import CryptoKit
import Foundation
import MKVMagicCore

public enum BundledTool: String, Codable, CaseIterable, Hashable, Sendable {
    case ffmpeg
    case ffprobe
    case mkvmerge
    case mkvpropedit
    case mkvextract
}

public enum ToolArchitecture: String, Codable, CaseIterable, Hashable, Sendable {
    case arm64
    case x86_64

    public static var current: ToolArchitecture? {
        #if arch(arm64)
            .arm64
        #elseif arch(x86_64)
            .x86_64
        #else
            nil
        #endif
    }
}

public enum ToolRuntimeArchitecture: String, Codable, CaseIterable, Hashable, Sendable {
    case universal
}

public struct ToolManifestEntry: Codable, Hashable, Sendable {
    public let name: BundledTool
    public let path: String
    public let version: String
    public let sha256: String
    public let license: String
    public let source: URL

    public init(
        name: BundledTool,
        path: String,
        version: String,
        sha256: String,
        license: String,
        source: URL
    ) {
        self.name = name
        self.path = path
        self.version = version
        self.sha256 = sha256
        self.license = license
        self.source = source
    }
}

public struct ToolLibraryManifestEntry: Codable, Hashable, Sendable {
    public let path: String
    public let sha256: String
    public let license: String
    public let source: URL

    public init(path: String, sha256: String, license: String, source: URL) {
        self.path = path
        self.sha256 = sha256
        self.license = license
        self.source = source
    }
}

public struct ToolManifest: Codable, Hashable, Sendable {
    public static let currentSchema = "mkv-magic-tool-manifest-v2"

    public let schema: String
    public let platform: String
    public let architecture: ToolRuntimeArchitecture
    public let tools: [ToolManifestEntry]
    public let libraries: [ToolLibraryManifestEntry]

    public init(
        schema: String = ToolManifest.currentSchema,
        platform: String = "macos",
        architecture: ToolRuntimeArchitecture = .universal,
        tools: [ToolManifestEntry],
        libraries: [ToolLibraryManifestEntry] = []
    ) {
        self.schema = schema
        self.platform = platform
        self.architecture = architecture
        self.tools = tools
        self.libraries = libraries
    }
}

public enum ToolCatalogError: Error, Equatable, Sendable {
    case unsupportedArchitecture
    case unsafeRoot
    case missingManifest
    case malformedManifest
    case unexpectedManifestFields
    case wrongManifestIdentity
    case duplicateTool(BundledTool)
    case incompleteManifest
    case unsafeToolPath(BundledTool)
    case missingTool(BundledTool)
    case nonExecutableTool(BundledTool)
    case hashMismatch(BundledTool)
}

public struct ToolCatalog: Sendable {
    public let rootURL: URL
    public let architecture: ToolArchitecture
    public let manifest: ToolManifest

    public init(
        rootURL: URL,
        architecture: ToolArchitecture? = .current,
        verifyHashes: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        guard let architecture else { throw ToolCatalogError.unsupportedArchitecture }
        let root = rootURL.standardizedFileURL
        guard root.isFileURL,
            try Self.isDirectoryWithoutSymlink(root, fileManager: fileManager)
        else {
            throw ToolCatalogError.unsafeRoot
        }

        let runtimeRoot = root.appendingPathComponent(
            ToolRuntimeArchitecture.universal.rawValue,
            isDirectory: true
        )
        guard try Self.isDirectoryWithoutSymlink(runtimeRoot, fileManager: fileManager) else {
            throw ToolCatalogError.unsafeRoot
        }
        let manifestURL = runtimeRoot.appendingPathComponent("manifest.json")
        guard try Self.isRegularFileWithoutSymlink(manifestURL, fileManager: fileManager) else {
            throw ToolCatalogError.missingManifest
        }

        let data = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        try Self.validateTopLevelFields(data)
        let decoded: ToolManifest
        do {
            decoded = try JSONDecoder().decode(ToolManifest.self, from: data)
        } catch {
            throw ToolCatalogError.malformedManifest
        }
        guard decoded.schema == ToolManifest.currentSchema,
            decoded.platform == "macos",
            decoded.architecture == .universal
        else {
            throw ToolCatalogError.wrongManifestIdentity
        }

        var seen = Set<BundledTool>()
        for entry in decoded.tools {
            guard seen.insert(entry.name).inserted else {
                throw ToolCatalogError.duplicateTool(entry.name)
            }
            let expectedPath = entry.name.rawValue
            guard entry.path == expectedPath else {
                throw ToolCatalogError.unsafeToolPath(entry.name)
            }
            let toolURL = runtimeRoot.appendingPathComponent(entry.path)
            guard Self.contains(toolURL, in: runtimeRoot),
                try Self.isRegularFileWithoutSymlink(toolURL, fileManager: fileManager)
            else {
                throw ToolCatalogError.missingTool(entry.name)
            }
            guard fileManager.isExecutableFile(atPath: toolURL.path) else {
                throw ToolCatalogError.nonExecutableTool(entry.name)
            }
            if verifyHashes {
                let digest = try Self.sha256(toolURL)
                guard digest == entry.sha256.lowercased() else {
                    throw ToolCatalogError.hashMismatch(entry.name)
                }
            }
        }
        guard seen == Set(BundledTool.allCases) else {
            throw ToolCatalogError.incompleteManifest
        }
        for library in decoded.libraries {
            guard library.path.hasPrefix("libs/"),
                !library.path.contains(".."),
                !library.path.hasPrefix("/"),
                library.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
            else {
                throw ToolCatalogError.malformedManifest
            }
            let libraryURL = runtimeRoot.appendingPathComponent(library.path)
            guard Self.contains(libraryURL, in: runtimeRoot),
                try Self.isRegularFileWithoutSymlink(libraryURL, fileManager: fileManager)
            else {
                throw ToolCatalogError.malformedManifest
            }
            if verifyHashes, try Self.sha256(libraryURL) != library.sha256 {
                throw ToolCatalogError.malformedManifest
            }
        }

        self.rootURL = root
        self.architecture = architecture
        manifest = decoded
    }

    public func url(for tool: BundledTool) throws -> URL {
        guard manifest.tools.contains(where: { $0.name == tool }) else {
            throw ToolCatalogError.missingTool(tool)
        }
        return
            rootURL
            .appendingPathComponent(ToolRuntimeArchitecture.universal.rawValue, isDirectory: true)
            .appendingPathComponent(tool.rawValue)
    }

    private static func validateTopLevelFields(_ data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolCatalogError.malformedManifest
        }
        let expected = Set(["schema", "platform", "architecture", "tools", "libraries"])
        guard Set(object.keys) == expected else {
            throw ToolCatalogError.unexpectedManifestFields
        }
    }

    private static func contains(_ child: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        return childPath == rootPath || childPath.hasPrefix(rootPath + "/")
    }

    private static func isDirectoryWithoutSymlink(
        _ url: URL,
        fileManager: FileManager
    ) throws -> Bool {
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
        ])
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func isRegularFileWithoutSymlink(
        _ url: URL,
        fileManager _: FileManager
    ) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
