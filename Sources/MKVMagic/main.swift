import AppKit
import Foundation

if CommandLine.arguments == [CommandLine.arguments[0], "--app-baseline-probe"] {
    do {
        let sample = try AppBaselineProbe.run()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(sample))
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(
            Data("app baseline probe failed: \(error)\n".utf8))
        exit(1)
    }
}

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

if CommandLine.arguments == [CommandLine.arguments[0], "--run-bundled-fixture-smoke"] {
    Task.detached {
        guard let resources = Bundle.main.resourceURL else {
            FileHandle.standardError.write(Data("missing app resource directory\n".utf8))
            exit(1)
        }
        do {
            let report = try await BundledFixtureSmoke().run(
                toolRoot: resources.appendingPathComponent("Tools", isDirectory: true)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(
                Data("bundled fixture smoke failed: \(error)\n".utf8))
            exit(1)
        }
    }
    dispatchMain()
}

if CommandLine.arguments == [CommandLine.arguments[0], "--run-native-release-verification"] {
    do {
        let baseline = try AppBaselineProbe.run()
        Task.detached {
            do {
                let report = try await NativeReleaseVerification.run(baseline: baseline)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                FileHandle.standardOutput.write(try encoder.encode(report))
                FileHandle.standardOutput.write(Data("\n".utf8))
                exit(0)
            } catch {
                FileHandle.standardError.write(
                    Data("native release verification failed\n".utf8))
                exit(1)
            }
        }
    } catch {
        FileHandle.standardError.write(
            Data("native release verification failed\n".utf8))
        exit(1)
    }
    dispatchMain()
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
withExtendedLifetime(delegate) {
    application.run()
}
