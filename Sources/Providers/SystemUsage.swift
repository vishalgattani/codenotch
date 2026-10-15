import Foundation
import IOKit

/// Cumulative CPU ticks across every core, as `host_statistics` reports them.
/// One reading says nothing on its own; the busy share is the difference
/// between two.
struct CPUTicks: Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    var busy: UInt64 { user &+ system &+ nice }
    var total: UInt64 { busy &+ idle }
}

enum SystemUsageError: LocalizedError, Equatable {
    case cpuUnavailable
    case gpuUnavailable

    var errorDescription: String? {
        switch self {
        case .cpuUnavailable: return L10n.t("CPU load could not be read")
        case .gpuUnavailable: return L10n.t("GPU utilisation could not be read")
        }
    }
}

enum SystemUsage {
    /// The busy share of the time between two tick readings, 0...1.
    /// Nil when no time passed or the counters went backwards (a reset).
    static func cpuFraction(from old: CPUTicks, to new: CPUTicks) -> Double? {
        guard new.total > old.total, new.busy >= old.busy, new.idle >= old.idle else { return nil }
        let busy = Double(new.busy - old.busy)
        let total = Double(new.total - old.total)
        return min(max(busy / total, 0), 1)
    }

    /// The busiest accelerator's "Device Utilization %" out of IOKit's
    /// `PerformanceStatistics` dictionaries, as 0...1. Nil when none reports it.
    static func gpuFraction(fromStatistics statistics: [[String: Any]]) -> Double? {
        let values = statistics.compactMap { stats -> Double? in
            (stats["Device Utilization %"] as? NSNumber)?.doubleValue
        }
        guard let peak = values.max() else { return nil }
        return min(max(peak / 100, 0), 1)
    }

    static func window(id: String, label: String, fraction: Double) -> LimitWindow {
        LimitWindow(id: id, label: label, usedFraction: fraction,
                    detail: "\(label) \(Int((fraction * 100).rounded()))%")
    }

    // MARK: Reading the machine

    static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    /// Every IOAccelerator's `PerformanceStatistics`. Apple Silicon publishes
    /// "Device Utilization %" there for any user, no root needed.
    static func readAcceleratorStatistics() -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var all: [[String: Any]] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let value = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                all.append(value)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return all
    }
}
