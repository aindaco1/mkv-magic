import Darwin
import Foundation
import OSLog

/// Two bounded, private JSONL files; serial writes never change media work's
/// outcome. A damaged record is counted and skipped, never uploaded verbatim.
public actor DiagnosticJournal {
    public static let maximumFileBytes = 262_144
    public static let maximumExportedEvents = 400
    private static let logger = Logger(subsystem: "com.dustwave.mkvmagic", category: "diagnostics")
    private let directory: URL
    private let maximumBytes: Int
    private var dropped = 0

    public init(directory: URL, maximumBytes: Int = maximumFileBytes) {
        self.directory = directory
        self.maximumBytes = min(Self.maximumFileBytes, max(1_024, maximumBytes))
    }

    public func record(_ event: DiagnosticEvent) {
        Self.logger.info(
            "action=\(event.action.rawValue, privacy: .public) stage=\(event.stage.rawValue, privacy: .public) outcome=\(event.outcome.rawValue, privacy: .public) failure=\(event.failure?.rawValue ?? "none", privacy: .public) attempt=\(event.attemptID.uuidString, privacy: .public)"
        )
        do {
            var line = try JSONEncoder().encode(event)
            guard DiagnosticEvent.decodeLine(line) != nil else { throw JournalError.unsafeFile }
            line.append(10)
            let directoryFD = try openDirectory()
            defer { close(directoryFD) }
            if let size = try fileSize("events.jsonl", in: directoryFD),
                size + line.count > maximumBytes
            {
                _ = try fileSize("events.previous.jsonl", in: directoryFD)
                guard
                    renameat(directoryFD, "events.jsonl", directoryFD, "events.previous.jsonl") == 0
                else { throw JournalError.unavailable }
            }
            let fd = openat(
                directoryFD, "events.jsonl",
                O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw JournalError.unsafeFile }
            defer { close(fd) }
            try validateFile(fd)
            guard fchmod(fd, 0o600) == 0 else { throw JournalError.unavailable }
            try line.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = write(
                        fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw JournalError.unavailable }
                    offset += count
                }
            }
        } catch {
            dropped = min(Int.max - 1, dropped) + 1
            Self.logger.error("diagnostic_write_failed")
        }
    }

    public func snapshot() -> DiagnosticSnapshot {
        var events: [DiagnosticEvent] = []
        var skipped = 0
        var unavailable = false
        do {
            let directoryFD = try openDirectory()
            defer { close(directoryFD) }
            for name in ["events.previous.jsonl", "events.jsonl"] {
                guard try fileSize(name, in: directoryFD) != nil else { continue }
                let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard fd >= 0 else { throw JournalError.unsafeFile }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                defer { try? handle.close() }
                try validateFile(fd)
                let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
                guard data.count <= maximumBytes else { throw JournalError.unsafeFile }
                for line in data.split(separator: 10) {
                    if let event = DiagnosticEvent.decodeLine(Data(line)) {
                        events.append(event)
                    } else {
                        skipped += 1
                    }
                }
            }
        } catch { unavailable = true }
        return DiagnosticSnapshot(
            events: Array(events.suffix(Self.maximumExportedEvents)), droppedEventCount: dropped,
            skippedInvalidRecordCount: skipped,
            omittedEventCount: max(0, events.count - Self.maximumExportedEvents),
            storageUnavailable: unavailable
        )
    }

    private func openDirectory() throws -> Int32 {
        guard directory.isFileURL, directory.path.hasPrefix("/"),
            directory.lastPathComponent == "Diagnostics"
        else { throw JournalError.unsafeFile }
        let parent = directory.deletingLastPathComponent()
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { throw JournalError.unsafeFile }
        defer { close(parentFD) }
        if mkdirat(parentFD, "Diagnostics", 0o700) != 0 && errno != EEXIST {
            throw JournalError.unavailable
        }
        let fd = openat(parentFD, "Diagnostics", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw JournalError.unsafeFile }
        guard fchmod(fd, 0o700) == 0 else {
            close(fd)
            throw JournalError.unavailable
        }
        return fd
    }

    private func fileSize(_ name: String, in directoryFD: Int32) throws -> Int? {
        var status = stat()
        if fstatat(directoryFD, name, &status, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return nil }
            throw JournalError.unavailable
        }
        try validateStatus(status)
        return Int(status.st_size)
    }

    private func validateFile(_ fd: Int32) throws {
        var status = stat()
        guard fstat(fd, &status) == 0 else { throw JournalError.unavailable }
        try validateStatus(status)
    }

    private func validateStatus(_ status: stat) throws {
        guard status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1,
            status.st_size >= 0, status.st_size <= maximumBytes
        else { throw JournalError.unsafeFile }
    }

    private enum JournalError: Error { case unsafeFile, unavailable }
}
