import Darwin
import Foundation

public struct DiagnosticCrashFacts: Codable, Equatable, Sendable {
    public enum Exception: String, Codable, Sendable {
        case badAccess = "EXC_BAD_ACCESS"
        case badInstruction = "EXC_BAD_INSTRUCTION"
        case arithmetic = "EXC_ARITHMETIC"
        case software = "EXC_SOFTWARE"
        case breakpoint = "EXC_BREAKPOINT"
        case crash = "EXC_CRASH"
        case resource = "EXC_RESOURCE"
        case guardViolation = "EXC_GUARD"
    }
    public enum Signal: String, Codable, Sendable {
        case abort = "SIGABRT"
        case segmentation = "SIGSEGV"
        case bus = "SIGBUS"
        case illegal = "SIGILL"
        case trap = "SIGTRAP"
        case kill = "SIGKILL"
        case floatingPoint = "SIGFPE"
        case terminate = "SIGTERM"
    }
    public enum Image: String, Codable, Sendable {
        case app = "MKVMagic"
        case appKit = "AppKit"
        case swift = "libswiftCore.dylib"
        case kernel = "libsystem_kernel.dylib"
    }
    public let exception: Exception
    public let signal: Signal?
    public let image: Image?
    public let imageOffset: Int?

    /// Explicit file selection is required: a sandboxed app must not scan the
    /// user's global DiagnosticReports directory or request broad disk access.
    public static func readSelectedIncident(_ url: URL) throws -> DiagnosticIssueReport {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL, url.pathExtension.lowercased() == "ips" else {
            throw DiagnosticReportError.invalidReport
        }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw DiagnosticReportError.invalidReport }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var status = stat()
        let limit = 2 * 1_024 * 1_024
        guard fstat(fd, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
            status.st_size > 0, status.st_size <= limit,
            let data = try handle.read(upToCount: limit + 1),
            let report = parse(data)
        else { throw DiagnosticReportError.invalidReport }
        return report
    }

    public static func parse(_ data: Data) -> DiagnosticIssueReport? {
        guard data.count <= 2 * 1_024 * 1_024, let newline = data.firstIndex(of: 10),
            let header = try? JSONSerialization.jsonObject(with: data[..<newline])
                as? [String: Any],
            header["bundleID"] as? String == "com.dustwave.mkvmagic",
            let id = (header["incident_id"] as? String).flatMap(UUID.init(uuidString:)),
            let body = try? JSONSerialization.jsonObject(with: data[data.index(after: newline)...])
                as? [String: Any],
            ["MKVMagic", "MKV Magic"].contains(body["procName"] as? String ?? ""),
            let exception = body["exception"] as? [String: Any],
            let type = (exception["type"] as? String).flatMap(Exception.init(rawValue:)),
            let architecture: ToolArchitecture = body["cpuType"] as? String == "ARM-64"
                ? .arm64
                : body["cpuType"] as? String == "X86-64" ? .x86_64 : nil
        else { return nil }
        let signal = (exception["signal"] as? String).flatMap(Signal.init(rawValue:))
        var image: Image?
        var offset: Int?
        if let threads = body["threads"] as? [[String: Any]],
            let faulting = body["faultingThread"] as? Int, threads.indices.contains(faulting),
            let frames = threads[faulting]["frames"] as? [[String: Any]],
            let images = body["usedImages"] as? [[String: Any]]
        {
            for frame in frames.prefix(12) {
                guard let index = frame["imageIndex"] as? Int, images.indices.contains(index),
                    let name = (images[index]["name"] as? String).flatMap(Image.init(rawValue:)),
                    let candidate = frame["imageOffset"] as? Int,
                    (0...1_000_000_000).contains(candidate)
                else { continue }
                image = name
                offset = candidate
                break
            }
        }
        let train = (body["osVersion"] as? [String: Any])?["train"] as? String ?? ""
        return DiagnosticIssueReport(
            id: id, kind: .nativeCrash, version: header["app_version"] as? String ?? "unknown",
            build: header["build_version"] as? String ?? "unknown",
            operatingSystem: train.hasPrefix("macOS ") ? String(train.dropFirst(6)) : "unknown",
            architecture: architecture, action: .application, stage: .execution, failure: .unknown,
            crash: Self(exception: type, signal: signal, image: image, imageOffset: offset)
        )
    }
}
