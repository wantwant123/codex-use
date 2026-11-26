import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    private static let dailyBudgetPresets = [2_000_000, 5_000_000, 10_000_000, 20_000_000, 50_000_000, 100_000_000]
    private static let weeklyBudgetPresets = [10_000_000, 25_000_000, 50_000_000, 100_000_000, 200_000_000, 500_000_000]

    var body: some View {
        TabView {
            menuBarTab
                .tabItem {
                    Label("settings.tabMenuBar", systemImage: "menubar.rectangle")
                }

            toolsTab
                .tabItem {
                    Label("settings.tabTools", systemImage: "cpu")
                }

            proxyTab
                .tabItem {
                    Label("settings.tabProxy", systemImage: "network")
                }

            generalTab
                .tabItem {
                    Label("settings.tabGeneral", systemImage: "gearshape")
                }
        }
        .frame(width: 540, height: 470)
        .background(SettingsWindowIdentifierView())
    }

    private var menuBarTab: some View {
        Form {
            Section("settings.sectionMenuBarDisplay") {
                Picker("settings.menuBarSource", selection: $settings.menuBarQuotaSource) {
                    ForEach(MenuBarQuotaSource.allCases) { source in
                        Text(verbatim: source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                Picker("settings.displayMode", selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(mode.title)
                                .frame(width: 72, alignment: .leading)
                            MenuBarModePreviewRow(settings: settings, mode: mode)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                if settings.menuBarDisplayMode.supportsPercentToggle {
                    Toggle("settings.showPercent", isOn: $settings.showMenuBarPercent)
                }

                Toggle("settings.colorByUsage", isOn: $settings.colorByUsage)

                if settings.colorByUsage {
                    UsageColorBar(settings: settings)
                }
            }

            Section("settings.sectionVisibility") {
                Toggle("settings.showClockInMenuBar", isOn: $settings.showClockInMenuBar)
                Toggle("settings.showTokenSpeedInMenuBar", isOn: $settings.showTokenSpeedInMenuBar)
                Toggle("traffic.showHealthInMenuBar", isOn: $settings.showProxyHealthInMenuBar)
                    .disabled(!settings.trafficEnabled)

                Text("settings.menuBarVisibilityHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var toolsTab: some View {
        Form {
            Section("settings.sectionAntigravity") {
                BudgetPickerRow(
                    titleKey: "settings.dailyTokenBudget",
                    value: $settings.antigravityDailyTokenBudget,
                    presets: Self.dailyBudgetPresets,
                    step: 1_000_000,
                    range: 100_000...500_000_000
                )

                BudgetPickerRow(
                    titleKey: "settings.weeklyTokenBudget",
                    value: $settings.antigravityWeeklyTokenBudget,
                    presets: Self.weeklyBudgetPresets,
                    step: 5_000_000,
                    range: 500_000...2_000_000_000
                )

                HStack(spacing: 8) {
                    TextField("settings.brainPath", text: $settings.antigravityBrainPath)
                        .textFieldStyle(.roundedBorder)
                    if settings.antigravityBrainPath != UsageDefaults.antigravityBrainPath {
                        Button("settings.resetDefault") {
                            settings.antigravityBrainPath = UsageDefaults.antigravityBrainPath
                        }
                        .controlSize(.small)
                    }
                }

                Text("settings.antigravityBudgetHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("settings.sectionCodex") {
                Picker("settings.refreshInterval", selection: refreshIntervalSelection) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    TextField("settings.sessionsPath", text: $settings.codexSessionsPath)
                        .textFieldStyle(.roundedBorder)
                    if settings.codexSessionsPath != UsageDefaults.codexSessionsPath {
                        Button("settings.resetDefault") {
                            settings.codexSessionsPath = UsageDefaults.codexSessionsPath
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var proxyTab: some View {
        Form {
            Section("traffic.clashTitle") {
                Toggle("traffic.enabled", isOn: $settings.trafficEnabled)
                Text("traffic.clashSource")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("traffic.healthNote")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section("settings.sectionLaunch") {
                Toggle(
                    "settings.launchAtLogin",
                    isOn: Binding(
                        get: { settings.launchAtLoginEnabled },
                        set: { settings.setLaunchAtLoginEnabled($0) }
                    )
                )

                if let message = settings.launchAtLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("settings.sectionAbout") {
                HStack {
                    Text("settings.version")
                    Spacer()
                    Text(Self.appVersionDisplay)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Text("settings.github")
                    Spacer()
                    Link(
                        "github.com/wantwant123/codex-use",
                        destination: URL(string: "https://github.com/wantwant123/codex-use")!
                    )
                }

                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("settings.starHint")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var refreshIntervalSelection: Binding<RefreshInterval> {
        Binding(
            get: {
                settings.refreshInterval
            },
            set: { newValue in
                guard settings.refreshInterval != newValue else {
                    return
                }

                DispatchQueue.main.async {
                    settings.refreshInterval = newValue
                }
            }
        )
    }

    private static let appVersionDisplay: String = {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? ""
        let build = (info?["CFBundleVersion"] as? String) ?? ""
        if version.isEmpty && build.isEmpty {
            return "-"
        }
        if build.isEmpty {
            return "v\(version)"
        }
        if version.isEmpty {
            return "(\(build))"
        }
        return "v\(version) (\(build))"
    }()
}

private struct BudgetPickerRow: View {
    let titleKey: LocalizedStringKey
    @Binding var value: Int
    let presets: [Int]
    let step: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(titleKey)
                Spacer()
                Text(verbatim: UsageFormatters.compactTokenCountText(value))
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Stepper(
                    "",
                    value: $value,
                    in: range,
                    step: step
                )
                .labelsHidden()
                .controlSize(.small)
            }

            HStack(spacing: 5) {
                ForEach(presets, id: \.self) { preset in
                    let selected = value == preset
                    Button {
                        value = preset
                    } label: {
                        Text(verbatim: UsageFormatters.compactTokenCountText(preset))
                            .font(.caption2.weight(selected ? .semibold : .regular).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(
                                selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(selected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
