import SwiftUI

struct MenuBarClockView: View {
    @ObservedObject var settings: AppSettings
    @Binding var choosingTimeZone: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                choosingTimeZone.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TimelineView(.everyMinute) { context in
                    Text(verbatim: MenuBarClock.dateTime(at: context.date, in: settings.clockTimeZone))
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }

                Text(verbatim: MenuBarClock.city(in: settings.clockTimeZone))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: choosingTimeZone ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .help("clock.changeTimeZone")
        .accessibilityLabel(Text("clock.changeTimeZone"))
        .accessibilityValue(MenuBarClock.city(in: settings.clockTimeZone))
    }
}

struct TimeZonePickerDrawer: View {
    @ObservedObject var settings: AppSettings
    @Binding var isPresented: Bool
    @State private var search = ""

    private var timeZones: [ClockTimeZone] {
        ClockTimeZone.all.filter { $0.matches(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("clock.search", text: $search)
                    .textFieldStyle(.plain)
                    .font(.callout)
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
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(timeZones) { zone in
                        Button {
                            settings.clockTimeZoneIdentifier = zone.id
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isPresented = false
                            }
                            search = ""
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: zone.city)
                                        .font(.callout)
                                    Text(verbatim: zone.id)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if settings.clockTimeZoneIdentifier == zone.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                settings.clockTimeZoneIdentifier == zone.id
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if timeZones.isEmpty {
                        Text("clock.noResults")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }
            .frame(height: 156)
        }
        .panelCard(padding: 10, cornerRadius: 12)
    }
}
