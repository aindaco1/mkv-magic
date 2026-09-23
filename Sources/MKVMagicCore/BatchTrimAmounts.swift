import Foundation

public struct BatchTrimAmounts: Equatable, Sendable {
    public let beginning: MediaTime
    public let end: MediaTime

    public init(beginning: MediaTime, end: MediaTime) {
        self.beginning = beginning
        self.end = end
    }

    public static func parseAmount(_ raw: String) throws -> MediaTime {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains(":") { return try ChapterTimestamp.parse(value) }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
            parts[0].allSatisfy({ $0.isASCII && $0.isNumber }),
            let seconds = Int64(parts[0])
        else { throw TrimPlanningError.invalidRange }
        let fraction = parts.count == 2 ? ".\(parts[1])" : ""
        return try ChapterTimestamp.parse(
            "\(seconds / 3600):\((seconds / 60) % 60):\(seconds % 60)\(fraction)")
    }

    public func retainedRange(duration: MediaTime?) throws -> MediaTrimRange {
        guard let duration, duration > .zero else { throw TrimPlanningError.invalidDuration }
        guard beginning >= .zero, end >= .zero, end < duration else {
            throw TrimPlanningError.invalidRange
        }
        guard beginning > .zero || end > .zero else { throw TrimPlanningError.noChange }
        // Subtraction is bounded above before arithmetic; never sum user input.
        let retainedEnd = MediaTime(nanoseconds: duration.nanoseconds - end.nanoseconds)
        guard beginning < retainedEnd else { throw TrimPlanningError.invalidRange }
        return MediaTrimRange(start: beginning, end: retainedEnd)
    }
}
