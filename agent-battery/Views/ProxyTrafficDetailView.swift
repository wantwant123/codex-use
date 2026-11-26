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

    private var countryName: String? {
        guard let code = store.countryCode else { return nil }
        return Locale.current.localizedString(forRegionCode: code)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            metricsRow
            TrafficHistoryView(points: store.snapshot.history)
                .panelCard(padding: 12, cornerRadius: 12)
            tableSection
            footer
        }
        .padding(18)
        .frame(minWidth: 780, minHeight: 620)
        .onChange(of: domains) { _, value in
            if !value { selectedApp = nil }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("traffic.newSession", systemImage: "arrow.clockwise") { store.restart() }
                Button("traffic.settings", systemImage: "gearshape") { openSettings() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("traffic.clashTitle")
                        .font(.title2.bold())

                    if let countryName {
                        Text(verbatim: countryName)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.primary.opacity(0.07), in: Capsule())
                    }

                    HStack(spacing: 5) {
                        ProxyHealthIndicator(health: store.currentHealth)
                        Text(verbatim: store.currentHealth.kind.title)
                            .font(.caption.weight(.medium))
                        if let latency = store.currentHealth.latencyMS {
                            Text(verbatim: "· \(latency) ms")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.75))
                }

                HStack(spacing: 8) {
                    Text(LocalizedStringKey(store.statusKey))
                        .foregroundStyle(store.isLive ? Color.secondary : Color.orange)
                    if !store.isLive, let updated = store.snapshot.updatedAt {
                        Text(verbatim: "·")
                            .foregroundStyle(.tertiary)
                        Text("traffic.lastUpdate")
                            .foregroundStyle(.secondary)
                        Text(updated, format: .dateTime.month().day().hour().minute().second())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }

            Spacer()

            if let start = store.snapshot.startedAt {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("traffic.since")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(start, format: .dateTime.month().day().hour().minute())
                        .font(.callout.weight(.semibold).monospacedDigit())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.75)
                )
            }
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 10) {
            metricCard(
                title: "traffic.downloadSpeed",
                value: TrafficFormat.speed(store.speed?.download),
                symbol: "arrow.down.circle.fill",
                tint: .blue
            )
            metricCard(
                title: "traffic.uploadSpeed",
                value: TrafficFormat.speed(store.speed?.upload),
                symbol: "arrow.up.circle.fill",
                tint: .orange
            )
            metricCard(
                title: "traffic.downloadTotal",
                value: TrafficFormat.bytes(store.snapshot.total.download),
                symbol: "arrow.down.doc",
                tint: .teal
            )
            metricCard(
                title: "traffic.uploadTotal",
                value: TrafficFormat.bytes(store.snapshot.total.upload),
                symbol: "arrow.up.doc",
                tint: .indigo
            )
        }
    }

    private var tableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("traffic.group", selection: $domains) {
                    Text("traffic.apps").tag(false)
                    Text("traffic.domains").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 156)

                Picker("traffic.routeLabel", selection: $route) {
                    ForEach(TrafficRoute.allCases) { route in
                        Text(route.title).tag(route)
                    }
                }
                .labelsHidden()
                .frame(width: 148)

                let total = rows.reduce(TrafficBytes()) { $0 + $1.bytes }
                HStack(spacing: 6) {
                    Text("traffic.filtered")
                        .foregroundStyle(.secondary)
                    Text(verbatim: "↓ \(TrafficFormat.bytes(total.download))  ↑ \(TrafficFormat.bytes(total.upload))")
                        .fontWeight(.medium)
                }
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.primary.opacity(0.05), in: Capsule())

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("traffic.search", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(width: 200)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let selectedApp {
                HStack(spacing: 8) {
                    Button {
                        self.selectedApp = nil
                        domains = false
                        search = ""
                    } label: {
                        Label("traffic.backApps", systemImage: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text(verbatim: selectedApp.isEmpty ? String(localized: "traffic.unknownApp") : URL(fileURLWithPath: selectedApp).lastPathComponent)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                            HStack(spacing: 4) {
                                Text(verbatim: row.title)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.borderless)
                        .help(Text("traffic.appDomains"))
                    } else {
                        Text(verbatim: row.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(row.title)
                    }
                }
                .width(min: 150, ideal: 230)

                TableColumn("traffic.downloadSpeed") { row in
                    Text(verbatim: TrafficFormat.speed(store.speed == nil ? nil : row.speed.download))
                        .foregroundStyle(.blue)
                }
                TableColumn("traffic.uploadSpeed") { row in
                    Text(verbatim: TrafficFormat.speed(store.speed == nil ? nil : row.speed.upload))
                        .foregroundStyle(.orange)
                }
                TableColumn("traffic.downloadTotal") { row in
                    Text(verbatim: TrafficFormat.bytes(row.bytes.download))
                }
                TableColumn("traffic.uploadTotal") { row in
                    Text(verbatim: TrafficFormat.bytes(row.bytes.upload))
                }
                TableColumn("traffic.usesProxy") { row in
                    Text(verbatim: row.routeTitle)
                        .lineLimit(1)
                        .help(row.routeTitle)
                }
                .width(min: 110, ideal: 160)
            }
            .monospacedDigit()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if rows.isEmpty {
                    Text("traffic.empty")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .panelCard(padding: 12, cornerRadius: 12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("traffic.unassigned")
                Text(verbatim: "↓ \(TrafficFormat.bytes(store.snapshot.unassigned.download))  ↑ \(TrafficFormat.bytes(store.snapshot.unassigned.upload))")
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.8))
                Spacer()
                if store.storageFailed {
                    Text("traffic.storageFailed").foregroundStyle(.orange)
                } else if store.snapshot.hasGaps {
                    Text("traffic.gapNote").foregroundStyle(.orange)
                } else if store.snapshot.isLimited {
                    Text("traffic.limitNote").foregroundStyle(.secondary)
                }
            }
            Text("traffic.sampleNote")
            Text("traffic.healthNote")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func metricCard(title: LocalizedStringKey, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(verbatim: value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard(padding: 11, cornerRadius: 12)
    }
}

private struct TrafficHistoryView: View {
    let points: [TrafficPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("traffic.history")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                legendPill(title: "traffic.download", color: .blue)
                legendPill(title: "traffic.upload", color: .orange)
            }
            .font(.caption2)

            Chart(points) { point in
                AreaMark(
                    x: .value(String(localized: "traffic.time"), point.date),
                    y: .value("B/s", point.speed.download),
                    series: .value(String(localized: "traffic.direction"), "down-area-\(point.segment)")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.20), Color.blue.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value(String(localized: "traffic.time"), point.date),
                    y: .value("B/s", point.speed.download),
                    series: .value(String(localized: "traffic.direction"), "down-\(point.segment)")
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                LineMark(
                    x: .value(String(localized: "traffic.time"), point.date),
                    y: .value("B/s", point.speed.upload),
                    series: .value(String(localized: "traffic.direction"), "up-\(point.segment)")
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.25))
                    AxisValueLabel {
                        if let value = value.as(Double.self) {
                            Text(verbatim: TrafficFormat.speed(value))
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
            }
            .frame(height: 118)
        }
    }

    private func legendPill(title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).foregroundStyle(.secondary)
        }
    }
}
