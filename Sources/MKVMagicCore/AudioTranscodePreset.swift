import Foundation

/// Explicit audio outputs that MKV Magic may offer after the corresponding
/// bundled FFmpeg encoder passes a local smoke encode. Packet copy remains the
/// default everywhere; these presets are opt-in generation-changing choices.
public enum AudioTranscodePreset: String, Codable, CaseIterable, Hashable, Sendable {
    case aacCompatibility
    case opusQuality
    case ac3Compatibility
    case eac3Compatibility
    case flacLossless

    public var displayName: String {
        switch self {
        case .aacCompatibility: "AAC"
        case .opusQuality: "Opus"
        case .ac3Compatibility: "AC-3"
        case .eac3Compatibility: "E-AC-3"
        case .flacLossless: "FLAC (Lossless)"
        }
    }

    public var codecName: String {
        switch self {
        case .aacCompatibility: "aac"
        case .opusQuality: "opus"
        case .ac3Compatibility: "ac3"
        case .eac3Compatibility: "eac3"
        case .flacLossless: "flac"
        }
    }

    public var isLossless: Bool { self == .flacLossless }

    /// Returns whether an inspected source track is already in this preset's
    /// output codec. Matching tracks can remain exact packet copies.
    public func matches(sourceCodec rawCodec: String) -> Bool {
        rawCodec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == codecName
    }

    /// A conservative channel-count boundary for the bundled encoders. Exact
    /// layout validation remains a planner responsibility so no downmix can be
    /// introduced merely because a count happens to fit.
    public var maximumChannelCount: Int {
        switch self {
        case .ac3Compatibility, .eac3Compatibility: 6
        case .aacCompatibility, .opusQuality, .flacLossless: 8
        }
    }

    public func preserves(channelLayout rawLayout: String, channels: Int) -> Bool {
        let layout = rawLayout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.channelCounts[layout] == channels else { return false }
        return supportedLayouts.contains(layout)
    }

    /// Returns the explicit common-format Join target for one reviewed lane.
    /// Exact layouts are preferred. The sole rematrix allowance is between the
    /// two conventional six-channel 5.1 orders; this retains all six channels
    /// while selecting the order the chosen encoder can reopen faithfully.
    public func joinOutputChannelLayout(
        forSourceLayout rawLayout: String,
        channels: Int
    ) -> String? {
        let layout = rawLayout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.channelCounts[layout] == channels else { return nil }
        if preserves(channelLayout: layout, channels: channels) { return layout }
        guard channels == 6 else { return nil }
        switch (self, layout) {
        case (.aacCompatibility, "5.1(side)"),
            (.opusQuality, "5.1(side)"),
            (.flacLossless, "5.1(side)"):
            return "5.1"
        case (.ac3Compatibility, "5.1"),
            (.eac3Compatibility, "5.1"):
            return "5.1(side)"
        default:
            return nil
        }
    }

    /// The exact declared output sample rate. A `nil` result means this preset
    /// must not be offered for the input rate. Opus uses its standardized 48 kHz
    /// Matroska clock; all other accepted choices retain the input rate.
    public func outputSampleRate(forInput input: Int) -> Int? {
        switch self {
        case .aacCompatibility:
            return Self.aacSampleRates.contains(input) ? input : nil
        case .opusQuality:
            return (8_000...192_000).contains(input) ? 48_000 : nil
        case .ac3Compatibility, .eac3Compatibility:
            return [32_000, 44_100, 48_000].contains(input) ? input : nil
        case .flacLossless:
            return (8_000...192_000).contains(input) ? input : nil
        }
    }

    public func recommendedBitrate(channels: Int) -> Int? {
        guard (1...maximumChannelCount).contains(channels) else { return nil }
        switch self {
        case .aacCompatibility:
            return switch channels {
            case 1: 96_000
            case 2: 192_000
            case 3...6: 384_000
            default: 512_000
            }
        case .opusQuality:
            return switch channels {
            case 1: 96_000
            case 2: 160_000
            case 3...6: 384_000
            default: 512_000
            }
        case .ac3Compatibility:
            return switch channels {
            case 1: 192_000
            case 2: 256_000
            default: 640_000
            }
        case .eac3Compatibility:
            return switch channels {
            case 1: 192_000
            case 2: 256_000
            default: 768_000
            }
        case .flacLossless:
            return nil
        }
    }

    private var supportedLayouts: Set<String> {
        switch self {
        case .aacCompatibility:
            ["mono", "stereo", "3.0", "quad", "4.0", "5.0", "5.1", "7.0", "octagonal"]
        case .opusQuality:
            ["mono", "stereo", "3.0", "quad", "5.0", "5.1", "6.1", "7.1"]
        case .ac3Compatibility, .eac3Compatibility:
            ["mono", "stereo", "3.0", "3.0(back)", "quad(side)", "4.0", "5.0(side)", "5.1(side)"]
        case .flacLossless:
            [
                "mono", "stereo", "3.0", "3.0(back)", "quad", "quad(side)", "4.0",
                "5.0", "5.0(side)", "5.1", "5.1(side)", "6.1", "7.0", "7.1",
                "7.1(wide)", "octagonal",
            ]
        }
    }

    private static let aacSampleRates: Set<Int> = [
        8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000,
    ]

    private static let channelCounts: [String: Int] = [
        "mono": 1,
        "stereo": 2,
        "3.0": 3,
        "3.0(back)": 3,
        "quad": 4,
        "quad(side)": 4,
        "4.0": 4,
        "5.0": 5,
        "5.0(side)": 5,
        "5.1": 6,
        "5.1(side)": 6,
        "6.1": 7,
        "7.0": 7,
        "7.1": 8,
        "7.1(wide)": 8,
        "octagonal": 8,
    ]
}
