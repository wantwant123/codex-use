import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @ObservedObject var traffic: ProxyTrafficStore
    @ObservedObject var tokenSpeed: TokenSpeedStore

    @State private var choosingTimeZone = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topUtilityBar

            if choosingTimeZone {
                TimeZonePickerDrawer(settings: settings, isPresented: $choosingTimeZone)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ToolSwitcherBar(
                selectedTool: $settings.selectedTool,
                store: store
            )

            UsageToolCardView(
                snapshot: store.snapshot(for: settings.selectedTool),
                lastRefreshAt: store.lastRefreshAt,
                refreshInterval: settings.refreshInterval,
                dailyBudget: settings.antigravityDailyTokenBudget,
                weeklyBudget: settings.antigravityWeeklyTokenBudget,
                tokenSpeed: settings.selectedTool == .codex ? tokenSpeed : nil
            )

            if settings.trafficEnabled {
                ProxyTrafficSummaryView(store: traffic) {
                    dismiss()
                    openWindow(id: "traffic")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        .padding(12)
    }

    private var topUtilityBar: some View {
        HStack(spacing: 6) {
            MenuBarClockView(settings: settings, choosingTimeZone: $choosingTimeZone)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                TopIconButton(systemImage: "arrow.clockwise", helpKey: "menu.refresh") {
                    store.refresh()
                }
                TopIconButton(systemImage: "gearshape", helpKey: "menu.settings") {
                    showSettings()
                }
                TopIconButton(systemImage: "power", helpKey: "menu.quit", isDestructive: true) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func showSettings() {
        SettingsWindowPresenter.show(dismissingMenuBarPanel: {
            dismiss()
        }) {
            openSettings()
        }
    }
}

private struct ToolSwitcherBar: View {
    @Binding var selectedTool: UsageTool
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 5) {
            ForEach(UsageTool.allCases) { tool in
                let isSelected = selectedTool == tool
                let snapshot = store.snapshot(for: tool)
                let percent = snapshot.menuBarRemainingPercent
                let accent = SurfaceStyle.accent(for: tool)

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedTool = tool
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tool.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? accent : .secondary)

                        Text(verbatim: tool.displayName)
                            .font(.callout.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        Text(verbatim: UsageFormatters.percentText(percent))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(percent == nil ? .secondary : SurfaceStyle.remainingColor(percent))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (percent == nil ? Color.secondary : SurfaceStyle.remainingColor(percent)).opacity(0.14),
                                in: Capsule()
                            )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.primary.opacity(0.09) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? accent.opacity(0.40) : Color.clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.75)
        )
    }
}

private struct TopIconButton: View {
    let systemImage: String
    let helpKey: LocalizedStringKey
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isHovered && isDestructive ? Color.red : (isHovered ? Color.primary : Color.secondary))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.10) : Color.primary.opacity(0.04))
                )
                .overlay(
                    Circle()
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
        .help(helpKey)
        .accessibilityLabel(helpKey)
        .onHover { isHovered = $0 }
    }
}
