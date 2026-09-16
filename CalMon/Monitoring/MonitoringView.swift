import SwiftUI

struct MonitoringView: View {
    let monitor: SystemMonitor
    let maxHeight: CGFloat
    var onClose: () -> Void

    @State private var isExpanded = false
    @State private var isInteracting = false
    @State private var frozenIDs: [String] = []

    private var snapshot: SystemMonitor.Snapshot { monitor.snapshot }
    private var collapsedCount: Int { 8 }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: UIStyle.Metrics.groupSpacing) {
                deviceRow
                cardsRow
                applicationCard
            }
            .padding(UIStyle.Metrics.contentMargin)
            .frame(width: UIStyle.Metrics.monitoringPanelWidth)
        }
        .frame(width: UIStyle.Metrics.monitoringPanelWidth)
        .frame(maxHeight: maxHeight)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) { onClose(); return .handled }
        .onChange(of: monitor.applications.map { $0.id }) { _, _ in
            if !isInteracting { frozenIDs = monitor.applications.map { $0.id } }
        }
    }

    // MARK: - Device

    private var deviceRow: some View {
        // One centered row with a single, constant gap between every item, inset
        // from both content edges.
        HStack(spacing: 14) {
            Text(snapshot.device.chip)
            Text(snapshot.device.osVersion)
            if let memory = snapshot.memory?.total {
                Text(UIStyle.memoryCapacityString(memory))
            }
            if let disk = snapshot.disk?.total {
                Text(UIStyle.diskCapacityString(disk))
            }
            if !snapshot.uptime.isEmpty {
                Text(snapshot.uptime)
            }
        }
        .font(UIStyle.Fonts.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(UIStyle.Metrics.cardPadding)
        .background(cardBackground)
    }

    // MARK: - Cards

    private var cardsRow: some View {
        HStack(alignment: .top, spacing: UIStyle.Metrics.cardSpacing) {
            ringCard(
                title: "CPU",
                color: UIStyle.Colors.cpuRing,
                fraction: snapshot.cpu.usage.map { $0 / 100 },
                percentText: UIStyle.percentString(snapshot.cpu.usage),
                subtitle: cpuSubtitle(snapshot.cpu)
            )
            ringCard(
                title: "内存",
                color: UIStyle.Colors.memoryRing,
                fraction: snapshot.memory?.usedPercent.map { $0 / 100 },
                percentText: UIStyle.percentString(snapshot.memory?.usedPercent),
                subtitle: capacitySubtitle(used: snapshot.memory?.used, total: snapshot.memory?.total, format: UIStyle.memoryCapacityString)
            )
            ringCard(
                title: "磁盘",
                color: UIStyle.Colors.diskRing,
                fraction: snapshot.disk?.usedPercent.map { $0 / 100 },
                percentText: UIStyle.percentString(snapshot.disk?.usedPercent),
                subtitle: capacitySubtitle(used: snapshot.disk?.used, total: snapshot.disk?.total, format: UIStyle.diskCapacityString)
            )
        }
    }

    private func capacitySubtitle(used: UInt64?, total: UInt64?, format: (UInt64) -> String) -> String? {
        guard let used, total != nil else { return nil }
        return "已使用 \(format(used))"
    }

    /// Same-snapshot used amount, one short line per card.
    private func cpuSubtitle(_ cpu: SystemMonitor.CPUSnapshot) -> String? {
        guard cpu.usage != nil else { return nil }
        return "已使用 \(UIStyle.percentString(cpu.usage))"
    }

    private func ringCard(title: String, color: Color, fraction: Double?, percentText: String, subtitle: String?) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(UIStyle.Fonts.groupTitle)
            RingGauge(fraction: fraction, color: color, text: percentText)
            Text(subtitle ?? " ")
                .font(UIStyle.Fonts.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(UIStyle.Metrics.cardPadding)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(percentText)\(subtitle.map { "，\($0)" } ?? "")")
    }

    // MARK: - Applications

    private var applicationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("应用内存占用")
                    .font(UIStyle.Fonts.groupTitle)
                Spacer()
                Text("按内存降序")
                    .font(UIStyle.Fonts.caption)
                    .foregroundStyle(.secondary)
            }

            let rows = orderedRows
            let visible = isExpanded ? rows : Array(rows.prefix(collapsedCount))

            if monitor.applicationState == .loading && rows.isEmpty {
                Text("正在读取…")
                    .font(UIStyle.Fonts.body)
                    .foregroundStyle(.secondary)
                    .frame(height: 36)
            } else if case .unavailable(let reason) = monitor.applicationState, rows.isEmpty {
                Text(reason)
                    .font(UIStyle.Fonts.body)
                    .foregroundStyle(.secondary)
                    .frame(height: 36)
            } else {
                Group {
                    if isExpanded {
                        ScrollView(.vertical) {
                            applicationRows(visible)
                        }
                        .frame(maxHeight: CGFloat(collapsedCount) * UIStyle.Metrics.applicationRowHeight)
                    } else {
                        applicationRows(visible)
                    }
                }
                if rows.count > collapsedCount {
                    Button(isExpanded ? "收起" : "查看更多…") {
                        isExpanded.toggle()
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                }
            }
        }
        .padding(UIStyle.Metrics.cardPadding)
        .background(cardBackground)
        .onHover { hovering in
            isInteracting = hovering
            if !hovering { frozenIDs = monitor.applications.map { $0.id } }
        }
    }

    private func applicationRows(_ rows: [AppMemoryReader.AppUsage]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { usage in
                applicationRow(usage)
            }
        }
    }

    private func applicationRow(_ usage: AppMemoryReader.AppUsage) -> some View {
        let fraction: Double? = {
            guard let bytes = usage.bytes, let total = snapshot.memory?.total, total > 0 else { return nil }
            return Double(bytes) / Double(total)
        }()
        return HStack(spacing: 8) {
            Group {
                if let icon = usage.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: UIStyle.Metrics.applicationIcon, height: UIStyle.Metrics.applicationIcon)

            Text(usage.name)
                .font(UIStyle.Fonts.body)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(usage.bytes.map { UIStyle.memoryString($0) } ?? "--")
                .font(UIStyle.Fonts.body)
                .monospacedDigit()
                .frame(width: UIStyle.Metrics.applicationValueWidth, alignment: .trailing)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: UIStyle.Metrics.applicationBarHeight / 2, style: .continuous)
                    .fill(UIStyle.Colors.track)
                if let fraction {
                    RoundedRectangle(cornerRadius: UIStyle.Metrics.applicationBarHeight / 2, style: .continuous)
                        .fill(UIStyle.Colors.applicationBar)
                        .frame(width: max(0, UIStyle.Metrics.applicationBarWidth * min(1, fraction)))
                }
            }
            .frame(width: UIStyle.Metrics.applicationBarWidth, height: UIStyle.Metrics.applicationBarHeight)
        }
        .frame(height: UIStyle.Metrics.applicationRowHeight)
        .overlay(alignment: .topTrailing) {
            if usage.status == .partial {
                Text("部分数据")
                    .font(UIStyle.Fonts.badge)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usage.name)，\(usage.bytes.map { UIStyle.memoryString($0) } ?? "不可读取")\(usage.status == .partial ? "，部分数据" : "")")
        .help(helpText(for: usage))
    }

    private func helpText(for usage: AppMemoryReader.AppUsage) -> String {
        var text = usage.name
        if let bytes = usage.bytes {
            text += "：\(UIStyle.memoryString(bytes))"
        } else {
            text += "：不可读取"
        }
        text += "（进程 \(usage.readableCount)/\(usage.processCount)）"
        if usage.status == .partial { text += "，部分数据" }
        return text
    }

    private var orderedRows: [AppMemoryReader.AppUsage] {
        if isInteracting {
            var map = Dictionary(uniqueKeysWithValues: monitor.applications.map { ($0.id, $0) })
            var ordered = frozenIDs.compactMap { map.removeValue(forKey: $0) }
            let appended = map.values.sorted { lhs, rhs in
                let l = lhs.bytes ?? 0, r = rhs.bytes ?? 0
                if l != r { return l > r }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            ordered.append(contentsOf: appended)
            return ordered
        }
        return monitor.applications
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: UIStyle.Metrics.cardCorner, style: .continuous)
            .fill(UIStyle.Colors.cardBackground)
    }
}

// MARK: - Ring

struct RingGauge: View {
    let fraction: Double?
    let color: Color
    let text: String
    var diameter: CGFloat = UIStyle.Metrics.ringDiameter
    var lineWidth: CGFloat = UIStyle.Metrics.ringLineWidth

    var body: some View {
        ZStack {
            Circle()
                .stroke(UIStyle.Colors.track, lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.0001, min(1, fraction)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(text)
                .font(UIStyle.Fonts.ringPercent)
                .monospacedDigit()
        }
        .frame(width: diameter, height: diameter)
    }
}
