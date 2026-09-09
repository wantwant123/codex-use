import SwiftUI

@main
struct AgentBatteryApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var store: UsageStore
    @StateObject private var traffic: ProxyTrafficStore

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: UsageStore(settings: settings))
        _traffic = StateObject(wrappedValue: ProxyTrafficStore(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView(settings: settings, store: store, traffic: traffic)
                .frame(width: 340)
                .onAppear {
                    store.refresh()
                }
        } label: {
            HStack(spacing: 6) {
                if !settings.trafficEnabled || !settings.showTrafficInMenuBar || settings.showQuotaWithTraffic {
                    MenuBarLabelView(settings: settings, store: store)
                }
                if settings.trafficEnabled && settings.showTrafficInMenuBar {
                    ProxyTrafficMenuLabel(store: traffic)
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("traffic.title", id: "traffic") {
            ProxyTrafficDetailView(store: traffic)
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(settings: settings, traffic: traffic)
        }
    }
}
