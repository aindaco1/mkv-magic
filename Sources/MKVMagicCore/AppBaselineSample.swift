import Foundation

public struct AppBaselineOperatingSystem: Codable, Equatable, Sendable {
    public let majorVersion: Int
    public let minorVersion: Int
    public let patchVersion: Int

    public init(_ version: OperatingSystemVersion) {
        majorVersion = version.majorVersion
        minorVersion = version.minorVersion
        patchVersion = version.patchVersion
    }
}

public struct AppBaselineSample: Codable, Equatable, Sendable {
    public static let schema = "mkv-magic-app-baseline-sample-v1"

    public let schema: String
    public let architecture: String
    public let operatingSystem: AppBaselineOperatingSystem
    public let activeProcessorCount: Int
    public let mainViewReadyNanoseconds: UInt64
    public let residentMemoryBytes: UInt64
    public let windowCount: Int
    public let rootSubviewCount: Int

    public init(
        architecture: String,
        operatingSystem: AppBaselineOperatingSystem,
        activeProcessorCount: Int,
        mainViewReadyNanoseconds: UInt64,
        residentMemoryBytes: UInt64,
        windowCount: Int,
        rootSubviewCount: Int
    ) {
        schema = Self.schema
        self.architecture = architecture
        self.operatingSystem = operatingSystem
        self.activeProcessorCount = activeProcessorCount
        self.mainViewReadyNanoseconds = mainViewReadyNanoseconds
        self.residentMemoryBytes = residentMemoryBytes
        self.windowCount = windowCount
        self.rootSubviewCount = rootSubviewCount
    }
}
