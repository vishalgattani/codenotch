import Foundation
import os

/// This Mac's own CPU load, as a ring. Off until switched on in Settings.
///
/// The share is averaged over the time since the previous fetch, so on the
/// store's 15-second cadence it is a 15-second average. The very first fetch
/// has nothing to compare with and takes a second reading half a second later.
actor SystemCPUProvider: UsageProvider {
    nonisolated let id = SystemProviders.cpuID
    nonisolated let displayName = "CPU"
    nonisolated let glyph = ProviderGlyph.systemCPU

    private let read: () -> CPUTicks?
    private var previous: CPUTicks?

    init(read: @escaping () -> CPUTicks? = SystemUsage.readCPUTicks) {
        self.read = read
    }

    nonisolated var isVisibleWhenAbsent: Bool { false }
    nonisolated var signInRoute: SignInRoute { .guidance(L10n.t("Switch on System in Settings to show CPU and GPU load.")) }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        if previous == nil {
            previous = read()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard let now = read() else { throw SystemUsageError.cpuUnavailable }
        defer { previous = now }
        guard let old = previous, let fraction = SystemUsage.cpuFraction(from: old, to: now) else {
            throw SystemUsageError.cpuUnavailable
        }
        Log.usage.debug("system cpu -> \(fraction, privacy: .public)")
        return SystemProviders.snapshot(id: id, displayName: displayName, glyph: glyph,
                                        window: SystemUsage.window(id: "cpu", label: "CPU", fraction: fraction,
                                                                                  thresholds: RingThresholds.load(for: id)))
    }
}

/// The GPU's utilisation as Apple Silicon's IOAccelerator reports it. Off
/// until switched on in Settings; absent on Macs whose GPU does not publish it.
actor SystemGPUProvider: UsageProvider {
    nonisolated let id = SystemProviders.gpuID
    nonisolated let displayName = "GPU"
    nonisolated let glyph = ProviderGlyph.systemGPU

    private let read: () -> [[String: Any]]

    init(read: @escaping () -> [[String: Any]] = SystemUsage.readAcceleratorStatistics) {
        self.read = read
    }

    nonisolated var isVisibleWhenAbsent: Bool { false }
    nonisolated var signInRoute: SignInRoute { .guidance(L10n.t("Switch on System in Settings to show CPU and GPU load.")) }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let fraction = SystemUsage.gpuFraction(fromStatistics: read()) else {
            throw SystemUsageError.gpuUnavailable
        }
        Log.usage.debug("system gpu -> \(fraction, privacy: .public)")
        return SystemProviders.snapshot(id: id, displayName: displayName, glyph: glyph,
                                        window: SystemUsage.window(id: "gpu", label: "GPU", fraction: fraction,
                                                                                  thresholds: RingThresholds.load(for: id)))
    }
}

/// How much of the startup volume is free. Off until switched on in Settings.
/// The ring fills by the free share; see `SystemUsage.diskWindow`.
actor SystemDiskProvider: UsageProvider {
    nonisolated let id = SystemProviders.diskID
    nonisolated let displayName = L10n.t("Disk")
    nonisolated let glyph = ProviderGlyph.systemDisk

    private let read: () -> Double?

    init(read: @escaping () -> Double? = SystemUsage.readStartupVolumeFreeFraction) {
        self.read = read
    }

    nonisolated var isVisibleWhenAbsent: Bool { false }
    nonisolated var signInRoute: SignInRoute { .guidance(L10n.t("Switch on Disk free in System settings to show free disk space.")) }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let free = read() else { throw SystemUsageError.diskUnavailable }
        Log.usage.debug("system disk free -> \(free, privacy: .public)")
        return SystemProviders.snapshot(id: id, displayName: displayName, glyph: glyph,
                                        window: SystemUsage.diskWindow(freeFraction: free,
                                                                       thresholds: RingThresholds.load(for: id)))
    }
}

enum SystemProviders {
    static let cpuID = "system-cpu"
    static let gpuID = "system-gpu"
    static let diskID = "system-disk"
    /// The CPU and GPU pair, switched together.
    static let ids = [cpuID, gpuID]
    static let all = [cpuID, gpuID, diskID]

    static func snapshot(id: String, displayName: String, glyph: ProviderGlyph, window: LimitWindow) -> ProviderSnapshot {
        ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                         fidelity: .official, status: .ok,
                         windows: [window], headlineID: window.id)
    }
}
