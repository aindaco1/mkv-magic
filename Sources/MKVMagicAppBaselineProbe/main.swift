import Foundation
import MKVMagicCore
import MKVMagicPerformance
import MKVMagicSystem

let arguments = Array(CommandLine.arguments.dropFirst())
guard let executableIndex = arguments.firstIndex(of: "--app-executable"),
    arguments.indices.contains(executableIndex + 1)
else {
    writeError(
        "Usage: MKVMagicAppBaselineProbe --app-executable PATH [--quick] [--enforce]\n"
    )
    exit(64)
}
let executablePath = arguments[executableIndex + 1]
var remaining = arguments
remaining.removeSubrange(executableIndex...(executableIndex + 1))
let allowedArguments: Set<String> = ["--enforce", "--quick"]
guard Set(remaining).isSubset(of: allowedArguments), Set(remaining).count == remaining.count,
    executablePath.hasPrefix("/"), !executablePath.contains("/../")
else {
    writeError(
        "Usage: MKVMagicAppBaselineProbe --app-executable PATH [--quick] [--enforce]\n"
    )
    exit(64)
}

do {
    let executableURL = URL(fileURLWithPath: executablePath).standardizedFileURL
    let values = try executableURL.resourceValues(forKeys: [
        .isRegularFileKey, .isSymbolicLinkKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
        throw AppBaselineLauncherError.unsafeExecutable
    }
    let rounds = remaining.contains("--quick") ? 3 : 7
    let runner = FoundationCommandRunner()
    var samples = [AppBaselineSample]()
    var launchNanoseconds = [UInt64]()
    samples.reserveCapacity(rounds)
    launchNanoseconds.reserveCapacity(rounds)
    for _ in 0..<rounds {
        let result = try await runner.run(
            CommandRequest(
                executableURL: executableURL,
                arguments: ["--app-baseline-probe"],
                timeout: 5,
                outputLimit: 65_536
            )
        )
        guard result.exitCode == 0,
            !result.standardOutput.wasTruncated,
            !result.standardError.wasTruncated,
            result.standardError.data.isEmpty,
            result.duration > 0,
            result.duration.isFinite,
            result.duration < 5
        else {
            // Temporary hosted-fixture diagnosis; remove once the SDK message is identified.
            if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
                writeError("Hosted baseline stderr: " + result.standardError.text + "\n")
            }
            throw AppBaselineLauncherError.childFailed(
                exitCode: result.exitCode,
                stdoutBytes: result.standardOutput.data.count,
                stderrBytes: result.standardError.data.count,
                truncated: result.standardOutput.wasTruncated || result.standardError.wasTruncated,
                duration: result.duration
            )
        }
        samples.append(
            try JSONDecoder().decode(AppBaselineSample.self, from: result.standardOutput.data))
        launchNanoseconds.append(UInt64(result.duration * 1_000_000_000))
    }
    let report = try AppBaselineProbeReport(
        samples: samples,
        processLaunchNanoseconds: launchNanoseconds
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try encoder.encode(report))
    FileHandle.standardOutput.write(Data("\n".utf8))
    if remaining.contains("--enforce"), !report.isWithinBudget {
        writeError("One or more app baseline budgets were exceeded.\n")
        exit(2)
    }
} catch {
    writeError("App baseline probe failed: \(error.localizedDescription)\n")
    exit(1)
}

private enum AppBaselineLauncherError: Error {
    case unsafeExecutable
    case childFailed(
        exitCode: Int32, stdoutBytes: Int, stderrBytes: Int, truncated: Bool, duration: TimeInterval
    )
}

extension AppBaselineLauncherError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsafeExecutable: "The app executable must be an absolute, regular, non-symlink file."
        case .childFailed(
            let exitCode, let stdoutBytes, let stderrBytes, let truncated, let duration):
            "The app probe failed or emitted unsafe diagnostic output "
                + "(exit: \(exitCode), stdout bytes: \(stdoutBytes), stderr bytes: \(stderrBytes), "
                + "truncated: \(truncated), seconds: \(duration))."
        }
    }
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
