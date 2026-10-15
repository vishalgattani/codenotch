import XCTest
@testable import Codenotch

final class SystemUsageTests: XCTestCase {
    func testCPUFractionIsBusyOverTotalTicks() throws {
        let old = CPUTicks(user: 100, system: 50, idle: 800, nice: 0)
        let new = CPUTicks(user: 160, system: 80, idle: 900, nice: 10)
        // busy +100, idle +100
        XCTAssertEqual(try XCTUnwrap(SystemUsage.cpuFraction(from: old, to: new)), 0.5, accuracy: 1e-9)
    }

    func testAnIdleIntervalIsZero() {
        let old = CPUTicks(user: 10, system: 10, idle: 10, nice: 0)
        let new = CPUTicks(user: 10, system: 10, idle: 110, nice: 0)
        XCTAssertEqual(SystemUsage.cpuFraction(from: old, to: new), 0)
    }

    func testNoElapsedTicksOrAResetGivesNothing() {
        let ticks = CPUTicks(user: 10, system: 10, idle: 10, nice: 0)
        XCTAssertNil(SystemUsage.cpuFraction(from: ticks, to: ticks))
        XCTAssertNil(SystemUsage.cpuFraction(from: ticks, to: CPUTicks(user: 1, system: 1, idle: 100, nice: 0)))
    }

    func testGPUTakesTheBusiestAcceleratorAndClamps() {
        let stats: [[String: Any]] = [["Device Utilization %": 12], ["Device Utilization %": NSNumber(value: 47)], ["Other": 3]]
        XCTAssertEqual(SystemUsage.gpuFraction(fromStatistics: stats), 0.47)
        XCTAssertEqual(SystemUsage.gpuFraction(fromStatistics: [["Device Utilization %": 140]]), 1)
        XCTAssertNil(SystemUsage.gpuFraction(fromStatistics: [["Other": 1]]))
        XCTAssertNil(SystemUsage.gpuFraction(fromStatistics: []))
    }

    func testWindowRoundsThePercentage() {
        let window = SystemUsage.window(id: "cpu", label: "CPU", fraction: 0.426)
        XCTAssertEqual(window.usedFraction, 0.426)
        XCTAssertEqual(window.detail, "CPU 43%")
    }

    func testCPUProviderComparesSuccessiveReadings() async throws {
        var readings = [CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
                        CPUTicks(user: 30, system: 0, idle: 70, nice: 0),
                        CPUTicks(user: 30, system: 0, idle: 170, nice: 0)]
        let provider = SystemCPUProvider(read: { readings.isEmpty ? nil : readings.removeFirst() })
        let first = try await provider.fetchSnapshot()
        XCTAssertEqual(first.windows.first?.usedFraction ?? -1, 0.3, accuracy: 1e-9)
        let second = try await provider.fetchSnapshot()
        XCTAssertEqual(second.windows.first?.usedFraction, 0)
    }

    func testTheLiveMachineAnswers() {
        XCTAssertNotNil(SystemUsage.readCPUTicks())
    }
}
