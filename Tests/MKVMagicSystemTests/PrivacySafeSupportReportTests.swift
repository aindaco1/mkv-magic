import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicSystem

final class PrivacySafeSupportReportTests: XCTestCase {
    private var rootURL: URL!
    private var toolRootURL: URL!

    func testStandaloneTranscodeHistoryUsesItsOwnPrivacySafeWorkflowKind() {
        XCTAssertEqual(
            SupportWorkflowKind(workflowID: BuiltInWorkflowCatalog.videoTranscode),
            .videoTranscode
        )
        XCTAssertEqual(
            SupportWorkflowKind(workflowID: BuiltInWorkflowCatalog.remuxToMKV),
            .remuxToMKV
        )
        XCTAssertEqual(
            SupportWorkflowKind(
                workflowID: BuiltInWorkflowCatalog.timedTextSubtitleConversion
            ),
            .timedTextSubtitleConversion
        )
        XCTAssertEqual(
            SupportWorkflowKind(workflowID: BuiltInWorkflowCatalog.textSubtitleExtraction),
            .textSubtitleExtraction
        )
        XCTAssertEqual(
            SupportWorkflowKind(workflowID: BuiltInWorkflowCatalog.attachmentExtraction),
            .attachmentExtraction
        )
        XCTAssertEqual(
            SupportWorkflowKind(workflowID: BuiltInWorkflowCatalog.attachmentRemoval),
            .attachmentRemoval
        )
        XCTAssertEqual(
            SupportWorkflowKind(workflowID: BuiltInWorkflowCatalog.tagExport),
            .tagExport
        )
        XCTAssertEqual(
            SupportWorkflowKind(workflowID: BuiltInWorkflowCatalog.tagRemoval),
            .tagRemoval
        )
    }

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-support-report-\(UUID().uuidString)",
            isDirectory: true
        )
        toolRootURL = rootURL.appendingPathComponent("tools", isDirectory: true)
        try FileManager.default.createDirectory(
            at: toolRootURL.appendingPathComponent("universal", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writeToolTree()
    }

    override func tearDownWithError() throws {
        if rootURL != nil { try FileManager.default.removeItem(at: rootURL) }
    }

    func testReportExportsOnlyCoarseFactsAndSanitizedLifecycle() throws {
        let record = try sensitiveRecord()
        let report = PrivacySafeSupportReport.make(
            applicationVersion: "1.0/private/path",
            applicationBuild: "42\nsecret",
            operatingSystem: "macOS 13.7.8 (Build Test)",
            catalog: try ToolCatalog(
                rootURL: toolRootURL,
                architecture: .arm64,
                verifyHashes: false
            ),
            records: [record]
        )

        let data = try report.encoded()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let job = try XCTUnwrap(report.history.jobs.first)

        XCTAssertEqual(report.schema, PrivacySafeSupportReport.currentSchema)
        XCTAssertEqual(report.history.totalJobCount, 1)
        XCTAssertEqual(job.workflow, .savedOrUnknown)
        XCTAssertEqual(job.result, .failed)
        XCTAssertEqual(job.lastActiveStage, .verifying)
        XCTAssertEqual(job.elapsedTime, .from1To10Minutes)
        XCTAssertEqual(job.failureCategory, .verificationFailed)
        XCTAssertEqual(job.plan?.videoEncodeGenerations, 1)
        let firstInput = try XCTUnwrap(job.inputs.first)
        XCTAssertEqual(try XCTUnwrap(firstInput).codecs, [.aac, .av1])
        XCTAssertEqual(report.application.version, "unknown")
        XCTAssertEqual(report.application.build, "unknown")
        XCTAssertTrue(text.contains("mkv-magic-privacy-safe-support-v4"))
        XCTAssertTrue(text.contains("av1"))

        for secret in [
            "/Users/private",
            "Secret Movie.mkv",
            "Secret Output.mkv",
            "My Secret Workflow",
            "Secret failure details",
            "Secret Track Title",
            "Secret Chapter",
            "secret.example",
            record.id.uuidString,
            record.inputs[0].id.uuidString,
            "1700000000",
        ] {
            XCTAssertFalse(text.contains(secret), "Leaked private value: \(secret)")
        }
    }

    func testWriterUsesPrivatePermissionsAndRejectsUnsafeDestinations() throws {
        let report = PrivacySafeSupportReport.make(
            applicationVersion: "1.0",
            applicationBuild: "1",
            operatingSystem: "macOS test",
            catalog: try ToolCatalog(
                rootURL: toolRootURL,
                architecture: .arm64,
                verifyHashes: false
            ),
            records: []
        )
        let destination = rootURL.appendingPathComponent("support.json")

        try PrivacySafeSupportReportWriter.write(report, to: destination)

        let decoded = try JSONDecoder().decode(
            PrivacySafeSupportReport.self,
            from: Data(contentsOf: destination)
        )
        XCTAssertEqual(decoded, report)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)

        XCTAssertThrowsError(
            try PrivacySafeSupportReportWriter.write(
                report,
                to: rootURL.appendingPathComponent("support.txt")
            )
        ) {
            XCTAssertEqual(
                $0 as? PrivacySafeSupportReportWriterError,
                .unsafeDestination
            )
        }

        let target = rootURL.appendingPathComponent("target.json")
        try Data().write(to: target)
        let symlink = rootURL.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        XCTAssertThrowsError(
            try PrivacySafeSupportReportWriter.write(report, to: symlink)
        ) {
            XCTAssertEqual(
                $0 as? PrivacySafeSupportReportWriterError,
                .unsafeDestination
            )
        }
    }

    func testReportExportsAStableFailureCategoryWithoutTheFailureMessage() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        var record = MediaJobRecord(
            createdAt: created,
            workflowID: BuiltInWorkflowCatalog.remuxToMKV,
            workflowName: "Private remux name",
            inputs: [MediaJobInput(displayName: "Private Movie.mp4")]
        )
        for state in [
            MediaJobState.inspecting, .planned, .ready, .running, .verifying, .failed,
        ] {
            try record.transition(
                to: state,
                at: created,
                message: state == .failed
                    ? "Verification failed: chapter timing or titles did not match the source."
                    : nil
            )
        }
        let report = PrivacySafeSupportReport.make(
            applicationVersion: "1.0",
            applicationBuild: "1",
            operatingSystem: "macOS test",
            catalog: try ToolCatalog(
                rootURL: toolRootURL,
                architecture: .arm64,
                verifyHashes: false
            ),
            records: [record]
        )
        let text = try XCTUnwrap(String(data: report.encoded(), encoding: .utf8))

        XCTAssertEqual(report.history.jobs.first?.failureCategory, .chapterMismatch)
        XCTAssertTrue(text.contains("chapterMismatch"))
        XCTAssertFalse(text.contains("chapter timing or titles"))
        XCTAssertFalse(text.contains("Private Movie.mp4"))
    }

    func testReportIncludesPrivacySafeQueueFailureWithoutNamesPathsOrRawErrors() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let workflow = SavedWorkflow(
            id: BuiltInWorkflowCatalog.remuxToMKV,
            name: "Private queued workflow",
            steps: [
                SavedWorkflowStep(action: .remuxToMKV),
                SavedWorkflowStep(action: .addExternalSubtitle),
            ]
        )
        let source = MediaQueueFileReference(
            displayName: "Private Movie.mp4",
            securityScopedBookmark: Data([1]),
            reviewedRevision: MediaQueueFileRevision(
                fileSize: 100,
                modificationDate: created
            )
        )
        let subtitle = MediaQueueFileReference(
            displayName: "Private Movie.en.srt",
            securityScopedBookmark: Data([2]),
            reviewedRevision: MediaQueueFileRevision(
                fileSize: 20,
                modificationDate: created
            )
        )
        let destination = MediaQueueFileReference(
            displayName: "Secret Destination",
            securityScopedBookmark: Data([3])
        )
        var queueJob = MediaQueueJob(
            createdAt: created,
            workflow: .saved(workflow),
            inputs: [source, subtitle],
            destinationDirectory: destination,
            outputDisplayName: "Private Output.mkv",
            reviewedPlan: ExecutionPlan(
                stages: [PlanStage(mechanism: .mkvMerge, summary: "Secret plan")],
                impact: PlanImpact(
                    videoEncodeCount: 0,
                    audioEncodeCount: 0,
                    copiesVideo: true
                )
            )
        )
        try queueJob.transition(to: .running, at: created)
        try queueJob.transition(
            to: .failed,
            at: created,
            reason: .executionFailed,
            failure: PrivacySafeMediaFailure(
                category: .toolFailed,
                lastActiveStage: .inspecting
            )
        )
        let queue = MediaQueueSnapshot(jobs: [queueJob], updatedAt: created)
        let report = PrivacySafeSupportReport.make(
            applicationVersion: "1.0",
            applicationBuild: "1",
            operatingSystem: "macOS test",
            catalog: try ToolCatalog(
                rootURL: toolRootURL,
                architecture: .x86_64,
                verifyHashes: false
            ),
            records: [],
            queueSnapshot: queue
        )
        let queued = try XCTUnwrap(report.queue?.jobs.first)
        let text = try XCTUnwrap(String(data: report.encoded(), encoding: .utf8))

        XCTAssertEqual(queued.workflow, .remuxToMKV)
        XCTAssertEqual(queued.state, .failed)
        XCTAssertEqual(queued.lastEventReason, .executionFailed)
        XCTAssertEqual(queued.inputCount, 2)
        XCTAssertEqual(queued.attemptCount, 1)
        XCTAssertEqual(queued.failureCategory, .toolFailed)
        XCTAssertEqual(queued.failureStage, .inspecting)
        for secret in [
            "Private Movie", "Private queued workflow", "Secret Destination",
            "Private Output", "Secret plan", "securityScopedBookmark",
        ] {
            XCTAssertFalse(text.contains(secret), "Leaked private queue value: \(secret)")
        }
    }

    func testReportExportsOnlyAValidatedJoinBoundaryNumber() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        var record = MediaJobRecord(
            createdAt: created,
            workflowID: BuiltInWorkflowCatalog.losslessJoin,
            workflowName: "Private join name",
            inputs: [
                MediaJobInput(displayName: "Private Part 1.mkv"),
                MediaJobInput(displayName: "Private Part 2.mkv"),
                MediaJobInput(displayName: "Private Part 3.mkv"),
            ]
        )
        for state in [
            MediaJobState.inspecting, .planned, .ready, .running, .verifying, .failed,
        ] {
            try record.transition(
                to: state,
                at: created,
                message: state == .failed
                    ? "Verification failed: the joined output did not decode cleanly across boundary 2."
                    : nil
            )
        }
        let report = PrivacySafeSupportReport.make(
            applicationVersion: "0.2.2-test.5",
            applicationBuild: "2",
            operatingSystem: "macOS test",
            catalog: try ToolCatalog(
                rootURL: toolRootURL,
                architecture: .x86_64,
                verifyHashes: false
            ),
            records: [record]
        )
        let job = try XCTUnwrap(report.history.jobs.first)
        let text = try XCTUnwrap(String(data: report.encoded(), encoding: .utf8))

        XCTAssertEqual(job.failureCategory, .joinBoundaryDecodeFailed)
        XCTAssertEqual(job.joinBoundaryNumber, 2)
        XCTAssertTrue(text.contains("joinBoundaryDecodeFailed"))
        XCTAssertTrue(text.contains("\"joinBoundaryNumber\" : 2"))
        XCTAssertFalse(text.contains("Private Part"))
        XCTAssertFalse(text.contains("did not decode cleanly"))
    }

    func testReportRejectsAnOutOfRangeJoinBoundaryNumber() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        var record = MediaJobRecord(
            createdAt: created,
            workflowID: BuiltInWorkflowCatalog.losslessJoin,
            workflowName: "Private join name",
            inputs: [
                MediaJobInput(displayName: "Private Part 1.mkv"),
                MediaJobInput(displayName: "Private Part 2.mkv"),
            ]
        )
        for state in [
            MediaJobState.inspecting, .planned, .ready, .running, .verifying, .failed,
        ] {
            try record.transition(
                to: state,
                at: created,
                message: state == .failed
                    ? "Verification failed: the joined output did not decode cleanly across boundary 99."
                    : nil
            )
        }
        let report = PrivacySafeSupportReport.make(
            applicationVersion: "0.2.2-test.5",
            applicationBuild: "2",
            operatingSystem: "macOS test",
            catalog: try ToolCatalog(
                rootURL: toolRootURL,
                architecture: .x86_64,
                verifyHashes: false
            ),
            records: [record]
        )
        let job = try XCTUnwrap(report.history.jobs.first)

        XCTAssertEqual(job.failureCategory, .verificationFailed)
        XCTAssertNil(job.joinBoundaryNumber)
    }

    func testReportDistinguishesSanitizedCommitFailures() throws {
        let cases: [(message: String, category: SupportFailureCategory)] = [
            (
                "Execution stopped: the output location was unavailable or unsafe.",
                .destinationUnavailable
            ),
            (
                "Execution stopped: an item already existed at the output location.",
                .destinationExists
            ),
            ("Execution stopped: output commit permission was denied.", .commitPermissionDenied),
            (
                "Execution stopped: the output filesystem did not support the verified no-overwrite commit.",
                .commitUnsupported
            ),
            ("Execution stopped: the verified output could not be committed.", .commitFailed),
            ("Execution stopped: history could not be updated.", .historyWriteFailed),
            ("Output committed; history finalization failed.", .historyWriteFailed),
        ]
        let created = Date(timeIntervalSince1970: 1_800_000_000)

        for (index, item) in cases.enumerated() {
            var record = MediaJobRecord(
                createdAt: created.addingTimeInterval(Double(index)),
                workflowID: BuiltInWorkflowCatalog.subtitleCleanup,
                workflowName: "Private cleanup name",
                inputs: [MediaJobInput(displayName: "Private Subtitle.srt")]
            )
            for state in [
                MediaJobState.inspecting, .planned, .ready, .running, .verifying,
                .committing, .failed,
            ] {
                try record.transition(
                    to: state,
                    at: record.createdAt,
                    message: state == .failed ? item.message : nil
                )
            }
            let report = PrivacySafeSupportReport.make(
                applicationVersion: "1.0",
                applicationBuild: "1",
                operatingSystem: "macOS test",
                catalog: try ToolCatalog(
                    rootURL: toolRootURL,
                    architecture: .arm64,
                    verifyHashes: false
                ),
                records: [record]
            )
            let text = try XCTUnwrap(String(data: report.encoded(), encoding: .utf8))

            XCTAssertEqual(report.history.jobs.first?.failureCategory, item.category)
            XCTAssertFalse(text.contains(item.message))
            XCTAssertFalse(text.contains("Private Subtitle.srt"))
        }
    }

    func testVersionOneReportWithoutFailureCategoryStillDecodes() throws {
        let report = PrivacySafeSupportReport.make(
            applicationVersion: "0.1.5",
            applicationBuild: "1",
            operatingSystem: "macOS test",
            catalog: try ToolCatalog(
                rootURL: toolRootURL,
                architecture: .arm64,
                verifyHashes: false
            ),
            records: [try sensitiveRecord()]
        )
        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: report.encoded()) as? [String: Any]
        )
        document["schema"] = "mkv-magic-privacy-safe-support-v1"
        var history = try XCTUnwrap(document["history"] as? [String: Any])
        var jobs = try XCTUnwrap(history["jobs"] as? [[String: Any]])
        jobs[0].removeValue(forKey: "failureCategory")
        history["jobs"] = jobs
        document["history"] = history

        let decoded = try JSONDecoder().decode(
            PrivacySafeSupportReport.self,
            from: JSONSerialization.data(withJSONObject: document)
        )

        XCTAssertEqual(decoded.schema, "mkv-magic-privacy-safe-support-v1")
        XCTAssertNil(decoded.history.jobs.first?.failureCategory)
    }

    func testReportBoundsHistoryToNewestFiveHundredJobs() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let records = (0...PrivacySafeSupportReport.maximumIncludedJobs).map { index in
            MediaJobRecord(
                createdAt: base.addingTimeInterval(Double(index)),
                workflowID: BuiltInWorkflowCatalog.trackMetadata,
                workflowName: "Edit track metadata",
                inputs: [MediaJobInput(displayName: "private-\(index).mkv")]
            )
        }
        let report = PrivacySafeSupportReport.make(
            applicationVersion: "1.0",
            applicationBuild: "1",
            operatingSystem: "macOS test",
            catalog: try ToolCatalog(
                rootURL: toolRootURL,
                architecture: .arm64,
                verifyHashes: false
            ),
            records: records
        )

        XCTAssertEqual(report.history.totalJobCount, 501)
        XCTAssertEqual(report.history.includedJobCount, 500)
        XCTAssertEqual(report.history.omittedOlderJobCount, 1)
        XCTAssertEqual(report.history.jobs.count, 500)
        XCTAssertEqual(report.history.jobs.first?.caseNumber, 1)
        XCTAssertEqual(report.history.jobs.last?.caseNumber, 500)
        XCTAssertEqual(report.history.jobs.first?.lastActiveStage, .queued)
        let text = try XCTUnwrap(String(data: report.encoded(), encoding: .utf8))
        XCTAssertFalse(text.contains("private-"))
    }

    private func sensitiveRecord() throws -> MediaJobRecord {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let facts = MediaJobInputFacts(
            asset: MediaAsset(
                sourceURL: URL(fileURLWithPath: "/Users/private/Secret Movie.mkv"),
                container: "matroska",
                duration: MediaTime(nanoseconds: 7_200_000_000_000),
                fileSize: 9_000_000_000,
                tracks: [
                    MediaTrack(
                        id: 0,
                        kind: .video,
                        codec: "av1",
                        title: "Secret Track Title"
                    ),
                    MediaTrack(id: 1, kind: .audio, codec: "aac", channels: 6),
                ],
                chapters: [ChapterNode(title: "Secret Chapter", start: .zero)]
            )
        )
        var record = MediaJobRecord(
            id: UUID(uuidString: "87705017-CE25-4F50-B4AA-A3084AE8C023")!,
            createdAt: created,
            workflowID: UUID(uuidString: "D7EA6CB4-C272-4C8E-8D1E-1B0E37C7F219")!,
            workflowName: "My Secret Workflow",
            inputs: [
                MediaJobInput(
                    id: UUID(uuidString: "96E700C5-99CB-4277-87BE-65CEEAC1DB54")!,
                    displayName: "Secret Movie.mkv",
                    privacySafeFacts: facts
                )
            ],
            outputDisplayName: "Secret Output.mkv",
            privacySafePlan: MediaJobPlanFacts(
                videoEncodeGenerations: 1,
                audioTracksEncoded: 0
            )
        )
        for (offset, state) in [
            MediaJobState.inspecting, .planned, .ready, .running, .verifying, .failed,
        ].enumerated() {
            try record.transition(
                to: state,
                at: created.addingTimeInterval(Double((offset + 1) * 45)),
                message: state == .failed ? "Secret failure details /Users/private" : nil
            )
        }
        return record
    }

    private func writeToolTree() throws {
        let architectureRoot = toolRootURL.appendingPathComponent("universal", isDirectory: true)
        let tools = BundledTool.allCases.map { tool in
            ToolManifestEntry(
                name: tool,
                path: tool.rawValue,
                version: "test/\(tool.rawValue)",
                sha256: String(repeating: "a", count: 64),
                license: "Secret License",
                source: URL(string: "https://secret.example/\(tool.rawValue)")!
            )
        }
        for tool in BundledTool.allCases {
            let url = architectureRoot.appendingPathComponent(tool.rawValue)
            try Data("tool".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        }
        let manifest = ToolManifest(tools: tools)
        try JSONEncoder().encode(manifest).write(
            to: architectureRoot.appendingPathComponent("manifest.json")
        )
    }
}
