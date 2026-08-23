import CryptoKit
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
            // Keep deterministic tool output without breaking Unicode file paths in Qt tools.
            "LC_ALL": "C.UTF-8",
            "LANG": "C.UTF-8",
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

public struct CommandLineDigestPolicy: Equatable, Sendable {
    public let requiredPrefix: String
    public let hexDigestByteCount: Int
    public let allowedSuffixSeparator: UInt8?

    public init(
        requiredPrefix: String,
        hexDigestByteCount: Int,
        allowedSuffixSeparator: UInt8? = nil
    ) {
        self.requiredPrefix = requiredPrefix
        self.hexDigestByteCount = hexDigestByteCount
        self.allowedSuffixSeparator = allowedSuffixSeparator
    }
}

public struct CommandTrailingHexDigestPolicy: Equatable, Sendable {
    public let commentPrefix: UInt8
    public let fieldSeparator: UInt8
    public let hexDigestByteCount: Int

    public init(
        commentPrefix: UInt8,
        fieldSeparator: UInt8,
        hexDigestByteCount: Int
    ) {
        self.commentPrefix = commentPrefix
        self.fieldSeparator = fieldSeparator
        self.hexDigestByteCount = hexDigestByteCount
    }
}

public struct CommandLineDigest: Equatable, Sendable {
    public let sha256: Data
    public let lineCount: Int

    public init(sha256: Data, lineCount: Int) {
        self.sha256 = sha256
        self.lineCount = lineCount
    }
}

public enum CommandLineDigestError: Error, Equatable, Sendable {
    case invalidPolicy
    case noCommands
    case malformedOutput
    case emptyOutput
    case commandFailed(index: Int, exitCode: Int32, message: String)
    case truncatedStandardError(index: Int)
}

extension CommandLineDigestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPolicy:
            "The streaming line-digest policy is invalid."
        case .noCommands:
            "The streaming line digest needs at least one command."
        case .malformedOutput:
            "A command emitted a malformed line while its output was being digested."
        case .emptyOutput:
            "The commands emitted no digestible lines."
        case .commandFailed(let index, let exitCode, let message):
            "Digest command \(index + 1) failed (code \(exitCode)): \(message)"
        case .truncatedStandardError(let index):
            "Digest command \(index + 1) emitted more diagnostic output than the safety limit."
        }
    }
}

public protocol CommandLineDigesting: Sendable {
    func digestLines(
        _ requests: [CommandRequest],
        policy: CommandLineDigestPolicy
    ) async throws -> CommandLineDigest

    func digestTrailingHexLines(
        _ requests: [CommandRequest],
        policy: CommandTrailingHexDigestPolicy
    ) async throws -> CommandLineDigest
}

public struct FoundationCommandRunner: CommandRunning, CommandLineDigesting {
    public init() {}

