import SwiftUI

struct UsageToolCardView: View {
    let snapshot: UsageSnapshot
    let lastRefreshAt: Date?
    let refreshInterval: RefreshInterval
    let onSettings: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            actions
            quotaRows
            tokenRows
            footer

            if let message = snapshot.message, !message.isEmpty {
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: 310, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("tool.codexName")
                .font(.title3)
                .fontWeight(.bold)

            Spacer()

            Text(snapshot.status.title)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.background.secondary, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
                )
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            DashboardButton(title: "menu.settings", systemImage: "gearshape", action: onSettings)
            DashboardButton(title: "menu.refresh", systemImage: "arrow.clockwise", action: onRefresh)
        }
    }

    private var quotaRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.hasFiveHourQuota {
                UsageBarRow(
                    title: "usage.fiveHourRemaining",
                    dotColor: remainingColor(snapshot.fiveHourRemainingPercent),
                    fillColor: remainingColor(snapshot.fiveHourRemainingPercent),
                    fillFraction: fraction(fromPercent: snapshot.fiveHourRemainingPercent),
                    leadingText: percentLeftText(snapshot.fiveHourRemainingPercent),
                    trailingText: resetText(snapshot.fiveHourResetAt)
                )
            }

            if snapshot.hasWeeklyQuota {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("usage.weeklyRemaining")
                            .font(.headline)
                        Spacer()
                        Text(verbatim: UsageFormatters.percentText(snapshot.weeklyRemainingPercent))
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }

                    QuotaBatteryView(
                        percent: snapshot.weeklyRemainingPercent,
                        color: remainingColor(snapshot.weeklyRemainingPercent)
                    )
                    .accessibilityHidden(true)

                    Text(verbatim: resetText(snapshot.weeklyResetAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !snapshot.hasFiveHourQuota {
                        Text("usage.weeklyOnly")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                )
            }

            if !snapshot.hasFiveHourQuota && !snapshot.hasWeeklyQuota {
                Text("usage.quotaUnavailable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tokenRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("usage.tokenUsage")
                .font(.headline)
            Text("usage.localTokenUsageHint")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(tokenMetrics) { metric in
                UsageBarRow(
                    title: LocalizedStringKey(metric.titleKey),
                    dotColor: metric.color,
                    fillColor: tokenFillColor,
                    fillFraction: tokenFraction(metric.value),
                    leadingText: tokenText(metric.value),
                    trailingText: metric.trailingText
                )
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: UsageFormatters.updatedText(snapshot.updatedAt))
            HStack {
                Text(String(format: NSLocalizedString("usage.lastChecked", comment: ""), lastRefreshAt?.formatted(date: .omitted, time: .shortened) ?? "—"))
                Spacer()
                Text(String(format: NSLocalizedString("usage.nextUpdate", comment: ""), refreshInterval.title))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private var tokenMetrics: [TokenMetric] {
        [
            TokenMetric(titleKey: "usage.todayTokens", value: snapshot.dailyTokenUsage, color: tokenFillColor),
            TokenMetric(titleKey: "usage.weekTokens", value: snapshot.weeklyTokenUsage, color: tokenFillColor),
            TokenMetric(titleKey: "usage.monthTokens", value: snapshot.monthlyTokenUsage, color: tokenFillColor),
        ]
    }

    private var tokenFillColor: Color {
        Color(red: 0.04, green: 0.42, blue: 0.95)
    }

    private var maxTokenUsage: Int {
        max(tokenMetrics.compactMap(\.value).max() ?? 0, 1)
    }

    private func fraction(fromPercent percent: Double?) -> Double {
        guard let percent else {
            return 0
        }

        return UsageMath.clampPercent(percent) / 100
    }

    private func tokenFraction(_ value: Int?) -> Double {
        guard let value else {
            return 0
        }

        return min(max(Double(value) / Double(maxTokenUsage), 0), 1)
    }

    private func percentLeftText(_ percent: Double?) -> String {
        String(format: NSLocalizedString("usage.percentLeft", comment: ""), UsageFormatters.percentText(percent))
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else {
            return String(localized: "usage.resetUnknown")
        }

        guard date > Date() else {
            return String(localized: "usage.resetPending")
        }

        let countdown = UsageFormatters.resetCountdownText(until: date)
        return String(format: NSLocalizedString("usage.resetsIn", comment: ""), countdown)
    }

    private func tokenText(_ value: Int?) -> String {
        String(format: NSLocalizedString("usage.tokensValue", comment: ""), UsageFormatters.compactTokenCountText(value))
    }

    private func remainingColor(_ percent: Double?) -> Color {
        guard let percent else {
            return .secondary
        }

        let clamped = UsageMath.clampPercent(percent) / 100
        return Color(
            hue: 0.33 * clamped,
            saturation: 0.84,
            brightness: 0.82
        )
    }
}

private struct DashboardButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }
}

private struct UsageBarRow: View {
    let title: LocalizedStringKey
    let dotColor: Color
    let fillColor: Color
    let fillFraction: Double
    let leadingText: String
    let trailingText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .separatorColor).opacity(0.10))

                    Capsule()
                        .fill(fillColor)
                        .frame(width: proxy.size.width * fillFraction)
                }
            }
            .frame(height: 7)

            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: leadingText)
                Spacer()
                Text(verbatim: trailingText)
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct TokenMetric: Identifiable {
    var id: String { titleKey }
    let titleKey: String
    let value: Int?
    let color: Color

    var trailingText: String {
        value == nil ? String(localized: "usage.noTokenData") : ""
    }
}
