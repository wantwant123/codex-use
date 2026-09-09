import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @ObservedObject var traffic: ProxyTrafficStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageToolCardView(
                snapshot: store.snapshot(for: .codex),
                lastRefreshAt: store.lastRefreshAt,
                refreshInterval: settings.refreshInterval,
                onSettings: showSettings,
                onRefresh: store.refresh
            )

            if settings.trafficEnabled {
                Divider()
                ProxyTrafficSummaryView(store: traffic) {
                    dismiss()
                    openWindow(id: "traffic")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            Divider()

            HStack {
                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("menu.quit", systemImage: "power")
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }

    private func showSettings() {
        SettingsWindowPresenter.show(dismissingMenuBarPanel: {
            dismiss()
        }) {
            openSettings()
        }
    }
}
