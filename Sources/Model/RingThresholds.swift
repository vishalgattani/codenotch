import Foundation

/// The user's own colour bands for one of the System rings, kept in
/// UserDefaults under the ring's provider id.
///
/// `higherIsWorse` decides which way the two limits read. CPU and GPU load
/// turn yellow at `watch` and red at `critical` and above; free disk space
/// turns yellow below `watch` and red below `critical`. The providers turn
/// this into the window's `bandOverride`, so the colour holds whichever way
/// the ring is drawn.
struct RingThresholds: Codable, Equatable {
    var watch: Double
    var critical: Double
    var higherIsWorse: Bool

    func band(for fraction: Double) -> UsageBand {
        if higherIsWorse {
            if fraction >= critical { return .critical }
            return fraction >= watch ? .watch : .ample
        }
        if fraction < critical { return .critical }
        return fraction < watch ? .watch : .ample
    }

    /// Keeps the two limits in 1...99% and ordered the way `higherIsWorse` reads them.
    func clamped() -> RingThresholds {
        var copy = self
        copy.watch = min(max(watch, 0.01), 0.99)
        copy.critical = min(max(critical, 0.01), 0.99)
        if higherIsWorse { copy.critical = max(copy.critical, min(copy.watch + 0.01, 0.99)) }
        else { copy.critical = min(copy.critical, max(copy.watch - 0.01, 0.01)) }
        return copy
    }

    static func defaults(for providerID: String) -> RingThresholds {
        providerID == SystemProviders.diskID
            ? RingThresholds(watch: 0.50, critical: 0.20, higherIsWorse: false)
            : RingThresholds(watch: 0.50, critical: 0.80, higherIsWorse: true)
    }

    static func key(for providerID: String) -> String { "ringThresholds.\(providerID)" }

    static func load(for providerID: String, from defaults: UserDefaults = .standard) -> RingThresholds {
        guard let data = defaults.data(forKey: key(for: providerID)),
              let stored = try? JSONDecoder().decode(RingThresholds.self, from: data) else {
            return Self.defaults(for: providerID)
        }
        return stored.clamped()
    }

    static func save(_ thresholds: RingThresholds, for providerID: String, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(thresholds.clamped()) {
            defaults.set(data, forKey: key(for: providerID))
        }
    }

    static func reset(for providerID: String, in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(for: providerID))
    }
}
