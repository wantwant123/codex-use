import SwiftUI

struct UsageToolCardView: View {
    let snapshot: UsageSnapshot
    let level: UsageLevel
    let lastRefreshAt: Date?
    let refreshInterval: RefreshInterval
    let onSettings: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
            UsageBarRow(
                title: "usage.session",
                dotColor: color(for: level),
                fillFraction: fraction(fromPercent: snapshot.fiveHourRemainingPercent),
                leadingText: percentLeftText(snapshot.fiveHourRemainingPercent),
                trailingText: resetText(snapshot.fiveHourResetAt)
            )

            UsageBarRow(
                title: "usage.weeklyRemaining",
                dotColor: color(for: weeklyLevel),
                fillFraction: fraction(fromPercent: snapshot.weeklyRemainingPercent),
                leadingText: percentLeftText(snapshot.weeklyRemainingPercent),
                trailingText: resetText(snapshot.weeklyResetAt)
            )
        }
    }

    private var tokenRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("usage.tokenUsage")
                .font(.headline)

            ForEach(tokenMetrics) { metric in
                UsageBarRow(
                    title: LocalizedStringKey(metric.titleKey),
                    dotColor: metric.color,
                    fillFraction: tokenFraction(metric.value),
                    leadingText: tokenText(metric.value),
                    trailingText: metric.trailingText
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(verbatim: UsageFormatters.updatedText(lastRefreshAt))
            Spacer()
            Text(String(format: NSLocalizedString("usage.nextUpdate", comment: ""), refreshInterval.title))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private var weeklyLevel: UsageLevel {
        UsageMath.level(for: snapshot.weeklyRemainingPercent, warningThreshold: 40, criticalThreshold: 15)
    }

    private var tokenMetrics: [TokenMetric] {
        [
            TokenMetric(titleKey: "usage.todayTokens", value: snapshot.dailyTokenUsage, color: .green),
            TokenMetric(titleKey: "usage.weekTokens", value: snapshot.weeklyTokenUsage, color: .orange),
            TokenMetric(titleKey: "usage.monthTokens", value: snapshot.monthlyTokenUsage, color: .blue),
        ]
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

        let countdown = UsageFormatters.resetCountdownText(until: date)
        return String(format: NSLocalizedString("usage.resetsIn", comment: ""), countdown)
    }

    private func tokenText(_ value: Int?) -> String {
        String(format: NSLocalizedString("usage.tokensValue", comment: ""), UsageFormatters.compactTokenCountText(value))
    }

    private func color(for level: UsageLevel) -> Color {
        switch level {
        case .normal:
            .green
        case .warning:
            .yellow
        case .critical:
            .red
        case .unavailable:
            .secondary
        }
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
    let fillFraction: Double
    let leadingText: String
    let trailingText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                        .fill(Color(nsColor: .separatorColor).opacity(0.16))

                    Capsule()
                        .fill(Color(red: 0.04, green: 0.08, blue: 0.14))
                        .frame(width: proxy.size.width * fillFraction)
                }
            }
            .frame(height: 13)

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
