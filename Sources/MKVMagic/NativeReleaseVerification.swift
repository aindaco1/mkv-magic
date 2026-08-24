import Foundation
import MKVMagicCore
import MKVMagicSystem

struct NativeReleaseVerificationReport: Codable, Equatable, Sendable {
    static let schema = "mkv-magic-native-release-verification-v1"

    let schema: String
    let appVersion: String
    let appBuild: String
    let architecture: String
    let operatingSystem: AppBaselineOperatingSystem
    let activeProcessorCount: Int
    let mainViewReadyNanoseconds: UInt64
    let residentMemoryBytes: UInt64
    let rootSubviewCount: Int
    let bundledToolCount: Int
    let fixture: BundledFixtureSmokeReport

    init(
        appVersion: String,
        appBuild: String,
        baseline: AppBaselineSample,
        bundledToolCount: Int,
        fixture: BundledFixtureSmokeReport
    ) throws {
        guard Self.isSafeIdentifier(appVersion), Self.isSafeIdentifier(appBuild),
            baseline.schema == AppBaselineSample.schema,
            baseline.architecture == "arm64" || baseline.architecture == "x86_64",
            baseline.activeProcessorCount > 0,
            baseline.mainViewReadyNanoseconds > 0,
            baseline.residentMemoryBytes > 0,
            baseline.windowCount == 0,
            baseline.rootSubviewCount > 0,
            bundledToolCount == BundledTool.allCases.count,
            fixture.schema == BundledFixtureSmokeReport.schema,
            fixture.architecture == baseline.architecture,
            fixture.sourceBytes > 0,
            fixture.outputBytes > 0,
            fixture.extractedTrackBytes > 0,
            fixture.trackCount > 0,
            fixture.originalPreserved
        else {
            throw NativeReleaseVerificationError.invalidReport
        }
        schema = Self.schema
        self.appVersion = appVersion
        self.appBuild = appBuild
        architecture = baseline.architecture
        operatingSystem = baseline.operatingSystem
        activeProcessorCount = baseline.activeProcessorCount
        mainViewReadyNanoseconds = baseline.mainViewReadyNanoseconds
        residentMemoryBytes = baseline.residentMemoryBytes
        rootSubviewCount = baseline.rootSubviewCount
        self.bundledToolCount = bundledToolCount
        self.fixture = fixture
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64
            && value.unicodeScalars.allSatisfy {
                CharacterSet(
                    charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.-"
                )
                .contains($0)
            }
    }
}

enum NativeReleaseVerificationError: Error {
    case invalidReport
    case missingBundleMetadata
}

extension NativeReleaseVerificationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidReport:
            "Native release verification returned missing or inconsistent facts."
        case .missingBundleMetadata:
            "Native release verification requires a packaged MKV Magic app."
        }
    }
}

enum NativeReleaseVerification {
    static func run(baseline: AppBaselineSample) async throws
        -> NativeReleaseVerificationReport
    {
        guard let resources = Bundle.main.resourceURL,
            let appVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            throw NativeReleaseVerificationError.missingBundleMetadata
        }
        let toolRoot = resources.appendingPathComponent("Tools", isDirectory: true)
        let toolSummaries = try await BundledToolVerifier().verify(toolRoot: toolRoot)
        let fixture = try await BundledFixtureSmoke().run(toolRoot: toolRoot)
        return try NativeReleaseVerificationReport(
            appVersion: appVersion,
            appBuild: appBuild,
            baseline: baseline,
            bundledToolCount: toolSummaries.count,
            fixture: fixture
        )
    }
}
