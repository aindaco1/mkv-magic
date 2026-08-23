import Foundation

public struct TrackRemoval: Codable, Equatable, Hashable, Sendable {
    public let trackUIDs: Set<UInt64>

    public init(trackUIDs: Set<UInt64>) {
        self.trackUIDs = trackUIDs
    }
}
