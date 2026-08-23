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

guard CommandLine.arguments.count == 2 else { throw ResealError.invalidArguments }
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
guard root.path.hasPrefix("/"), rootValues.isDirectory == true, rootValues.isSymbolicLink != true
else {
    throw ResealError.unsafeRoot
}

let expectedTools = Set(["ffmpeg", "ffprobe", "mkvmerge", "mkvpropedit", "mkvextract"])
for architecture in ["arm64", "x86_64"] {
    let architectureRoot = root.appendingPathComponent(architecture, isDirectory: true)
    let manifestURL = architectureRoot.appendingPathComponent("manifest.json")
    let buildManifestURL = architectureRoot.appendingPathComponent("build-manifest.json")
    guard !FileManager.default.fileExists(atPath: buildManifestURL.path) else {
        throw ResealError.invalidManifest("build manifest already exists for \(architecture)")
    }
    let sourceData = try Data(contentsOf: manifestURL)
    guard var manifest = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any],
        Set(manifest.keys) == Set(["schema", "platform", "architecture", "tools", "libraries"]),
        manifest["schema"] as? String == "mkv-magic-tool-manifest-v1",
        manifest["platform"] as? String == "macos",
        manifest["architecture"] as? String == architecture,
        var tools = manifest["tools"] as? [[String: Any]],
        var libraries = manifest["libraries"] as? [[String: Any]],
        tools.count == expectedTools.count
    else {
        throw ResealError.invalidManifest(architecture)
    }
    let names = Set(tools.compactMap { $0["name"] as? String })
    guard names == expectedTools else { throw ResealError.invalidManifest(architecture) }

    try FileManager.default.copyItem(at: manifestURL, to: buildManifestURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: buildManifestURL.path
    )
    for index in tools.indices {
        guard let name = tools[index]["name"] as? String,
            tools[index]["path"] as? String == name
        else {
            throw ResealError.invalidManifest(architecture)
        }
        let toolURL = architectureRoot.appendingPathComponent(name)
        let values = try toolURL.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ResealError.missingTool("\(architecture)/\(name)")
        }
        tools[index]["sha256"] = try sha256(toolURL)
    }
    manifest["tools"] = tools
    for index in libraries.indices {
        guard let path = libraries[index]["path"] as? String,
            path.hasPrefix("libs/"),
            !path.contains("..")
        else {
            throw ResealError.invalidManifest(architecture)
        }
        let libraryURL = architectureRoot.appendingPathComponent(path)
        let values = try libraryURL.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ResealError.missingTool("\(architecture)/\(path)")
        }
        libraries[index]["sha256"] = try sha256(libraryURL)
    }
    manifest["libraries"] = libraries
    let replacement = try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    ) + Data("\n".utf8)
    try replacement.write(to: manifestURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: manifestURL.path
    )
}
