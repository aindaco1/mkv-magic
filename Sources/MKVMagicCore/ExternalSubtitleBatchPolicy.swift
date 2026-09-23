import Foundation

/// Shared bounds and structural checks for review, planning, and durable jobs.
public enum ExternalSubtitleBatchPolicy {
    public static let maximumSubtitlesPerVideo = 32

    public static func supportsMultipleSubtitles(_ workflow: SavedWorkflow) -> Bool {
        Set(workflow.steps.filter(\.isEnabled).map(\.action)) == [
            .remuxToMKV, .addExternalSubtitle,
        ]
    }
}
