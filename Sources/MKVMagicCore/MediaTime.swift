import Foundation

/// Nanosecond-resolution media time with deterministic integer arithmetic.
public struct MediaTime: Codable, Comparable, Hashable, Sendable {
    public static let zero = MediaTime(nanoseconds: 0)

    public let nanoseconds: Int64

    public init(nanoseconds: Int64) {
        self.nanoseconds = nanoseconds
    }

    public init?(seconds: Double) {
        guard seconds.isFinite else { return nil }
        let scaled = seconds * 1_000_000_000
        guard scaled >= Double(Int64.min), scaled <= Double(Int64.max) else { return nil }
        nanoseconds = Int64(scaled.rounded())
    }

    public var seconds: Double {
        Double(nanoseconds) / 1_000_000_000
    }

    public static func < (lhs: MediaTime, rhs: MediaTime) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }

    public static func + (lhs: MediaTime, rhs: MediaTime) -> MediaTime {
        MediaTime(nanoseconds: lhs.nanoseconds + rhs.nanoseconds)
    }

    public static func - (lhs: MediaTime, rhs: MediaTime) -> MediaTime {
        MediaTime(nanoseconds: lhs.nanoseconds - rhs.nanoseconds)
    }
}
