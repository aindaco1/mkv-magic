import Foundation

public enum MatroskaEditingPolicy {
    public static func supports(_ asset: MediaAsset) -> Bool {
        let extensions = Set(["mkv", "mka", "mks", "mk3d", "webm"])
        return extensions.contains(asset.sourceURL.pathExtension.lowercased())
            || asset.container.localizedCaseInsensitiveContains("matroska")
            || asset.container.localizedCaseInsensitiveContains("webm")
    }
}
