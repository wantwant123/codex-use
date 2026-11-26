import SwiftUI

struct UsageToolCardView: View {
    let snapshot: UsageSnapshot
    let lastRefreshAt: Date?
    let refreshInterval: RefreshInterval
    let dailyBudget: Int
    let weeklyBudget: Int
    let tokenSpeed: TokenSpeedStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            quotaSection
            tokenGrid
            if snapshot.tool == .antigravity {
                antigravityDetails
            }
            footer

            if let message = snapshot.message, !message.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.top, 1)
                    Text(verbatim: message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .panelCard(padding: 13)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SurfaceStyle.accent(for: snapshot.tool).opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: snapshot.tool.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SurfaceStyle.accent(for: snapshot.tool))
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: snapshot.tool.displayName)
                        .font(.headline)

                    StatusPillView(
                        title: sourceBadgeText,
                        tint: SurfaceStyle.accent(for: snapshot.tool),
                        showDot: false
                    )
                }

                if let tokenSpeed {
                    TokenSpeedInlineRow(tokenSpeed: tokenSpeed)
                } else {
                    Text("usage.budgetHint")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            StatusPillView(title: snapshot.status.title, tint: statusTint)
        }
    }

    @ViewBuilder
    private var quotaSection: some View {
        if snapshot.tool == .antigravity {
            antigravityQuotaSection
        } else {
            codexQuotaSection
        }
    }

    private var codexQuotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if snapshot.hasWeeklyQuota {
                HeroBatteryQuotaBox(
                    titleKey: "usage.weeklyRemaining",
                    percent: snapshot.weeklyRemainingPercent,
                    subtitle: resetText(snapshot.weeklyResetAt),
                    trailingBadge: snapshot.hasFiveHourQuota ? nil : String(localized: "usage.weeklyOnly")
                )
            } else if snapshot.hasFiveHourQuota {
                HeroBatteryQuotaBox(
                    titleKey: "usage.fiveHourRemaining",
                    percent: snapshot.fiveHourRemainingPercent,
                    subtitle: resetText(snapshot.fiveHourResetAt),
                    trailingBadge: nil
                )
            }

            if snapshot.hasFiveHourQuota && snapshot.hasWeeklyQuota {
                CompactQuotaProgressRow(
                    titleKey: "usage.fiveHourRemaining",
                    percent: snapshot.fiveHourRemainingPercent,
                    trailingText: resetText(snapshot.fiveHourResetAt)
                )
            }

            if !snapshot.hasFiveHourQuota && !snapshot.hasWeeklyQuota {
                Text("usage.quotaUnavailable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
                    .insetTile(padding: 10)
            }
        }
    }

    private var antigravityQuotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if snapshot.hasFiveHourQuota || snapshot.hasWeeklyQuota {
                HeroBatteryQuotaBox(
                    titleKey: "usage.dailyBudgetRemaining",
                    percent: snapshot.fiveHourRemainingPercent,
                    subtitle: resetText(snapshot.fiveHourResetAt),
                    trailingBadge: String(
                        format: NSLocalizedString("usage.budgetTarget", comment: ""),
                        UsageFormatters.compactTokenCountText(dailyBudget)
                    )
                )

                CompactQuotaProgressRow(
                    titleKey: "usage.weeklyBudgetRemaining",
                    percent: snapshot.weeklyRemainingPercent,
                    trailingText: String(
                        format: NSLocalizedString("usage.budgetTarget", comment: ""),
                        UsageFormatters.compactTokenCountText(weeklyBudget)
                    ) + " · " + resetText(snapshot.weeklyResetAt)
                )
            } else {
                Text("usage.quotaUnavailable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
                    .insetTile(padding: 10)
            }
        }
    }

    private var tokenGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("usage.tokenUsage")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if snapshot.tool == .codex {
                    Text("usage.localTokenUsageHint")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                TokenMetricTile(
                    titleKey: "usage.todayTokens",
                    value: snapshot.dailyTokenUsage,
                    accent: SurfaceStyle.accent(for: snapshot.tool)
                )
                TokenMetricTile(
                    titleKey: "usage.weekTokens",
                    value: snapshot.weeklyTokenUsage,
                    accent: .blue
                )
                TokenMetricTile(
                    titleKey: "usage.monthTokens",
                    value: snapshot.monthlyTokenUsage,
                    accent: .purple
                )
            }
        }
    }

    @ViewBuilder
    private var antigravityDetails: some View {
        if let breakdown = snapshot.tokenBreakdown, breakdown.totalTokens > 0 {
            TokenBreakdownBarView(breakdown: breakdown)
        }

        if !snapshot.topModels.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("usage.topModels")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 5) {
                    ForEach(snapshot.topModels) { item in
                        HStack(spacing: 4) {
                            Text(verbatim: item.model)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(verbatim: UsageFormatters.compactTokenCountText(item.tokens))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.primary.opacity(0.05), in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5)
                        )
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(verbatim: UsageFormatters.updatedText(snapshot.updatedAt))
            Text(verbatim: "·")
                .foregroundStyle(.tertiary)
            Text(String(
                format: NSLocalizedString("usage.lastChecked", comment: ""),
                lastRefreshAt?.formatted(date: .omitted, time: .shortened) ?? "—"
            ))
            Spacer(minLength: 4)
            Text(verbatim: refreshInterval.title)
                .foregroundStyle(.tertiary)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var sourceBadgeText: String {
        if snapshot.isBudgetEstimated {
            return String(localized: "usage.budgetEstimatedBadge")
        }
        return snapshot.status == .available
            ? String(localized: "usage.liveBadge")
            : String(localized: "usage.localBadge")
    }

    private var statusTint: Color {
        switch snapshot.status {
        case .available: .green
        case .stale: .orange
        case .unavailable: .secondary
        case .error: .red
        }
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
}

private struct TokenSpeedInlineRow: View {
    @ObservedObject var tokenSpeed: TokenSpeedStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8.5))
                .foregroundStyle(tokenSpeed.sample != nil ? .orange : .secondary)
            if tokenSpeed.sample != nil {
                Text(verbatim: tokenSpeed.text)
                    .monospacedDigit()
            } else {
                Text("tokenSpeed.waiting")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help("tokenSpeed.note")
    }
}

