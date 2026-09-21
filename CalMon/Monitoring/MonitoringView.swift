import AppKit
import Observation
import SwiftUI

struct MonitoringView: View {
    let monitor: SystemMonitor
    let maxHeight: CGFloat
    @Bindable var search: AppSearchModel
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
                subtitle: cpuValue(snapshot.cpu),
                unusedSubtitle: cpuUnusedValue(snapshot.cpu)
            )
            ringCard(
                title: "内存",
                color: UIStyle.Colors.memoryRing,
                fraction: snapshot.memory?.usedPercent.map { $0 / 100 },
                percentText: UIStyle.percentString(snapshot.memory?.usedPercent),
                subtitle: capacityValue(snapshot.memory?.used, total: snapshot.memory?.total, format: UIStyle.memoryCapacityString),
                unusedSubtitle: capacityValue(snapshot.memory?.unusedCapacity, total: snapshot.memory?.total, format: UIStyle.memoryCapacityString)
            )
            ringCard(
                title: "磁盘",
                color: UIStyle.Colors.diskRing,
                fraction: snapshot.disk?.usedPercent.map { $0 / 100 },
                percentText: UIStyle.percentString(snapshot.disk?.usedPercent),
                subtitle: capacityValue(snapshot.disk?.used, total: snapshot.disk?.total, format: UIStyle.diskCapacityString),
                unusedSubtitle: capacityValue(snapshot.disk?.unusedCapacity, total: snapshot.disk?.total, format: UIStyle.diskCapacityString)
            )
        }
    }

    /// Value only; the "已使用"/"未使用" label is added by `metricLine`.
    private func capacityValue(_ bytes: UInt64?, total: UInt64?, format: (UInt64) -> String) -> String? {
        guard let bytes, total != nil else { return nil }
        return format(bytes)
    }

    private func cpuValue(_ cpu: SystemMonitor.CPUSnapshot) -> String? {
        guard let usage = cpu.usage else { return nil }
        return UIStyle.percentString(usage)
    }

    /// Unused share of the same snapshot; the two lines always sum to 100% by
    /// deriving it from the rounded used value.
    private func cpuUnusedValue(_ cpu: SystemMonitor.CPUSnapshot) -> String? {
        guard let usage = cpu.usage else { return nil }
        return "\(max(0, 100 - Int(usage.rounded())))%"
    }

    private func ringCard(
        title: String,
        color: Color,
        fraction: Double?,
        percentText: String,
        subtitle: String?,
        unusedSubtitle: String?
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(UIStyle.Fonts.groupTitle)
            RingGauge(fraction: fraction, color: color, text: percentText)
                .padding(.bottom, 6)
            // Labels share one left edge so 已使用 / 未使用 line up.
            VStack(alignment: .leading, spacing: 1) {
                metricLine(label: "已使用", value: subtitle)
                metricLine(label: "未使用", value: unusedSubtitle)
            }
            .font(UIStyle.Fonts.caption)
            .foregroundStyle(.secondary)
        }
        .padding(UIStyle.Metrics.cardPadding)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title) \(percentText)"
                + "，已使用 \(subtitle ?? "--")"
                + "，未使用 \(unusedSubtitle ?? "--")"
        )
    }

    private func metricLine(label: String, value: String?) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Text(value ?? "--")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Applications

    private var applicationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("应用内存占用")
                    .font(UIStyle.Fonts.groupTitle)
                Spacer(minLength: 8)
                searchControl
            }
            // Fixed title-row height so expanding never moves the title or card.
            .frame(height: 24)

            let searching = !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let rows = searching ? AppMemoryReader.filter(monitor.applications, query: search.query) : orderedRows
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
            } else if searching && rows.isEmpty {
                Text("未找到匹配应用")
                    .font(UIStyle.Fonts.body)
                    .foregroundStyle(.secondary)
                    .frame(height: 36)
            } else {
                Group {
                    if searching || isExpanded {
                        ScrollView(.vertical) {
                            applicationRows(searching ? rows : visible)
                        }
                        .frame(maxHeight: CGFloat(collapsedCount) * UIStyle.Metrics.applicationRowHeight)
                    } else {
                        applicationRows(visible)
                    }
                }
                if !searching && rows.count > collapsedCount {
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

    /// Round magnifier by default; expands leftwards only. The expanded right
    /// edge is fixed, and the width is capped at the usage-bar width so its left
    /// edge never passes the bars below (SEARCH_AND_YEAR_NAVIGATION.md §2.1).
    @ViewBuilder
    private var searchControl: some View {
        if search.isExpanded {
            SearchField(
                text: $search.query,
                placeholder: "搜索",
                shouldFocus: true,
                onEscape: onClose,
                onEndEditing: { search.endEditing() }
            )
            // Cap the expanded field at the usage-bar width. 4 pt is reserved so
            // the native bezel stroke (drawn just outside the frame) never
            // crosses the bar's left edge below.
            .frame(width: UIStyle.Metrics.applicationBarWidth - 4, height: 24)
        } else {
            Button {
                search.expand()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("搜索应用名称")
            .help("搜索应用名称")
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

// MARK: - Search

/// Transient monitor-panel search state. Not persisted; cleared when the panel
/// is dismissed. Kept out of Preferences on purpose (docs/MONITORING_APP_SEARCH.md).
@MainActor
@Observable
final class AppSearchModel {
    var query = ""
    /// Collapsed (round magnifier) or expanded (native field) entry
    /// (docs/SEARCH_AND_YEAR_NAVIGATION.md §2).
    var isExpanded = false

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isFiltering: Bool { !trimmedQuery.isEmpty }

    /// Every panel presentation starts collapsed and empty (never persisted).
    func beginPresentation() {
        query = ""
        isExpanded = false
    }

    func expand() { isExpanded = true }

    /// Focus left the panel: only collapse when no filter is in effect.
    func endEditing() {
        if !isFiltering { isExpanded = false }
    }
}

/// Compact native search entry (docs/UI_COMPACT_ALIGNMENT.md §2). A light AppKit
/// composite instead of `NSSearchField`, whose built-in magnifier/clear reserve
/// too much of a 64 pt field: a bezelled `NSTextField` with an inline borderless
/// clear button. No self-drawn material; the visible border spans the frame so it
/// lines up with the usage-bar track below.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Focus the field as soon as it appears (used when expanding).
    var shouldFocus = false
    var onEscape: () -> Void
    var onEndEditing: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SearchFieldControl {
        let control = SearchFieldControl()
        control.delegate = context.coordinator
        control.placeholder = placeholder
        control.onTextChange = { [weak coordinator = context.coordinator] value in
            coordinator?.parent.text = value
        }
        control.onClear = { [weak coordinator = context.coordinator] in
            // Clearing keeps the field expanded and focused so typing can continue.
            coordinator?.parent.text = ""
        }
        control.onEscape = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onEscape()
        }
        control.onEndEditing = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onEndEditing()
        }
        context.coordinator.control = control
        control.setText(text)
        return control
    }

    func updateNSView(_ nsView: SearchFieldControl, context: Context) {
        context.coordinator.parent = self
        nsView.placeholder = placeholder
        nsView.setText(text)
        if shouldFocus, !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                nsView.focus()
            }
        } else if !shouldFocus {
            context.coordinator.didFocus = false
        }
    }

    static func dismantleNSView(_ nsView: SearchFieldControl, coordinator: Coordinator) {
        nsView.endEditingNow()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var didFocus = false
        weak var control: SearchFieldControl?

        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            // Do not react to marked (IME composition) text.
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
            parent.text = field.stringValue
            control?.setText(field.stringValue)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
            control?.setText(field.stringValue)
            parent.onEndEditing()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            // Let the input method handle Escape while composing a candidate.
            if let editor = control.currentEditor() as? NSTextView, editor.hasMarkedText() { return false }
            if !parent.text.isEmpty {
                parent.text = ""
                control.stringValue = ""
                self.control?.setText("")
                return true
            }
            parent.onEscape()
            return true
        }
    }
}

