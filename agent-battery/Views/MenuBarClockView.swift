import SwiftUI

struct MenuBarClockView: View {
    @ObservedObject var settings: AppSettings
    @State private var choosingTimeZone = false
    @State private var search = ""

    private var timeZones: [ClockTimeZone] {
        ClockTimeZone.all.filter { $0.matches(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TimelineView(.everyMinute) { context in
                    Text(verbatim: MenuBarClock.dateTime(at: context.date, in: settings.clockTimeZone))
                        .font(.headline.monospacedDigit())
                }
                Spacer()
                Button {
                    choosingTimeZone.toggle()
                    search = ""
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: MenuBarClock.city(in: settings.clockTimeZone))
                            .lineLimit(1)
                        Image(systemName: choosingTimeZone ? "chevron.up" : "chevron.down")
                    }
                }
                .buttonStyle(.borderless)
                .help("clock.changeTimeZone")
                .accessibilityLabel(Text("clock.changeTimeZone"))
                .accessibilityValue(MenuBarClock.city(in: settings.clockTimeZone))
            }

            if choosingTimeZone {
                TextField("clock.search", text: $search)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(timeZones) { zone in
                            Button {
                                settings.clockTimeZoneIdentifier = zone.id
                                choosingTimeZone = false
                                search = ""
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: zone.city)
                                        Text(verbatim: zone.id)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if settings.clockTimeZoneIdentifier == zone.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .padding(6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if timeZones.isEmpty {
                            Text("clock.noResults")
                                .foregroundStyle(.secondary)
                                .padding(6)
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }
}
