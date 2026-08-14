import SwiftUI

struct LLMUsageHeatmapCard: View {
    let entries: [LLMCallLogEntry]
    @ObservedObject var pricingStore: LLMPricingStore

    @State private var selectedModel = allModelsKey

    private static let allModelsKey = "__all_models__"
    private static let weekCount = 26
    private static let cellSize: CGFloat = 13
    private static let cellSpacing: CGFloat = 4

    private var modelOptions: [String] {
        Array(Set(entries.map(\.model)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var filteredEntries: [LLMCallLogEntry] {
        guard selectedModel != Self.allModelsKey else { return entries }
        return entries.filter { $0.model == selectedModel }
    }

    private var calendar: LLMUsageCalendar {
        LLMUsageCalendar(entries: filteredEntries, weekCount: Self.weekCount)
    }

    private var summary: LLMUsageSummary {
        LLMUsageSummary(entries: filteredEntries, pricingStore: pricingStore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("每日调用热点")
                        .font(.title3.weight(.semibold))
                    Text("最近 26 周，颜色越深表示当天调用次数越多")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("模型", selection: $selectedModel) {
                    Text("全部模型").tag(Self.allModelsKey)
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            heatmap

            HStack(spacing: 16) {
                Label("\(summary.calls) 次调用", systemImage: "arrow.trianglehead.2.clockwise")
                Label("\(summary.totalTokens.formatted()) Token", systemImage: "number")
                Label(
                    summary.estimatedCostUSD.formatted(.currency(code: "USD")),
                    systemImage: "dollarsign.circle"
                )
                Spacer()
                heatLegend
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
        .onChange(of: modelOptions) { _, options in
            if selectedModel != Self.allModelsKey, !options.contains(selectedModel) {
                selectedModel = Self.allModelsKey
            }
        }
    }

    private var heatmap: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: Self.cellSpacing) {
                Color.clear.frame(width: 22, height: 14)
                ForEach(Array(firstWeek.enumerated()), id: \.offset) { index, day in
                    Text(index.isMultiple(of: 2) ? weekdayLabel(day.date) : "")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: Self.cellSize, alignment: .trailing)
                }
            }

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 5) {
                    monthLabels

                    HStack(alignment: .top, spacing: Self.cellSpacing) {
                        ForEach(Array(calendar.weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: Self.cellSpacing) {
                                ForEach(week) { day in
                                    heatCell(day)
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("每日调用热点")
        .accessibilityValue("最近 26 周共 \(summary.calls) 次调用，\(summary.totalTokens) Token")
    }

    private var firstWeek: [LLMUsageCalendar.Day] {
        calendar.weeks.first ?? []
    }

    private var monthLabels: some View {
        HStack(spacing: Self.cellSpacing) {
            ForEach(Array(calendar.weeks.enumerated()), id: \.offset) { index, week in
                Text(monthLabel(for: week, index: index) ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: Self.cellSize, height: 14, alignment: .leading)
                    .zIndex(monthLabel(for: week, index: index) == nil ? 0 : 1)
            }
        }
    }

    private func heatCell(_ day: LLMUsageCalendar.Day) -> some View {
        let level = intensity(for: day.calls)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(cellColor(level: level, isFuture: day.isFuture))
            .frame(width: Self.cellSize, height: Self.cellSize)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(day.isFuture ? 0.05 : 0.08), lineWidth: 0.5)
            }
            .help(dayHelp(day))
    }

    private var heatLegend: some View {
        HStack(spacing: 5) {
            Text("少")
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(cellColor(level: level, isFuture: false))
                    .frame(width: 11, height: 11)
            }
            Text("多")
        }
    }

    private func intensity(for calls: Int) -> Int {
        guard calls > 0 else { return 0 }
        let maximum = max(calendar.maximumCallsPerDay, 1)
        return min(4, max(1, Int(ceil(Double(calls) / Double(maximum) * 4))))
    }

    private func cellColor(level: Int, isFuture: Bool) -> Color {
        if isFuture {
            return Color.primary.opacity(0.015)
        }
        guard level > 0 else {
            return Color.primary.opacity(0.055)
        }
        return Color.accentColor.opacity(0.18 + Double(level) * 0.19)
    }

    private func dayHelp(_ day: LLMUsageCalendar.Day) -> String {
        let date = day.date.formatted(.dateTime.year().month().day())
        if day.isFuture {
            return date
        }
        return "\(date)：\(day.calls) 次调用，\(day.totalTokens.formatted()) Token"
    }

    private func weekdayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private func monthLabel(for week: [LLMUsageCalendar.Day], index: Int) -> String? {
        guard let first = week.first else { return nil }
        if index == 0 {
            return first.date.formatted(.dateTime.month(.abbreviated))
        }
        guard let firstDayOfMonth = week.first(where: {
            Calendar.autoupdatingCurrent.component(.day, from: $0.date) == 1
        }) else { return nil }
        return firstDayOfMonth.date.formatted(.dateTime.month(.abbreviated))
    }
}
