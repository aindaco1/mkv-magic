#!/usr/bin/env swift
import CryptoKit
import Foundation

enum ResealError: Error {
    case invalidArguments
    case unsafeRoot
    case invalidManifest(String)
    case missingTool(String)
}

func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
        hasher.update(data: bytes)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func isSHA256(_ value: Any?) -> Bool {
    guard let value = value as? String else { return false }
    return value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
}

func inventoryData(_ manifest: [String: Any]) throws -> Data {
    guard var tools = manifest["tools"] as? [[String: Any]],
        var libraries = manifest["libraries"] as? [[String: Any]]
    else {
        throw ResealError.invalidManifest("inventory")
    }
    for index in tools.indices { tools[index].removeValue(forKey: "sha256") }
    for index in libraries.indices { libraries[index].removeValue(forKey: "sha256") }
    var inventory = manifest
    inventory["tools"] = tools
    inventory["libraries"] = libraries
    return try JSONSerialization.data(
        withJSONObject: inventory,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
}

func reseal() throws {
    guard CommandLine.arguments.count == 2 else { throw ResealError.invalidArguments }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        .standardizedFileURL
    let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard root.path.hasPrefix("/"), rootValues.isDirectory == true,
        rootValues.isSymbolicLink != true
    else {
        throw ResealError.unsafeRoot
    }

    let expectedTools = Set(["ffmpeg", "ffprobe", "mkvmerge", "mkvpropedit", "mkvextract"])
    let runtimeArchitecture = "universal"
    let runtimeRoot = root.appendingPathComponent(runtimeArchitecture, isDirectory: true)
    let manifestURL = runtimeRoot.appendingPathComponent("manifest.json")
    let buildManifestURL = runtimeRoot.appendingPathComponent("build-manifest.json")
    let sourceData = try Data(contentsOf: manifestURL)
    guard var manifest = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any],
        Set(manifest.keys)
            == Set(["schema", "platform", "architecture", "tools", "libraries"]),
        manifest["schema"] as? String == "mkv-magic-tool-manifest-v2",
        manifest["platform"] as? String == "macos",
        manifest["architecture"] as? String == runtimeArchitecture,
        var tools = manifest["tools"] as? [[String: Any]],
        var libraries = manifest["libraries"] as? [[String: Any]],
        tools.count == expectedTools.count
    else {
        throw ResealError.invalidManifest(runtimeArchitecture)
    }
    let names = Set(tools.compactMap { $0["name"] as? String })
    guard names == expectedTools else {
        throw ResealError.invalidManifest(runtimeArchitecture)
    }

    if let buildValues = try? buildManifestURL.resourceValues(forKeys: [
        .isRegularFileKey, .isSymbolicLinkKey,
    ]) {
        guard buildValues.isRegularFile == true, buildValues.isSymbolicLink != true else {
            throw ResealError.invalidManifest("unsafe Universal build manifest")
        }
        let buildData = try Data(contentsOf: buildManifestURL)
        guard
            let buildManifest = try JSONSerialization.jsonObject(with: buildData)
                as? [String: Any],
            Set(buildManifest.keys)
                == Set(["schema", "platform", "architecture", "tools", "libraries"]),
            buildManifest["schema"] as? String == "mkv-magic-tool-manifest-v2",
            buildManifest["platform"] as? String == "macos",
            buildManifest["architecture"] as? String == runtimeArchitecture,
            let buildTools = buildManifest["tools"] as? [[String: Any]],
            let buildLibraries = buildManifest["libraries"] as? [[String: Any]],
            buildTools.count == expectedTools.count,
            buildLibraries.count == libraries.count,
            Set(buildTools.compactMap { $0["name"] as? String }) == expectedTools,
            buildTools.allSatisfy({ isSHA256($0["sha256"]) }),
            buildLibraries.allSatisfy({ isSHA256($0["sha256"]) }),
            try inventoryData(buildManifest) == inventoryData(manifest)
        else {
            throw ResealError.invalidManifest("existing Universal build manifest")
        }
    } else {
        try FileManager.default.copyItem(at: manifestURL, to: buildManifestURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: buildManifestURL.path
        )
    }
    for index in tools.indices {
        guard let name = tools[index]["name"] as? String,
            tools[index]["path"] as? String == name
        else {
            throw ResealError.invalidManifest(runtimeArchitecture)
        }
        let toolURL = runtimeRoot.appendingPathComponent(name)
        let values = try toolURL.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ResealError.missingTool("universal/\(name)")
        }
        tools[index]["sha256"] = try sha256(toolURL)
    }
    manifest["tools"] = tools
    for index in libraries.indices {
        guard let path = libraries[index]["path"] as? String,
            path.hasPrefix("libs/"),
            !path.contains("..")
        else {
            throw ResealError.invalidManifest(runtimeArchitecture)
        }
        let libraryURL = runtimeRoot.appendingPathComponent(path)
        let values = try libraryURL.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ResealError.missingTool("universal/\(path)")
        }
        libraries[index]["sha256"] = try sha256(libraryURL)
    }
    manifest["libraries"] = libraries
    let replacement =
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) + Data("\n".utf8)
    try replacement.write(to: manifestURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: manifestURL.path
    )
}

do {
    try reseal()
} catch {
    FileHandle.standardError.write(Data("tool manifest resealing failed: \(error)\n".utf8))
    exit(1)
}
