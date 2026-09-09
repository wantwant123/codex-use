import SwiftUI

struct ProxyTrafficSummaryView: View {
    @ObservedObject var store: ProxyTrafficStore
    let openDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("traffic.title", systemImage: "network")
                    .font(.headline)
                Spacer()
                ProxyHealthIndicator(health: store.currentHealth)
            }
            HStack {
                Text(verbatim: "↓ \(TrafficFormat.speed(store.speed?.download))")
                    .foregroundStyle(.blue)
                Spacer()
                Text(verbatim: "↑ \(TrafficFormat.speed(store.speed?.upload))")
                    .foregroundStyle(.orange)
            }
            .monospacedDigit()
            HStack {
                Text("traffic.sessionTotal")
                Spacer()
                Text(verbatim: store.snapshot.startedAt == nil ? "—" : TrafficFormat.bytes(store.snapshot.total.total))
                    .monospacedDigit()
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(LocalizedStringKey(store.statusKey))
                .font(.caption).foregroundStyle(.secondary)
            Text(verbatim: store.currentHealth.kind.title)
                .font(.caption).foregroundStyle(.secondary)
            Button(action: openDetails) {
                HStack {
                    Text("traffic.details")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(.borderless)
        }
    }
}
