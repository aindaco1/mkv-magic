import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicSystem

final class MediaQueueSchedulingEnvironmentReaderTests: XCTestCase {
    func testInjectedSystemFactsProduceOneSchedulingSnapshot() {
        let reader = SystemMediaQueueSchedulingEnvironmentReader(
            isOnBattery: { true },
            thermalPressure: { .critical }
        )

        XCTAssertEqual(
            reader.read(),
            MediaQueueSchedulingEnvironment(
                isOnBattery: true,
                thermalPressure: .critical
            )
        )
    }

    func testEveryKnownProcessThermalStateMapsExactly() {
        XCTAssertEqual(
            SystemMediaQueueSchedulingEnvironmentReader.thermalPressure(for: .nominal),
            .nominal
        )
        XCTAssertEqual(
            SystemMediaQueueSchedulingEnvironmentReader.thermalPressure(for: .fair),
            .fair
        )
        XCTAssertEqual(
            SystemMediaQueueSchedulingEnvironmentReader.thermalPressure(for: .serious),
            .serious
        )
        XCTAssertEqual(
            SystemMediaQueueSchedulingEnvironmentReader.thermalPressure(for: .critical),
            .critical
        )
    }
}
