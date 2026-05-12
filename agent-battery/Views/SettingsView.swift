import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("settings.sectionMenuBarDisplay") {
                Picker("settings.displayMode", selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(mode.title)
                                .frame(width: 80, alignment: .leading)
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

            Section("settings.sectionRefresh") {
                Picker("settings.refreshInterval", selection: refreshIntervalSelection) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
            }

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
                        "github.com/geebos/agent-battery",
                        destination: URL(string: "https://github.com/geebos/agent-battery")!
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
        .frame(width: 520)
        .background(SettingsWindowIdentifierView())
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
