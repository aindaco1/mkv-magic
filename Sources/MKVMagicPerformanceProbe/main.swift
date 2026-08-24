import Darwin
import Foundation
import MKVMagicPerformance

let arguments = Array(CommandLine.arguments.dropFirst())
let allowedArguments: Set<String> = ["--enforce", "--quick"]
guard Set(arguments).isSubset(of: allowedArguments), Set(arguments).count == arguments.count else {
    writeError("Usage: MKVMagicPerformanceProbe [--quick] [--enforce]\n")
    exit(64)
}

do {
    let configuration: ResponsivenessProbeConfiguration =
        arguments.contains("--quick") ? .quick : .standard
    let report = try await ResponsivenessProbe(configuration: configuration).run()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(report)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    if arguments.contains("--enforce"), !report.isWithinBudget {
        writeError("One or more responsiveness budgets were exceeded.\n")
        exit(2)
    }
} catch {
    writeError("Responsiveness probe failed: \(error.localizedDescription)\n")
    exit(1)
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
