import SwiftUI

/// One switch for both System rings, CPU and GPU.
struct SystemSettingsRow: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: UsageStore

    private var enabled: Bool { SystemProviders.ids.allSatisfy(preferences.isConnected) }

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

            Text(L10n.t("CPU is the share of time all cores were busy since the last reading; GPU is the busiest accelerator's utilisation as macOS reports it. Read locally on the usual refresh cadence, without sudo."))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}
