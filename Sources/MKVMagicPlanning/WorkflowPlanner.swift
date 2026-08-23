import Foundation
import MKVMagicCore

public enum PlanningError: Error, Equatable, Sendable {
    case emptyWorkflow
    case invalidTrimRange
    case multipleVideoEncodes
}

public struct WorkflowPlanner: Sendable {
    public init() {}

    public func plan(asset: MediaAsset, workflow: WorkflowDefinition) throws -> ExecutionPlan {
        guard !workflow.operations.isEmpty else { throw PlanningError.emptyWorkflow }

        var needsPropertyEdit = false
        var needsRemux = false
        var needsVideoEncode = false
        var needsStreamCopyTrim = false
        var warnings: [String] = []

        for operation in workflow.operations {
            switch operation {
            case .editSegmentTitle, .editTrackMetadata, .setTrackLanguage:
                needsPropertyEdit = true
            case .removeTracks, .removeTracksByUID, .muxSubtitle:
                needsRemux = true
            case .trim(let start, let end, let exact):
                guard start >= .zero, end > start else { throw PlanningError.invalidTrimRange }
                if exact {
                    needsVideoEncode = true
                    warnings.append("Exact trimming may require video encoding.")
                } else {
                    needsStreamCopyTrim = true
                }
            case .transcodeVideo:
                needsVideoEncode = true
            }
        }

        var stages: [PlanStage] = []
        if needsVideoEncode {
            stages.append(
                PlanStage(
                    mechanism: .ffmpegEncode,
                    summary: "Fuse all video-affecting operations into one final encode"
                )
            )
        } else if needsStreamCopyTrim {
            stages.append(
                PlanStage(
                    mechanism: .ffmpegStreamCopy,
                    summary: "Trim at compatible packet boundaries without encoding"
                )
            )
        }

        if needsRemux {
            stages.append(
                PlanStage(
                    mechanism: .mkvMerge,
                    summary: "Apply structural track changes while copying compatible streams"
                )
            )
        }

        if needsPropertyEdit {
            stages.append(
                PlanStage(
                    mechanism: .mkvPropEdit,
                    summary: "Apply Matroska properties to a verified temporary clone"
                )
            )
        }

        stages.append(PlanStage(mechanism: .verify, summary: "Verify the planned output contract"))
        stages.append(PlanStage(mechanism: .commit, summary: "Commit the verified result"))

        let encodeCount = stages.filter { $0.mechanism == .ffmpegEncode }.count
        guard encodeCount <= 1 else { throw PlanningError.multipleVideoEncodes }

        return ExecutionPlan(
            stages: stages,
            impact: PlanImpact(
                videoEncodeCount: encodeCount,
                audioEncodeCount: 0,
                copiesVideo: encodeCount == 0,
                warnings: warnings
            )
        )
    }
}