private struct HeroBatteryQuotaBox: View {
    let titleKey: LocalizedStringKey
    let percent: Double?
    let subtitle: String
    let trailingBadge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: UsageFormatters.percentText(percent))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(percent == nil ? Color.secondary : Color.primary)
            }

            QuotaBatteryView(
                percent: percent,
                color: SurfaceStyle.remainingColor(percent),
                height: 40
            )
            .accessibilityHidden(true)

            HStack(spacing: 6) {
                Text(verbatim: subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let trailingBadge {
                    Text(verbatim: trailingBadge)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .insetTile(padding: 10, cornerRadius: 12)
    }
}

private struct CompactQuotaProgressRow: View {
    let titleKey: LocalizedStringKey
    let percent: Double?
    let trailingText: String

    private var fraction: Double {
        guard let percent else { return 0 }
        return UsageMath.clampPercent(percent) / 100
    }

    private var tint: Color {
        SurfaceStyle.remainingColor(percent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                Text(verbatim: UsageFormatters.percentText(percent))
                    .font(.caption.weight(.bold).monospacedDigit())
                Text(verbatim: "·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(verbatim: trailingText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
        .insetTile(padding: 8, cornerRadius: 9)
    }
}

private struct TokenMetricTile: View {
    let titleKey: LocalizedStringKey
    let value: Int?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(accent.opacity(0.85))
                    .frame(width: 5, height: 5)
                Text(titleKey)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(verbatim: UsageFormatters.compactTokenCountText(value))
                .font(.system(.callout, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(value == nil ? .secondary : .primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetTile(padding: 8, cornerRadius: 10)
    }
}

private struct TokenBreakdownBarView: View {
    let breakdown: TokenBreakdown

    private var total: Double {
        max(1, Double(breakdown.totalTokens))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("usage.tokenBreakdown")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let hitRate = breakdown.cacheHitRatio {
                    Text(String(
                        format: NSLocalizedString("usage.cacheHitRate", comment: ""),
                        UsageFormatters.percentText(hitRate * 100)
                    ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.teal)
                }
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let inputW = width * Double(breakdown.inputTokens) / total
                let cacheW = width * Double(breakdown.cacheReadTokens) / total
                let outputW = width * Double(breakdown.outputTokens) / total

                HStack(spacing: 1) {
                    if inputW > 0 {
                        Rectangle().fill(Color.blue).frame(width: max(2, inputW))
                    }
                    if cacheW > 0 {
                        Rectangle().fill(Color.teal).frame(width: max(2, cacheW))
                    }
                    if outputW > 0 {
                        Rectangle().fill(Color.purple).frame(width: max(2, outputW))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 5)

            HStack(spacing: 10) {
                legendDot(color: .blue, labelKey: "usage.inputTokens", count: breakdown.inputTokens)
                legendDot(color: .teal, labelKey: "usage.cacheReadTokens", count: breakdown.cacheReadTokens)
                legendDot(color: .purple, labelKey: "usage.outputTokens", count: breakdown.outputTokens)
                Spacer(minLength: 0)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .insetTile(padding: 8, cornerRadius: 10)
    }

    private func legendDot(color: Color, labelKey: LocalizedStringKey, count: Int) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(labelKey)
            Text(verbatim: UsageFormatters.compactTokenCountText(count))
                .foregroundStyle(.primary)
        }
        .lineLimit(1)
    }
}
