import AppKit
import Darwin
import Foundation
import MKVMagicCore

@MainActor
enum AppBaselineProbe {
    static func run() throws -> AppBaselineSample {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let model = AppModel()
        let controller = MainViewController(model: model)
        controller.loadView()
        controller.view.layoutSubtreeIfNeeded()
        let finishedAt = DispatchTime.now().uptimeNanoseconds
        let elapsed = finishedAt.subtractingReportingOverflow(startedAt)
        guard !elapsed.overflow else { throw AppBaselineRuntimeError.clockOverflow }
        let residentMemoryBytes = try withExtendedLifetime(controller) {
            try currentResidentMemoryBytes()
        }
        return AppBaselineSample(
            architecture: architecture,
            operatingSystem: AppBaselineOperatingSystem(
                ProcessInfo.processInfo.operatingSystemVersion
            ),
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            mainViewReadyNanoseconds: elapsed.partialValue,
            residentMemoryBytes: residentMemoryBytes,
            windowCount: application.windows.count,
            rootSubviewCount: controller.view.subviews.count
        )
    }

    private static func currentResidentMemoryBytes() throws -> UInt64 {
        var information = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard status == KERN_SUCCESS, information.resident_size > 0 else {
            throw AppBaselineRuntimeError.memoryUnavailable
        }
        return UInt64(information.resident_size)
    }

    private static var architecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unsupported"
        #endif
    }
}

private enum AppBaselineRuntimeError: Error {
    case clockOverflow
    case memoryUnavailable
}
