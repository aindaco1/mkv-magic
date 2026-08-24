import Foundation
import IOKit.ps
import MKVMagicCore

public protocol MediaQueueSchedulingEnvironmentReading: Sendable {
    func read() -> MediaQueueSchedulingEnvironment
}

public struct SystemMediaQueueSchedulingEnvironmentReader:
    MediaQueueSchedulingEnvironmentReading, Sendable
{
    private let isOnBattery: @Sendable () -> Bool
    private let thermalPressure: @Sendable () -> MediaQueueThermalPressure

    public init() {
        isOnBattery = { Self.readIsOnBattery() }
        thermalPressure = {
            Self.thermalPressure(for: ProcessInfo.processInfo.thermalState)
        }
    }

    init(
        isOnBattery: @escaping @Sendable () -> Bool,
        thermalPressure: @escaping @Sendable () -> MediaQueueThermalPressure
    ) {
        self.isOnBattery = isOnBattery
        self.thermalPressure = thermalPressure
    }

    public func read() -> MediaQueueSchedulingEnvironment {
        MediaQueueSchedulingEnvironment(
            isOnBattery: isOnBattery(),
            thermalPressure: thermalPressure()
        )
    }

    static func thermalPressure(
        for state: ProcessInfo.ThermalState
    ) -> MediaQueueThermalPressure {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
    }

    private static func readIsOnBattery() -> Bool {
        guard let powerSourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(powerSourcesInfo)?.takeRetainedValue()
                as? [CFTypeRef]
        else {
            return true
        }
        var foundInternalBattery = false
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(
                    powerSourcesInfo,
                    source
                )?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else {
                continue
            }
            foundInternalBattery = true
            switch description[kIOPSPowerSourceStateKey] as? String {
            case kIOPSBatteryPowerValue: return true
            case kIOPSACPowerValue: return false
            default: continue
            }
        }
        return foundInternalBattery
    }
}
