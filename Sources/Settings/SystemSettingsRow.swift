import SwiftUI

/// One switch for the CPU and GPU rings together, and one for the disk-free ring.
struct SystemSettingsRow: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: UsageStore

    private var enabled: Bool { SystemProviders.ids.allSatisfy(preferences.isConnected) }
    private var diskEnabled: Bool { preferences.isConnected(SystemProviders.diskID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProviderGlyphView(glyph: .systemCPU, size: 16)
                Text(L10n.t("CPU and GPU rings"))
                Spacer()
                Toggle(L10n.t("Show CPU and GPU load"), isOn: Binding(
                    get: { enabled },
                    set: { on in
                        for id in SystemProviders.ids { preferences.setConnected(on, for: id) }
                        store.disconnected = preferences.disconnectedIDs(among: store.knownIDs)
                        if on { for id in SystemProviders.ids { store.refresh(providerID: id) } }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .font(.body)

            if enabled {
                ForEach(SystemProviders.ids, id: \.self) { id in
                    let snapshot = store.snapshots.first { $0.id == id }
                    Text(snapshot?.windows.first?.detail ?? snapshot?.statusMessage ?? L10n.t("Reading…"))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L10n.t("Monitoring off.")).foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 10) {
                ProviderGlyphView(glyph: .systemDisk, size: 16)
                Text(L10n.t("Disk used ring"))
                Spacer()
                Toggle(L10n.t("Show disk space used"), isOn: Binding(
                    get: { diskEnabled },
                    set: { on in
                        preferences.setConnected(on, for: SystemProviders.diskID)
                        store.disconnected = preferences.disconnectedIDs(among: store.knownIDs)
                        if on { store.refresh(providerID: SystemProviders.diskID) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .font(.body)

            if diskEnabled {
                let snapshot = store.snapshots.first { $0.id == SystemProviders.diskID }
                Text(snapshot?.windows.first?.detail ?? snapshot?.statusMessage ?? L10n.t("Reading…"))
                    .foregroundStyle(.secondary)
            }

            Text(L10n.t("CPU is the share of time all cores were busy since the last reading; GPU is the busiest accelerator's utilisation as macOS reports it. Read locally on the usual refresh cadence, without sudo."))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The colour bands of each System ring: where it turns yellow and where red.
/// All of them worsen as they rise.
struct SystemRingColorsRow: View {
    @ObservedObject var store: UsageStore
    let providerID: String
    let title: String
    @State private var thresholds: RingThresholds

    init(store: UsageStore, providerID: String, title: String) {
        self.store = store
        self.providerID = providerID
        self.title = title
        _thresholds = State(initialValue: RingThresholds.load(for: providerID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Button(L10n.t("Reset")) {
                    RingThresholds.reset(for: providerID)
                    thresholds = RingThresholds.load(for: providerID)
                    store.refresh(providerID: providerID)
                }
                .controlSize(.small)
            }
            limit(L10n.t("Yellow from"),
                  color: Palette.watch, value: \.watch)
            limit(L10n.t("Red from"),
                  color: Palette.critical, value: \.critical)
        }
    }

    private func limit(_ label: String, color: Color, value: WritableKeyPath<RingThresholds, Double>) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).frame(width: 90, alignment: .leading)
            Slider(value: Binding(
                get: { thresholds[keyPath: value] },
                set: { thresholds[keyPath: value] = $0 }
            ), in: 0.01...0.99, step: 0.01) { editing in
                guard !editing else { return }
                thresholds = thresholds.clamped()
                RingThresholds.save(thresholds, for: providerID)
                store.refresh(providerID: providerID)
            }
            Text("\(Int((thresholds[keyPath: value] * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        .font(.caption)
    }
}
