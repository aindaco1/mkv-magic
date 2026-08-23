import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

@MainActor
final class AppModel {
    enum State: Equatable {
        case ready
        case inspecting(String)
        case failed(String)
    }

    private(set) var assets: [MediaAsset] = []
    private(set) var state: State = .ready
    var didChange: (() -> Void)?

    func addFiles(_ urls: [URL]) async {
        let uniqueURLs = Array(Set(urls.map(\.standardizedFileURL))).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        guard !uniqueURLs.isEmpty else { return }

        let inspector: FFprobeInspector<FoundationCommandRunner>
        do {
            let catalog = try makeToolCatalog()
            inspector = FFprobeInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                runner: FoundationCommandRunner()
            )
        } catch {
            state = .failed(
                "This development build has no verified tool bundle. Package the app or set "
                    + "MKV_MAGIC_TOOL_ROOT to an explicit manifest-backed tool directory."
            )
            didChange?()
            return
        }

        for url in uniqueURLs {
            state = .inspecting(url.lastPathComponent)
            didChange?()
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let asset = try await inspector.inspect(url)
                if let existing = assets.firstIndex(where: { $0.sourceURL == asset.sourceURL }) {
                    assets[existing] = asset
                } else {
                    assets.append(asset)
                }
            } catch {
                state = .failed(
                    "Could not inspect \(url.lastPathComponent): \(error.localizedDescription)")
                didChange?()
                continue
            }
        }
        state = .ready
        didChange?()
    }

    private func makeToolCatalog() throws -> ToolCatalog {
        if let explicitRoot = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"],
            explicitRoot.hasPrefix("/")
        {
            return try ToolCatalog(rootURL: URL(fileURLWithPath: explicitRoot, isDirectory: true))
        }
        guard let resourceURL = Bundle.main.resourceURL else {
            throw ToolCatalogError.unsafeRoot
        }
        return try ToolCatalog(
            rootURL: resourceURL.appendingPathComponent("Tools", isDirectory: true))
    }
}