    public func run(_ request: CommandRequest) async throws -> CommandResult {
        try validate(request)

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

    public func digestLines(
        _ requests: [CommandRequest],
        policy: CommandLineDigestPolicy
    ) async throws -> CommandLineDigest {
        let prefix = Data(policy.requiredPrefix.utf8)
        guard !prefix.isEmpty, prefix.count <= 128,
            policy.hexDigestByteCount >= 1, policy.hexDigestByteCount <= 256
        else {
            throw CommandLineDigestError.invalidPolicy
        }
        return try await digest(
            requests,
            policy: .prefixedHex(
                prefix: prefix,
                hexDigestByteCount: policy.hexDigestByteCount,
                allowedSuffixSeparator: policy.allowedSuffixSeparator
            )
        )
    }

    public func digestTrailingHexLines(
        _ requests: [CommandRequest],
        policy: CommandTrailingHexDigestPolicy
    ) async throws -> CommandLineDigest {
        guard policy.hexDigestByteCount >= 1, policy.hexDigestByteCount <= 256,
            policy.commentPrefix != 10, policy.commentPrefix != 13,
            policy.fieldSeparator != 10, policy.fieldSeparator != 13,
            policy.commentPrefix != policy.fieldSeparator
        else {
            throw CommandLineDigestError.invalidPolicy
        }
        return try await digest(
            requests,
            policy: .trailingHex(
                commentPrefix: policy.commentPrefix,
                fieldSeparator: policy.fieldSeparator,
                hexDigestByteCount: policy.hexDigestByteCount
            )
        )
    }

    private func digest(
        _ requests: [CommandRequest],
        policy: CanonicalDigestLinePolicy
    ) async throws -> CommandLineDigest {
        guard !requests.isEmpty else { throw CommandLineDigestError.noCommands }
        for request in requests { try validate(request) }

        let accumulator = CanonicalLineDigestAccumulator()
        for (index, request) in requests.enumerated() {
            let processResult = try await withThrowingTaskGroup(
                of: DigestProcessResult.self
            ) { group in
                group.addTask {
                    try await executeDigest(
                        request,
                        accumulator: accumulator,
                        policy: policy
                    )
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
            guard !processResult.standardError.wasTruncated else {
                throw CommandLineDigestError.truncatedStandardError(index: index)
            }
            guard processResult.exitCode == 0 else {
                let message = processResult.standardError.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw CommandLineDigestError.commandFailed(
                    index: index,
                    exitCode: processResult.exitCode,
                    message: String((message.isEmpty ? "Unknown tool error" : message).prefix(240))
                )
            }
        }
        let digest = accumulator.finalize()
        guard digest.lineCount > 0 else { throw CommandLineDigestError.emptyOutput }
        return digest
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [self] in
            guard process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

private final class ProcessTerminationWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32, Never>?
    private var exitCode: Int32?

    func finish(with exitCode: Int32) {
        let continuation: CheckedContinuation<Int32, Never>?
        lock.lock()
        if let waiting = self.continuation {
            continuation = waiting
            self.continuation = nil
        } else {
            self.exitCode = exitCode
            continuation = nil
        }
        lock.unlock()
        continuation?.resume(returning: exitCode)
    }

    func value() async -> Int32 {
        await withCheckedContinuation { continuation in
            let completedCode: Int32?
            lock.lock()
            if let exitCode {
                completedCode = exitCode
            } else {
                self.continuation = continuation
                completedCode = nil
            }
            lock.unlock()
            if let completedCode {
                continuation.resume(returning: completedCode)
            }
        }
    }
}

private struct LaunchedProcess: @unchecked Sendable {
    let box: ProcessBox
    let standardOutput: Pipe
    let standardError: Pipe
    let terminationWaiter: ProcessTerminationWaiter
}

private struct DigestProcessResult: Sendable {
    let exitCode: Int32
    let standardError: CommandOutput
}

private enum CanonicalDigestLinePolicy: Sendable {
    case prefixedHex(
        prefix: Data,
        hexDigestByteCount: Int,
        allowedSuffixSeparator: UInt8?
    )
    case trailingHex(
        commentPrefix: UInt8,
        fieldSeparator: UInt8,
        hexDigestByteCount: Int
    )
}

private final class CanonicalLineDigestAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var hasher = SHA256()
    private var lineCount = 0

    func update(_ canonicalLine: Data) {
        lock.lock()
        hasher.update(data: canonicalLine)
        lineCount += 1
        lock.unlock()
    }

    func finalize() -> CommandLineDigest {
        lock.lock()
        let digest = Data(hasher.finalize())
        let count = lineCount
        lock.unlock()
        return CommandLineDigest(sha256: digest, lineCount: count)
    }
}

private func validate(_ request: CommandRequest) throws {
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
}

private func launch(_ request: CommandRequest) throws -> LaunchedProcess {
    let box = ProcessBox()
    let standardOutput = Pipe()
    let standardError = Pipe()
    box.process.executableURL = request.executableURL
    box.process.arguments = request.arguments
    box.process.environment = request.environment
    box.process.currentDirectoryURL = request.currentDirectoryURL
    box.process.standardOutput = standardOutput
    box.process.standardError = standardError
    let terminationWaiter = ProcessTerminationWaiter()
    box.process.terminationHandler = { process in
        terminationWaiter.finish(with: process.terminationStatus)
    }

    do {
        try box.process.run()
    } catch {
        throw CommandRunnerError.launchFailed(String(describing: error))
    }
    return LaunchedProcess(
        box: box,
        standardOutput: standardOutput,
        standardError: standardError,
        terminationWaiter: terminationWaiter
    )
}

private func execute(_ request: CommandRequest) async throws -> CommandResult {
    try Task.checkCancellation()
    let launched = try launch(request)

    let outputTask = Task.detached {
        try readBounded(
            launched.standardOutput.fileHandleForReading,
            limit: request.outputLimit
        )
    }
    let errorTask = Task.detached {
        try readBounded(
            launched.standardError.fileHandleForReading,
            limit: request.outputLimit
        )
    }

    let exitCode = await withTaskCancellationHandler {
        await launched.terminationWaiter.value()
    } onCancel: {
        launched.box.terminate()
    }

    if Task.isCancelled {
        launched.box.terminate()
        throw CommandRunnerError.cancelled
    }
    return try await CommandResult(
        exitCode: exitCode,
        standardOutput: outputTask.value,
        standardError: errorTask.value
    )
}

private func executeDigest(
    _ request: CommandRequest,
    accumulator: CanonicalLineDigestAccumulator,
    policy: CanonicalDigestLinePolicy
) async throws -> DigestProcessResult {
    try Task.checkCancellation()
    let launched = try launch(request)
    let outputTask = Task.detached {
        try readCanonicalDigestLines(
            launched.standardOutput.fileHandleForReading,
            accumulator: accumulator,
            policy: policy
        )
    }
    let errorTask = Task.detached {
        try readBounded(
            launched.standardError.fileHandleForReading,
            limit: request.outputLimit
        )
    }
    let exitCode = await withTaskCancellationHandler {
        await launched.terminationWaiter.value()
    } onCancel: {
        launched.box.terminate()
    }
    if Task.isCancelled {
        launched.box.terminate()
        throw CommandRunnerError.cancelled
    }
    try await outputTask.value
    return try await DigestProcessResult(
        exitCode: exitCode,
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

private func readCanonicalDigestLines(
    _ handle: FileHandle,
    accumulator: CanonicalLineDigestAccumulator,
    policy: CanonicalDigestLinePolicy
) throws {
    var pending = Data()
    var firstError: CommandLineDigestError?

    func consume(_ rawLine: Data) {
        guard firstError == nil else { return }
        var line = rawLine
        if line.last == 13 { line.removeLast() }
        let canonical: Data
        switch policy {
        case .prefixedHex(let prefix, let hexDigestByteCount, let suffix):
            let retainedByteCount = prefix.count + hexDigestByteCount
            guard line.count >= retainedByteCount,
                line.starts(with: prefix),
                line[prefix.count..<retainedByteCount].allSatisfy(isASCIIHex),
                line.count == retainedByteCount || suffix == line[retainedByteCount]
            else {
                firstError = .malformedOutput
                return
            }
            canonical = Data(line.prefix(retainedByteCount))
        case .trailingHex(let commentPrefix, let separator, let hexDigestByteCount):
            if line.first == commentPrefix { return }
            guard let fieldStart = line.lastIndex(of: separator) else {
                firstError = .malformedOutput
                return
            }
            let rawField = line[line.index(after: fieldStart)...]
            let field = rawField.drop(while: { $0 == 32 || $0 == 9 })
            guard field.count == hexDigestByteCount, field.allSatisfy(isASCIIHex) else {
                firstError = .malformedOutput
                return
            }
            canonical = Data(field)
        }
        var terminated = canonical
        terminated.append(10)
        accumulator.update(terminated)
    }

    while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
        pending.append(chunk)
        while let newline = pending.firstIndex(of: 10) {
            consume(Data(pending[..<newline]))
            pending.removeSubrange(...newline)
        }
        if pending.count > 4_096 {
            firstError = .malformedOutput
            pending.removeAll(keepingCapacity: false)
        }
    }
    if !pending.isEmpty { consume(pending) }
    if let firstError { throw firstError }
}

private func isASCIIHex(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
}
