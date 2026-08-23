import Foundation

public struct CommandRequest: Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let currentDirectoryURL: URL?
    public let timeout: TimeInterval
    public let outputLimit: Int

    public init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = CommandRequest.defaultEnvironment,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval = 120,
        outputLimit: Int = 1_048_576
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
        self.timeout = timeout
        self.outputLimit = outputLimit
    }

    public static var defaultEnvironment: [String: String] {
        var result = [
            "LC_ALL": "C",
            "LANG": "C",
            "PATH": "/usr/bin:/bin",
        ]
        if let temporaryDirectory = ProcessInfo.processInfo.environment["TMPDIR"] {
            result["TMPDIR"] = temporaryDirectory
        }
        return result
    }
}

public struct CommandOutput: Sendable, Equatable {
    public let data: Data
    public let wasTruncated: Bool

    public init(data: Data, wasTruncated: Bool) {
        self.data = data
        self.wasTruncated = wasTruncated
    }

    public var text: String {
        String(decoding: data, as: UTF8.self)
    }
}

public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: CommandOutput
    public let standardError: CommandOutput

    public init(
        exitCode: Int32,
        standardOutput: CommandOutput,
        standardError: CommandOutput
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum CommandRunnerError: Error, Equatable, Sendable {
    case unsafeExecutable
    case invalidTimeout
    case invalidOutputLimit
    case launchFailed(String)
    case timedOut
    case cancelled
}

public protocol CommandRunning: Sendable {
    func run(_ request: CommandRequest) async throws -> CommandResult
}

public struct FoundationCommandRunner: CommandRunning {
    public init() {}

    public func run(_ request: CommandRequest) async throws -> CommandResult {
        guard request.executableURL.isFileURL,
            request.executableURL.path.hasPrefix("/"),
            !request.executableURL.path.contains("/../"),
            FileManager.default.isExecutableFile(atPath: request.executableURL.path)
        else {
            throw CommandRunnerError.unsafeExecutable
        }
        guard request.timeout > 0, request.timeout.isFinite else {
            throw CommandRunnerError.invalidTimeout
        }
        guard request.outputLimit >= 1_024, request.outputLimit <= 16_777_216 else {
            throw CommandRunnerError.invalidOutputLimit
        }

        return try await withThrowingTaskGroup(of: CommandResult.self) { group in
            group.addTask {
                try await execute(request)
            }
            group.addTask {
                let nanoseconds = UInt64(request.timeout * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw CommandRunnerError.timedOut
            }
            guard let first = try await group.next() else {
                throw CommandRunnerError.launchFailed("Command produced no result")
            }
            group.cancelAll()
            return first
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}

private func execute(_ request: CommandRequest) async throws -> CommandResult {
    try Task.checkCancellation()
    let box = ProcessBox()
    let standardOutput = Pipe()
    let standardError = Pipe()
    box.process.executableURL = request.executableURL
    box.process.arguments = request.arguments
    box.process.environment = request.environment
    box.process.currentDirectoryURL = request.currentDirectoryURL
    box.process.standardOutput = standardOutput
    box.process.standardError = standardError

    do {
        try box.process.run()
    } catch {
        throw CommandRunnerError.launchFailed(String(describing: error))
    }

    let outputTask = Task.detached {
        try readBounded(standardOutput.fileHandleForReading, limit: request.outputLimit)
    }
    let errorTask = Task.detached {
        try readBounded(standardError.fileHandleForReading, limit: request.outputLimit)
    }

    let exitCode = await withTaskCancellationHandler {
        await Task.detached {
            box.process.waitUntilExit()
            return box.process.terminationStatus
        }.value
    } onCancel: {
        box.terminate()
    }

    if Task.isCancelled {
        box.terminate()
        throw CommandRunnerError.cancelled
    }
    return try await CommandResult(
        exitCode: exitCode,
        standardOutput: outputTask.value,
        standardError: errorTask.value
    )
}

private func readBounded(_ handle: FileHandle, limit: Int) throws -> CommandOutput {
    var retained = Data()
    var wasTruncated = false
    while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
        retained.append(chunk)
        if retained.count > limit {
            wasTruncated = true
            retained.removeFirst(retained.count - limit)
        }
    }
    return CommandOutput(data: retained, wasTruncated: wasTruncated)
}
