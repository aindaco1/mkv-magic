import Foundation

public enum MatroskaTagPolicyError: Error, Equatable, Sendable {
    case unsupportedSource
    case unavailableCounts
    case noTags
}

extension MatroskaTagPolicyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Tag tools require an inspected Matroska file."
        case .unavailableCounts:
            "The Matroska tag counts are unavailable or invalid."
        case .noTags:
            "This Matroska file has no global or track tags to export or remove."
        }
    }
}

public struct MatroskaTagCounts: Equatable, Sendable {
    public let global: Int
    public let track: Int

    public init(global: Int, track: Int) {
        self.global = global
        self.track = track
    }

    public var total: Int { global + track }
}

public enum MatroskaTagPolicy {
    public static func counts(in asset: MediaAsset) throws -> MatroskaTagCounts {
        guard MatroskaEditingPolicy.supports(asset) else {
            throw MatroskaTagPolicyError.unsupportedSource
        }
        guard let global = asset.globalTagCount,
            let track = asset.trackTagCount,
            global >= 0,
            track >= 0
        else {
            throw MatroskaTagPolicyError.unavailableCounts
        }
        // MKVToolNix 101 may flatten generated track-statistics Tag elements
        // into ffprobe's per-track metadata while reporting no top-level
        // `track_tags` entries. Recognize that narrow signature for offering and
        // compiling tag removal, while exact mkvextract XML remains authoritative.
        let flattenedStatisticsCount = asset.tracks.count { track in
            track.tags.keys.contains { key in
                key.lowercased().hasPrefix("_statistics_")
            }
        }
        let counts = MatroskaTagCounts(
            global: global,
            track: max(track, flattenedStatisticsCount)
        )
        guard counts.total > 0 else { throw MatroskaTagPolicyError.noTags }
        return counts
    }

    public static func canOffer(for asset: MediaAsset) -> Bool {
        (try? counts(in: asset)) != nil
    }
}

public enum MatroskaTagXMLDocumentError: Error, Equatable, Sendable {
    case oversizedInput
    case malformedXML
    case unsafeXML
    case unexpectedRoot
    case unsupportedRootElement(String)
    case countMismatch
}

extension MatroskaTagXMLDocumentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .oversizedInput: "The Matroska tag document is larger than 16 MiB."
        case .malformedXML: "The Matroska tag document is malformed."
        case .unsafeXML: "The Matroska tag document contains a forbidden declaration or entity."
        case .unexpectedRoot: "The Matroska tag document must use a Tags root element."
        case .unsupportedRootElement(let name):
            "The Matroska tag document contains an unsupported root element: \(name)."
        case .countMismatch:
            "The extracted tag document does not match the inspected global and track tag counts."
        }
    }
}

/// A bounded, validated copy of MKVToolNix's complete tag XML.
///
/// The bytes remain untouched so an export is exact. Parsing is intentionally
/// narrow: it establishes a safe `Tags` document and classifies each direct
/// `Tag` entry by whether its `Targets` contains a `TrackUID`.
public struct MatroskaTagXMLDocument: Equatable, Sendable {
    public static let maximumInputBytes = 16_777_216

    public let data: Data
    public let counts: MatroskaTagCounts

    public init(
        data: Data,
        expectedCounts: MatroskaTagCounts? = nil
    ) throws {
        guard data.count <= Self.maximumInputBytes else {
            throw MatroskaTagXMLDocumentError.oversizedInput
        }
        guard !data.isEmpty,
            !data.contains(0),
            var text = String(data: data, encoding: .utf8)
        else {
            throw MatroskaTagXMLDocumentError.malformedXML
        }
        for declaration in [
            "<!DOCTYPE Tags SYSTEM \"matroskatags.dtd\">",
            "<!DOCTYPE Tags SYSTEM 'matroskatags.dtd'>",
        ] {
            text = text.replacingOccurrences(of: declaration, with: "")
        }
        let lowercase = text.lowercased()
        guard !lowercase.contains("<!doctype"), !lowercase.contains("<!entity") else {
            throw MatroskaTagXMLDocumentError.unsafeXML
        }

        let xml: XMLDocument
        do {
            xml = try XMLDocument(
                data: Data(text.utf8),
                options: [.nodeLoadExternalEntitiesNever]
            )
        } catch {
            throw MatroskaTagXMLDocumentError.malformedXML
        }
        guard let root = xml.rootElement(), root.name == "Tags" else {
            throw MatroskaTagXMLDocumentError.unexpectedRoot
        }

        var globalCount = 0
        var trackCount = 0
        for child in root.children ?? [] {
            guard let element = child as? XMLElement else { continue }
            guard element.name == "Tag" else {
                throw MatroskaTagXMLDocumentError.unsupportedRootElement(
                    element.name ?? "unknown"
                )
            }
            let targets = Self.elementChildren(of: element).filter { $0.name == "Targets" }
            let targetsTrack = targets.contains { target in
                Self.elementChildren(of: target).contains { $0.name == "TrackUID" }
            }
            if targetsTrack {
                trackCount += 1
            } else {
                globalCount += 1
            }
        }
        let counts = MatroskaTagCounts(global: globalCount, track: trackCount)
        guard expectedCounts == nil || counts == expectedCounts else {
            throw MatroskaTagXMLDocumentError.countMismatch
        }
        self.data = data
        self.counts = counts
    }

    private static func elementChildren(of element: XMLElement) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }
    }
}
