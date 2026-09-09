import SwiftUI

struct ProxyTrafficSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ProxyTrafficStore
    @State private var address = ""
    @State private var secret = ""
    @State private var message: String?

    var body: some View {
        Section("traffic.title") {
            Toggle("traffic.enabled", isOn: $settings.trafficEnabled)
            Toggle("traffic.showMenuBar", isOn: $settings.showTrafficInMenuBar)
                .disabled(!settings.trafficEnabled)
            Toggle("traffic.showQuota", isOn: $settings.showQuotaWithTraffic)
                .disabled(!settings.trafficEnabled || !settings.showTrafficInMenuBar)
            TextField("traffic.controller", text: $address)
            SecureField("traffic.secret", text: $secret)
            HStack {
                Text("traffic.localOnly").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("traffic.apply") { apply() }
            }
            if let message {
                Text(LocalizedStringKey(message)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            address = settings.proxyControllerAddress
            secret = ProxyControllerSecret.read()
        }
    }

    private func apply() {
        guard (try? ProxyTrafficClient.makeRequest(address: address, secret: secret)) != nil else {
            message = "traffic.invalidAddress"
            return
        }
        guard ProxyControllerSecret.save(secret) else {
            message = "traffic.secretFailed"
            return
        }
        if settings.proxyControllerAddress == address {
            store.restart()
        } else {
            settings.proxyControllerAddress = address
        }
        message = "traffic.applied"
    }
}
