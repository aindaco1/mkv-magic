import MKVMagicCore

public struct ReviewedEditPlanner: Sendable {
    public init() {}

    public func plan(_ edit: MediaQueueReviewedEdit) -> ExecutionPlan {
        let mechanism: ExecutionMechanism
        let summary: String
        switch edit {
        case .tagRemoval(_, let count):
            mechanism = .mkvPropEdit
            summary = "Clear all \(count) reviewed tags on a temporary clone."
        case .chapters(_, let desired):
            mechanism = .mkvPropEdit
            summary = "Apply the exact reviewed document with \(desired.chapterCount) chapters."
        case .subtitleCleanup:
            mechanism = .subtitleText
            summary = "Write the exact reviewed UTF-8 subtitle text."
        case .trackMetadata(_, let edits):
            mechanism = .mkvPropEdit
            summary = "Apply the reviewed metadata to \(edits.count) tracks on one temporary clone."
        case .subtitleExtraction:
            mechanism = .mkvExtract
            summary = "Extract the reviewed text subtitle without converting its format."
        case .fastTrim(_, let adjusted, _):
            mechanism = .mkvMerge
            summary =
                "Copy the reviewed keyframe range \(ChapterTimestamp.format(adjusted.start, digits: 3))–\(ChapterTimestamp.format(adjusted.end, digits: 3)) without encoding."
        }
        return ExecutionPlan(
            stages: [
                PlanStage(mechanism: mechanism, summary: summary),
                PlanStage(
                    mechanism: .verify, summary: "Verify the reviewed output and preserved content."
                ),
                PlanStage(
                    mechanism: .commit,
                    summary: "Commit a new output and reopen it for verification."),
            ],
            impact: PlanImpact(
                videoEncodeCount: 0, audioEncodeCount: 0,
                copiesVideo: mechanism != .subtitleText && mechanism != .mkvExtract))
    }
}
