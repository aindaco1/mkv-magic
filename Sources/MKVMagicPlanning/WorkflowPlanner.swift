import Foundation
import MKVMagicCore

public enum PlanningError: Error, Equatable, Sendable {
    case emptyWorkflow
    case invalidTrimRange
    case multipleVideoEncodes
    case multipleAudioConversions
}

public struct WorkflowPlanner: Sendable {
    public init() {}

    public func plan(asset: MediaAsset, workflow: WorkflowDefinition) throws -> ExecutionPlan {
        guard !workflow.operations.isEmpty else { throw PlanningError.emptyWorkflow }

        var needsPropertyEdit = false
        var needsRemux = false
        var needsVideoEncode = false
        var audioTranscodePreset: AudioTranscodePreset?
        var needsStreamCopyTrim = false
        var warnings: [String] = []

        for operation in workflow.operations {
            switch operation {
            case .editSegmentTitle, .editTrackMetadata, .setTrackLanguage:
                needsPropertyEdit = true
            case .removeTracks, .removeTracksByUID, .addExternalSubtitle:
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
            case .transcodeAudio(let preset):
                guard audioTranscodePreset == nil || audioTranscodePreset == preset else {
                    throw PlanningError.multipleAudioConversions
                }
                audioTranscodePreset = preset
            }
        }

        let audioEncodeCount =
            audioTranscodePreset.map { preset in
                asset.tracks.count {
                    $0.kind == .audio && !preset.matches(sourceCodec: $0.codec)
                }
            } ?? 0
        let needsAudioEncode = audioEncodeCount > 0

        var stages: [PlanStage] = []
        if needsVideoEncode || needsAudioEncode {
            let summary: String
            switch (needsVideoEncode, needsAudioEncode) {
            case (true, true):
                summary = "Fuse reviewed video and audio conversion into one FFmpeg process"
            case (true, false):
                summary = "Fuse all video-affecting operations into one final encode"
            case (false, true):
                let noun = audioEncodeCount == 1 ? "track" : "tracks"
                summary =
                    "Convert \(audioEncodeCount) mismatched audio \(noun) once while packet-copying video"
            case (false, false):
                preconditionFailure("An encode stage requires video or audio work")
            }
            stages.append(
                PlanStage(
                    mechanism: .ffmpegEncode,
                    summary: summary
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

        let encodeStageCount = stages.filter { $0.mechanism == .ffmpegEncode }.count
        guard encodeStageCount <= 1 else { throw PlanningError.multipleVideoEncodes }

        return ExecutionPlan(
            stages: stages,
            impact: PlanImpact(
                videoEncodeCount: needsVideoEncode ? 1 : 0,
                audioEncodeCount: audioEncodeCount,
                copiesVideo: !needsVideoEncode,
                warnings: warnings
            )
        )
    }
}
