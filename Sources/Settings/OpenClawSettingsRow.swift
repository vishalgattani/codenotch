import SwiftUI

struct OpenClawSettingsRow: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: UsageStore
    @AppStorage(OpenClawUsage.sessionKeyDefault) private var sessionKey = ""

    private let providerID = "openclaw"
    private var enabled: Bool { preferences.isConnected(providerID) }
    private var snapshot: ProviderSnapshot? { store.snapshots.first { $0.id == providerID } }
    private var checking: Bool { store.refreshing.contains(providerID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProviderGlyphView(glyph: .openclaw, size: 16)
                Text("OpenClaw")
                Spacer()
                Toggle("Monitor OpenClaw", isOn: Binding(
                    get: { enabled },
                    set: { on in
                        preferences.setConnected(on, for: providerID)
                        store.disconnected = preferences.disconnectedIDs(among: store.knownIDs)
                        if on { store.refresh(providerID: providerID) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .font(.body)

            HStack {
                TextField(L10n.t("Session key (optional)"), text: $sessionKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if enabled { store.refresh(providerID: providerID) } }
                    .accessibilityLabel("OpenClaw session key")
                Button(L10n.t("Apply")) { store.refresh(providerID: providerID) }
                    .disabled(!enabled)
                    .controlSize(.small)
            }

            if !enabled {
                Text(L10n.t("Monitoring off.")).foregroundStyle(.secondary)
            } else if checking && snapshot?.hasReading != true {
                Text(L10n.t("Checking OpenClaw…")).foregroundStyle(.secondary)
            } else if let detail = snapshot?.windows.first?.detail {
                Text(detail).foregroundStyle(.secondary).textSelection(.enabled)
            } else {
                Text(snapshot?.statusMessage ?? L10n.t("Connecting to OpenClaw…"))
                    .foregroundStyle(.orange)
            }

            Text(L10n.t("The ring is the chosen session's tokens in context over its window, or the most recently updated session when none is chosen or it is missing. Find keys with `openclaw sessions list`; the key stays on this Mac. Read with `openclaw sessions list --json` at most every 15 seconds."))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}
