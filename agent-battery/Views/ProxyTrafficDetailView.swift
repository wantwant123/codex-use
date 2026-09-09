import Charts
import SwiftUI

struct ProxyTrafficDetailView: View {
    @ObservedObject var store: ProxyTrafficStore
    @State private var route = TrafficRoute.all
    @State private var domains = false
    @State private var selectedApp: String?
    @State private var search = ""
    @Environment(\.openSettings) private var openSettings

    private var rows: [TrafficRow] {
        store.snapshot.rows(domains: domains, route: route, app: selectedApp)
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(spacing: 12) {
                metric("traffic.downloadSpeed", value: TrafficFormat.speed(store.speed?.download), color: .blue)
                metric("traffic.uploadSpeed", value: TrafficFormat.speed(store.speed?.upload), color: .orange)
                metric("traffic.downloadTotal", value: TrafficFormat.bytes(store.snapshot.total.download))
                metric("traffic.uploadTotal", value: TrafficFormat.bytes(store.snapshot.total.upload))
            }
            TrafficHistoryView(points: store.snapshot.history)
                .frame(height: 125)
            Divider()
            filters
            HStack {
                Text("traffic.filtered")
                let total = rows.reduce(TrafficBytes()) { $0 + $1.bytes }
                Text(verbatim: "↓ \(TrafficFormat.bytes(total.download))  ↑ \(TrafficFormat.bytes(total.upload))")
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let selectedApp {
                HStack {
                    Button {
                        self.selectedApp = nil
                        domains = false
                        search = ""
                    } label: { Label("traffic.backApps", systemImage: "chevron.left") }
                    Text(verbatim: selectedApp.isEmpty ? String(localized: "traffic.unknownApp") : URL(fileURLWithPath: selectedApp).lastPathComponent)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Table(rows) {
                TableColumn("traffic.name") { row in
                    if !domains && row.id != TrafficKey.overflow {
                        Button {
                            selectedApp = row.id
                            domains = true
                            search = ""
                        } label: {
                            HStack {
                                Text(verbatim: row.title).lineLimit(1).truncationMode(.middle)
                                Image(systemName: "chevron.right").font(.caption2)
                            }
                        }
                        .buttonStyle(.borderless)
                        .help(Text("traffic.appDomains"))
                    } else {
                        Text(verbatim: row.title).lineLimit(1).truncationMode(.middle).help(row.title)
                    }
                }
                .width(min: 140, ideal: 220)
                TableColumn("traffic.downloadSpeed") { row in
                    Text(verbatim: TrafficFormat.speed(store.speed == nil ? nil : row.speed.download))
                }
                TableColumn("traffic.uploadSpeed") { row in
                    Text(verbatim: TrafficFormat.speed(store.speed == nil ? nil : row.speed.upload))
                }
                TableColumn("traffic.downloadTotal") { row in
                    Text(verbatim: TrafficFormat.bytes(row.bytes.download))
                }
                TableColumn("traffic.uploadTotal") { row in
                    Text(verbatim: TrafficFormat.bytes(row.bytes.upload))
                }
            }
            .monospacedDigit()
            .overlay {
                if rows.isEmpty { Text("traffic.empty").foregroundStyle(.secondary) }
            }
            footer
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 620)
        .onChange(of: domains) { _, value in
            if !value { selectedApp = nil }
        }
        .toolbar {
            Button("traffic.settings", systemImage: "gearshape") { openSettings() }
            Button("traffic.newSession", systemImage: "arrow.clockwise") { store.restart() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("traffic.title").font(.title2.bold())
                Text(LocalizedStringKey(store.statusKey))
                    .font(.caption).foregroundStyle(store.isLive ? Color.secondary : Color.orange)
                if !store.isLive, let updated = store.snapshot.updatedAt {
                    HStack {
                        Text("traffic.lastUpdate")
                        Text(updated, format: .dateTime.month().day().hour().minute().second())
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let start = store.snapshot.startedAt {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("traffic.since").font(.caption).foregroundStyle(.secondary)
                    Text(start, format: .dateTime.month().day().hour().minute()).monospacedDigit()
                }
            }
        }
    }

    private var filters: some View {
        HStack {
            Picker("traffic.group", selection: $domains) {
                Text("traffic.apps").tag(false)
                Text("traffic.domains").tag(true)
            }
            .pickerStyle(.segmented).frame(width: 160)
            Picker("traffic.routeLabel", selection: $route) {
                ForEach(TrafficRoute.allCases) { route in Text(route.title).tag(route) }
            }
            .frame(width: 175)
            Spacer()
            TextField("traffic.search", text: $search)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 230)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("traffic.unassigned")
                Text(verbatim: "↓ \(TrafficFormat.bytes(store.snapshot.unassigned.download))  ↑ \(TrafficFormat.bytes(store.snapshot.unassigned.upload))")
                    .monospacedDigit()
            }
            Text("traffic.sampleNote")
            if store.snapshot.hasGaps { Text("traffic.gapNote").foregroundStyle(.orange) }
            if store.snapshot.isLimited { Text("traffic.limitNote") }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func metric(_ title: LocalizedStringKey, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TrafficHistoryView: View {
    let points: [TrafficPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("traffic.history").foregroundStyle(.secondary)
                Spacer()
                Text("traffic.download").foregroundStyle(.blue)
                Text("traffic.upload").foregroundStyle(.orange)
            }
            .font(.caption)
            Chart(points) { point in
                LineMark(x: .value(String(localized: "traffic.time"), point.date), y: .value("B/s", point.speed.download),
                         series: .value(String(localized: "traffic.direction"), "down-\(point.segment)"))
                    .foregroundStyle(.blue)
                LineMark(x: .value(String(localized: "traffic.time"), point.date), y: .value("B/s", point.speed.upload),
                         series: .value(String(localized: "traffic.direction"), "up-\(point.segment)"))
                    .foregroundStyle(.orange)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let value = value.as(Double.self) { Text(verbatim: TrafficFormat.speed(value)) }
                    }
                }
            }
        }
    }
}
