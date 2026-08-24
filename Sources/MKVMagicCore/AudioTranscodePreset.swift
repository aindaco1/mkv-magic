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

    /// A conservative channel-count boundary for the bundled encoders. Exact
    /// layout validation remains a planner responsibility so no downmix can be
    /// introduced merely because a count happens to fit.
    public var maximumChannelCount: Int {
        switch self {
        case .ac3Compatibility, .eac3Compatibility: 6
        case .aacCompatibility, .opusQuality, .flacLossless: 8
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
}