/// Bezelled field plus an inline clear button; the field keeps its frame while
/// the text insets reserve the clear area, so nothing shifts when it appears.
final class SearchFieldControl: NSView {
    var placeholder = "搜索" {
        didSet { cell.placeholderString = placeholder }
    }
    var onTextChange: ((String) -> Void)?
    var onClear: (() -> Void)?
    var onEscape: (() -> Void)?
    var onEndEditing: (() -> Void)?

    private static let clearHit: CGFloat = 20
    private static let clearInset: CGFloat = 2

    private let field = NSTextField(frame: .zero)
    private let clearButton = NSButton()
    private var cell: InsetTextFieldCell { field.cell as! InsetTextFieldCell }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let cell = InsetTextFieldCell(textCell: "")
        cell.isBezeled = true
        cell.bezelStyle = .roundedBezel
        cell.controlSize = .small
        cell.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        cell.alignment = .left
        cell.lineBreakMode = .byTruncatingTail
        cell.usesSingleLineMode = true
        cell.placeholderString = placeholder
        field.cell = cell
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .default
        field.delegate = nil
        field.frame = bounds
        field.autoresizingMask = [.width, .height]
        field.setAccessibilityLabel("搜索应用名称")
        addSubview(field)

        clearButton.isBordered = false
        clearButton.bezelStyle = .inline
        clearButton.imagePosition = .imageOnly
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.setAccessibilityLabel("清除搜索")
        clearButton.autoresizingMask = [.minXMargin]
        addSubview(clearButton)
        layoutClearButton()
        updateClearVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Set by the representable so AppKit editing callbacks reach the coordinator.
    var delegate: NSTextFieldDelegate? {
        get { field.delegate }
        set { field.delegate = newValue }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 64, height: 24) }

    func focus() {
        window?.makeFirstResponder(field)
    }

    func endEditingNow() {
        window?.makeFirstResponder(nil)
    }

    func setText(_ value: String) {
        if field.stringValue != value {
            field.stringValue = value
        }
        // While editing, the field editor owns the visible text, so mirror the
        // value there too and keep the caret at the end.
        if let editor = field.currentEditor() as? NSTextView, editor.string != value {
            editor.string = value
            editor.setSelectedRange(NSRange(location: (value as NSString).length, length: 0))
        }
        refreshInsets()
        updateClearVisibility()
    }

    @objc private func clearTapped() {
        field.stringValue = ""
        refreshInsets()
        updateClearVisibility()
        onClear?()
        focus()
    }

    private func layoutClearButton() {
        clearButton.frame = NSRect(
            x: bounds.width - Self.clearInset - Self.clearHit,
            y: (bounds.height - Self.clearHit) / 2,
            width: Self.clearHit,
            height: Self.clearHit
        )
    }

    private func updateClearVisibility() {
        clearButton.isHidden = field.stringValue.isEmpty
        clearButton.isEnabled = !field.stringValue.isEmpty
    }

    /// Left 6 pt; the clear area (20 pt + 2 pt trailing + 2 pt gap) is always
    /// reserved so the text never runs under the button and nothing moves.
    private func refreshInsets() {
        cell.textInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: Self.clearInset + Self.clearHit + 2)
    }

    override func layout() {
        super.layout()
        layoutClearButton()
        refreshInsets()
    }
}
