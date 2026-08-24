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
    }

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-support-report-\(UUID().uuidString)",
            isDirectory: true
        )
        toolRootURL = rootURL.appendingPathComponent("tools", isDirectory: true)
        try FileManager.default.createDirectory(
            at: toolRootURL.appendingPathComponent("arm64", isDirectory: true),
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
        XCTAssertEqual(job.plan?.videoEncodeGenerations, 1)
        let firstInput = try XCTUnwrap(job.inputs.first)
        XCTAssertEqual(try XCTUnwrap(firstInput).codecs, [.aac, .av1])
        XCTAssertEqual(report.application.version, "unknown")
        XCTAssertEqual(report.application.build, "unknown")
        XCTAssertTrue(text.contains("mkv-magic-privacy-safe-support-v1"))
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
        let architectureRoot = toolRootURL.appendingPathComponent("arm64", isDirectory: true)
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
        let manifest = ToolManifest(architecture: .arm64, tools: tools)
        try JSONEncoder().encode(manifest).write(
            to: architectureRoot.appendingPathComponent("manifest.json")
        )
    }
}
