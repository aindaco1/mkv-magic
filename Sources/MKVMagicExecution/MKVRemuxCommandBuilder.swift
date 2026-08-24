import Foundation
import MKVMagicPlanning

public enum MKVRemuxCommandError: Error, Equatable, Sendable {
    case unsafePath
    case unsupportedDestination
    case destinationExists
    case inconsistentPlan
}

extension MKVRemuxCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsafePath: "Remux to MKV requires safe absolute source and output paths."
        case .unsupportedDestination: "Remux to MKV creates one .mkv output."
        case .destinationExists: "The temporary MKV output already exists."
        case .inconsistentPlan: "The remux command no longer matches the reviewed track order."
        }
    }
}

public struct MKVRemuxCommandBuilder: Sendable {
    public init() {}

    public func build(
        plan: ResolvedMKVRemuxPlan,
        outputURL: URL
    ) throws -> [String] {
        let sourceURL = plan.source.sourceURL.standardizedFileURL
        let outputURL = outputURL.standardizedFileURL
        guard safeAbsoluteFilePath(sourceURL), safeAbsoluteFilePath(outputURL),
            sourceURL != outputURL
        else {
            throw MKVRemuxCommandError.unsafePath
        }
        guard outputURL.pathExtension.lowercased() == "mkv" else {
            throw MKVRemuxCommandError.unsupportedDestination
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw MKVRemuxCommandError.destinationExists
        }
        let mediaTrackIDs = plan.source.tracks.filter {
            $0.kind == .video || $0.kind == .audio || $0.kind == .subtitle
        }.map(\.id)
        let chapterCarrierTrackIDs = plan.source.tracks.filter {
            $0.kind == .data
                && $0.codec.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "bin_data"
                && !plan.source.chapters.isEmpty
        }.map(\.id)
        guard !plan.trackIDsInOutputOrder.isEmpty,
            plan.trackIDsInOutputOrder == mediaTrackIDs,
            plan.chapterCarrierTrackIDs == chapterCarrierTrackIDs,
            Set(mediaTrackIDs).count == mediaTrackIDs.count,
            mediaTrackIDs.allSatisfy({ $0 >= 0 })
        else {
            throw MKVRemuxCommandError.inconsistentPlan
        }
        let trackOrder = plan.trackIDsInOutputOrder
            .map { "0:\($0)" }
            .joined(separator: ",")
        return [
            "--output", outputURL.path,
            "--abort-on-warnings",
            "--flush-on-close",
            "--normalize-language-ietf", "canonical",
            "--disable-track-statistics-tags",
            "--no-buttons",
            "--track-order", trackOrder,
            sourceURL.path,
        ]
    }

    private func safeAbsoluteFilePath(_ url: URL) -> Bool {
        let path = url.path
        return url.isFileURL && path.hasPrefix("/") && !path.contains("\0")
            && (1...4_096).contains(path.utf8.count)
    }
}
