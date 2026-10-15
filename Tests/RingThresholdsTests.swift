import XCTest
@testable import Codenotch

final class RingThresholdsTests: XCTestCase {
    func testFreeFractionIsAvailableOverTotal() throws {
        XCTAssertEqual(try XCTUnwrap(SystemUsage.freeFraction(available: 900, total: 1000)), 0.9, accuracy: 1e-9)
        XCTAssertEqual(SystemUsage.freeFraction(available: 2000, total: 1000), 1)
        XCTAssertEqual(SystemUsage.freeFraction(available: -5, total: 1000), 0)
        XCTAssertNil(SystemUsage.freeFraction(available: 10, total: 0))
        XCTAssertNil(SystemUsage.freeFraction(available: nil, total: 100))
    }

    func testDiskWindowShowsTheUsedShareAndBandsOnIt() throws {
        let thresholds = RingThresholds.defaults(for: SystemProviders.diskID)
        let roomy = SystemUsage.diskWindow(freeFraction: 0.9, thresholds: thresholds)
        XCTAssertEqual(try XCTUnwrap(roomy.usedFraction), 0.1, accuracy: 1e-9)
        XCTAssertEqual(roomy.detail, "Disk 10% used")
        XCTAssertEqual(roomy.bandOverride, .ample)
        XCTAssertEqual(SystemUsage.diskWindow(freeFraction: 0.35, thresholds: thresholds).bandOverride, .watch)
        XCTAssertEqual(SystemUsage.diskWindow(freeFraction: 0.10, thresholds: thresholds).bandOverride, .critical)
    }

    func testFreeSpaceDirectionStillWorks() {
        let t = RingThresholds(watch: 0.50, critical: 0.20, higherIsWorse: false)
        XCTAssertEqual(t.band(for: 0.50), .ample)
        XCTAssertEqual(t.band(for: 0.499), .watch)
        XCTAssertEqual(t.band(for: 0.199), .critical)
    }

    func testLoadDefaultsRiseWithLoad() {
        let t = RingThresholds.defaults(for: SystemProviders.cpuID)
        XCTAssertEqual(t.band(for: 0.49), .ample)
        XCTAssertEqual(t.band(for: 0.50), .watch)
        XCTAssertEqual(t.band(for: 0.80), .critical)
        XCTAssertEqual(SystemUsage.window(id: "cpu", label: "CPU", fraction: 0.9, thresholds: t).bandOverride, .critical)
    }

    func testClampingKeepsTheLimitsOrdered() {
        let load = RingThresholds(watch: 0.7, critical: 0.4, higherIsWorse: true).clamped()
        XCTAssertGreaterThan(load.critical, load.watch)
        let disk = RingThresholds(watch: 0.1, critical: 0.3, higherIsWorse: false).clamped()
        XCTAssertLessThan(disk.critical, disk.watch)
    }

    func testPersistsPerRing() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RingThresholdsTests"))
        defaults.removePersistentDomain(forName: "RingThresholdsTests")
        XCTAssertEqual(RingThresholds.load(for: SystemProviders.diskID, from: defaults),
                       RingThresholds.defaults(for: SystemProviders.diskID))
        let custom = RingThresholds(watch: 0.6, critical: 0.9, higherIsWorse: true)
        RingThresholds.save(custom, for: SystemProviders.diskID, to: defaults)
        XCTAssertEqual(RingThresholds.load(for: SystemProviders.diskID, from: defaults), custom)
        RingThresholds.save(RingThresholds(watch: 0.5, critical: 0.2, higherIsWorse: false), for: SystemProviders.diskID, to: defaults)
        XCTAssertEqual(RingThresholds.load(for: SystemProviders.diskID, from: defaults),
                       RingThresholds.defaults(for: SystemProviders.diskID))
        XCTAssertEqual(RingThresholds.load(for: SystemProviders.gpuID, from: defaults),
                       RingThresholds.defaults(for: SystemProviders.gpuID))
        RingThresholds.reset(for: SystemProviders.diskID, in: defaults)
        XCTAssertEqual(RingThresholds.load(for: SystemProviders.diskID, from: defaults),
                       RingThresholds.defaults(for: SystemProviders.diskID))
    }

    func testDiskProviderReportsTheFreeShare() async throws {
        let snapshot = try await SystemDiskProvider(read: { 0.15 }).fetchSnapshot()
        XCTAssertEqual(snapshot.windows.first?.usedFraction ?? -1, 0.85, accuracy: 1e-9)
    }
}
