import AppKit
import Foundation

if CommandLine.arguments == [CommandLine.arguments[0], "--verify-bundled-tools"] {
    Task.detached {
        guard let resources = Bundle.main.resourceURL else {
            FileHandle.standardError.write(Data("missing app resource directory\n".utf8))
            exit(1)
        }
        do {
            let summaries = try await BundledToolVerifier().verify(
                toolRoot: resources.appendingPathComponent("Tools", isDirectory: true))
            FileHandle.standardOutput.write(
                Data((summaries.joined(separator: "\n") + "\n").utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(
                Data("bundled tool verification failed: \(error)\n".utf8))
            exit(1)
        }
    }
    dispatchMain()
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
withExtendedLifetime(delegate) {
    application.run()
}
