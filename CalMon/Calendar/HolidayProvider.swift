@preconcurrency import EventKit
import Foundation
import Observation

/// Owns the calendar data sources:
/// - 24 solar terms (versioned static JSON; calendrical data, not holidays).
/// - Festival names and explicit 休/班 markers from a system calendar via EventKit.
///
/// Rule: there is no built-in holiday or adjusted-workday data. Festivals and
/// 休/班 markers come only from a system calendar the user has authorized; when
/// nothing is available the calendar simply shows a plain Gregorian/lunar grid.
/// Nothing is guessed from weekends or holiday names.
@MainActor
@Observable
final class HolidayProvider {

    // MARK: - Types

    /// Explicit 休/班 marker carried by a system event; never inferred.
    enum Marker: String, Equatable {
        case holiday
        case workday
    }

    struct Festival: Identifiable, Equatable {
        var id: String
        var title: String
        var sourceTitle: String?
        /// Set only for holiday-arrangement rows (e.g. "国庆节（休）").
        var marker: Marker? = nil
    }

    enum SourceStatus: Equatable {
        case inactive
        case active(String)
        case error(String)
    }

    enum AccessState: Equatable {
        case notDetermined
        case requesting
        case authorized
        case denied
        case restricted
    }

    // MARK: - Solar terms (built-in calendrical data)

    private struct SolarTermFile: Decodable {
        struct Term: Decodable { let name: String; let date: String }
        let year: Int
        let source: String?
        let sourceURL: String?
        let terms: [Term]
    }

    private(set) var solarTermYears: [Int] = []
    private var solarTermByKey: [String: String] = [:]

    /// Bumped whenever cached calendar data changes so views can rebuild.
    private(set) var revision = 0

    // MARK: - EventKit

    /// EKEventStore is documented as safe for concurrent reads; the fetch runs
    /// off the main actor. `nonisolated(unsafe)` records that intent.
    nonisolated(unsafe) private let store = EKEventStore()
    var selectedCalendarID: String?
    var selectedCalendarTitle: String?
    private(set) var sourceStatus: SourceStatus = .inactive
    private(set) var accessState: AccessState = .notDetermined
    private(set) var isRequestingAccess = false
    private(set) var accessError: String?
    private(set) var holidayCalendarTitle: String?
    /// Public metadata of every discovered calendar, kept as evidence of what the
    /// automatic recognition considered.
    private(set) var candidateDetails: [String] = []
    private(set) var holidayCandidates: [String] = []
    var hasHolidayCalendar: Bool { holidayCalendarTitle != nil }

    private var eventsByKey: [String: [Festival]] = [:]
    private var arrangementsByKey: [String: [Festival]] = [:]
    private var markersByKey: [String: Marker] = [:]
    private var loadedRange: DateInterval?
    private(set) var generation = 0
    private let fetchQueue = DispatchQueue(label: "com.calmon.calendar.fetch", qos: .utility)
    private var observer: NSObjectProtocol?

    private let calendar: Calendar
    private let authorizationCheck: () -> Bool

    init(calendar: Calendar = .current, authorizationCheck: @escaping () -> Bool = HolidayProvider.isAuthorized) {
        self.calendar = calendar
        self.authorizationCheck = authorizationCheck
        loadSolarTerms()
        startObservingStore()
    }

    // MARK: - Solar terms

    private func loadSolarTerms() {
        for year in 2025...2027 {
            if let file: SolarTermFile = Self.decodeResource("\(year)", subdirectory: "SolarTerms") {
                solarTermYears.append(file.year)
                for term in file.terms {
                    solarTermByKey[term.date] = term.name
                }
            }
        }
        solarTermYears.sort()
        revision += 1
    }

    private static func decodeResource<T: Decodable>(_ name: String, subdirectory: String) -> T? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory),
            Bundle.main.url(forResource: name, withExtension: "json"),
            Bundle.main.resourceURL?.appendingPathComponent("\(subdirectory)/\(name).json")
        ]
        for case let url? in candidates {
            if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) {
                return value
            }
        }
        return nil
    }

    func solarTerm(on date: Date) -> String? {
        solarTermByKey[Self.dayKey(date, calendar: calendar)]
    }

    // MARK: - Authorization

    nonisolated static func isAuthorized() -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return true
        default: return false
        }
    }

    /// Reads the real system status. Checking access is not requesting it.
    func refreshAccessState() {
        if isRequestingAccess { accessState = .requesting; return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: accessState = .authorized
        case .denied: accessState = .denied
        case .restricted: accessState = .restricted
        // Write-only cannot read festivals; treat it as not granted for reading.
        case .writeOnly: accessState = .denied
        default: accessState = .notDetermined
        }
    }

    /// Requests access only when the user taps; never called automatically.
    func requestAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            isRequestingAccess = true
            accessState = .requesting
            accessError = nil
            store.requestFullAccessToEvents { [weak self] granted, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isRequestingAccess = false
                    if let error {
                        self.accessError = error.localizedDescription
                    } else if !granted {
                        self.accessError = "用户拒绝了日历访问"
                    }
                    self.refreshAccessState()
                    if granted {
                        self.autoDiscoverSource()
                    } else {
                        self.invalidateEvents()
                    }
                }
            }
        default:
            refreshAccessState()
            autoDiscoverSource()
        }
    }

    /// Drops cached events, invalidates any in-flight fetch and republishes so the
    /// calendar UI rebuilds without stale data.
    private func invalidateEvents() {
        generation += 1
        loadedRange = nil
        reloadRange = nil
        eventsByKey = [:]
        markersByKey = [:]
        arrangementsByKey = [:]
        revision += 1
    }

    // MARK: - Source discovery

    /// Discovers a Chinese holiday calendar using public calendar metadata after
    /// access is granted. Falls back to a plain calendar when nothing matches.
    func autoDiscoverSource() {
        refreshAccessState()
        guard accessState == .authorized else {
            invalidateEvents()
            return
        }
        let calendars = store.calendars(for: .event)
        candidateDetails = calendars.map {
            "\($0.title) [type=\($0.type.rawValue) immutable=\($0.isImmutable) allowsModifications=\($0.allowsContentModifications) source=\($0.source?.title ?? "-")]"
        }
        let matched = calendars.filter { Self.holidayCalendarCandidate($0) }
        holidayCandidates = matched.map(\.title)
        if ProcessInfo.processInfo.environment["CALMON_DUMP_CALENDAR"] == "1" {
            for detail in candidateDetails {
                FileHandle.standardError.write(Data("CAND \(detail)\n".utf8))
            }
            FileHandle.standardError.write(Data("CAND matched=\(holidayCandidates.joined(separator: " | "))\n".utf8))
        }

        // Keep the current choice when it is still a candidate; otherwise take the
        // first candidate. Removing and re-adding sources is handled by the store
        // change observer, so this re-runs discovery.
        let chosen = matched.first(where: { $0.calendarIdentifier == selectedCalendarID }) ?? matched.first
        guard let chosen else {
            selectedCalendarID = nil
            selectedCalendarTitle = nil
            holidayCalendarTitle = nil
            sourceStatus = .inactive
            invalidateEvents()
            return
        }
        selectedCalendarID = chosen.calendarIdentifier
        selectedCalendarTitle = chosen.title
        holidayCalendarTitle = chosen.title
        sourceStatus = .active(chosen.title)
        reloadEvents()
    }

    /// Conservative public-metadata match. A China marker plus a holiday marker in
    /// the calendar title, and the calendar must be read-only/subscribed/immutable
    /// so an editable personal calendar with a similar name is not read.
    /// Recorded in `candidateDetails` for review.
    nonisolated static func holidayCalendarCandidate(_ calendar: EKCalendar) -> Bool {
        let readOnly = calendar.type == .subscription || calendar.isImmutable || !calendar.allowsContentModifications
        if holidayCalendarCandidate(title: calendar.title, isReadOnly: readOnly) { return true }
        // Read-only holiday calendar from a China-related source.
        let title = normalize(calendar.title)
        let source = normalize(calendar.source?.title ?? "")
        let hasHoliday = title.contains("节假日") || title.contains("节日") || title.contains("holiday")
        let chinaSource = source.contains("中国") || source.contains("china") || source.contains("chinese")
        return hasHoliday && readOnly && chinaSource
    }

    nonisolated static func holidayCalendarCandidate(title: String) -> Bool {
        let normalized = normalize(title)
        let hasChina = normalized.contains("中国") || normalized.contains("china")
            || normalized.contains("chinese") || normalized.contains("prc")
        let hasHoliday = normalized.contains("节假日") || normalized.contains("节日") || normalized.contains("holiday")
        return hasChina && hasHoliday
    }

    /// Title match plus the read-only requirement; separated for unit testing.
    nonisolated static func holidayCalendarCandidate(title: String, isReadOnly: Bool) -> Bool {
        holidayCalendarCandidate(title: title) && isReadOnly
    }

    func disconnect() {
        selectedCalendarID = nil
        selectedCalendarTitle = nil
        holidayCalendarTitle = nil
        sourceStatus = .inactive
        invalidateEvents()
    }

    private func startObservingStore() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleStoreChange() }
        }
    }

    /// Sources may be added or removed while the app is running. Re-discover first
    /// (still using the notification, no polling), then reload the visible range.
    func handleStoreChange() {
        refreshAccessState()
        guard accessState == .authorized else {
            invalidateEvents()
            return
        }
        autoDiscoverSource()
    }

    // MARK: - Event fetching

    /// Ensures the festivals for the given visible grid range are loaded.
    /// Only the current range is cached; switching months replaces it.
    func ensureEvents(range: DateInterval) {
        guard selectedCalendarID != nil else {
            eventsByKey = [:]
            arrangementsByKey = [:]
            markersByKey = [:]
            return
        }
        // Do not churn or re-fetch while access is not granted.
        guard authorizationCheck() else { return }
        if let loaded = loadedRange, loaded.start <= range.start, loaded.end >= range.end {
            return
        }
        loadEvents(range: range)
    }

    func reloadEvents() {
        if selectedCalendarID != nil, !authorizationCheck() {
            sourceStatus = .error("系统节日暂不可用")
            invalidateEvents()
            return
        }
        let range = reloadRange
        invalidateEvents()
        if let range {
            reloadRange = range
            loadEvents(range: range)
        }
    }

    /// Publishes a fetched result only if it is still current, the source is still
    /// selected and access is still authorized. Internal so it can be unit-tested.
    func publishFetchedEvents(_ festivals: [String: [Festival]], arrangements: [String: [Festival]], markers: [String: Marker], range: DateInterval, requestedGeneration: Int, calendarID: String, calendarTitle: String) {
        guard requestedGeneration == generation else { return }
        guard selectedCalendarID == calendarID else { return }
        guard authorizationCheck() else {
            sourceStatus = .error("系统节日暂不可用")
            invalidateEvents()
            return
        }
        eventsByKey = festivals
        arrangementsByKey = arrangements
        markersByKey = markers
        loadedRange = range
        revision += 1
        if case .active = sourceStatus {} else {
            sourceStatus = .active(calendarTitle)
        }
    }

    private var reloadRange: DateInterval?

    private func loadEvents(range: DateInterval) {
        guard let calendarID = selectedCalendarID else { return }
        guard let eventCalendar = store.calendars(for: .event).first(where: { $0.calendarIdentifier == calendarID }) else {
            sourceStatus = .error("系统节日暂不可用")
            selectedCalendarID = nil
            selectedCalendarTitle = nil
            invalidateEvents()
            return
        }
        reloadRange = range
        generation += 1
        let requestedGeneration = generation
        nonisolated(unsafe) let store = self.store
        let calendarRefID = eventCalendar.calendarIdentifier
        let calendarTitle = eventCalendar.title
        let displayCalendar = self.calendar

        fetchQueue.async { [weak self] in
            guard let self else { return }
            // Re-fetch the calendar from its identifier inside the queue so no
            // non-Sendable EKCalendar crosses the concurrency boundary.
            guard let eventCalendar = store.calendar(withIdentifier: calendarRefID) else {
                Task { @MainActor in
                    guard requestedGeneration == self.generation else { return }
                    self.sourceStatus = .error("系统节日暂不可用")
                    self.selectedCalendarID = nil
                    self.selectedCalendarTitle = nil
                    self.invalidateEvents()
                }
                return
            }
            let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: [eventCalendar])
            let events = store.events(matching: predicate)
            if ProcessInfo.processInfo.environment["CALMON_DUMP_CALENDAR"] == "1" {
                FileHandle.standardError.write(Data("CALDUMP calendar=\(calendarTitle) count=\(events.count)\n".utf8))
                for event in events.sorted(by: { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }) {
                    let s = Self.dayKey(event.startDate, calendar: displayCalendar)
                    let e = Self.dayKey(event.endDate, calendar: displayCalendar)
                    FileHandle.standardError.write(Data("CALDUMP \(s)..\(e) allDay=\(event.isAllDay) title=\(event.title ?? "")\n".utf8))
                }
            }
            let mapped = Self.map(events: events, range: range, calendar: displayCalendar)
            Task { @MainActor in
                self.publishFetchedEvents(mapped.festivals, arrangements: mapped.arrangements, markers: mapped.markers, range: range, requestedGeneration: requestedGeneration, calendarID: calendarRefID, calendarTitle: calendarTitle)
            }
        }
    }

    /// Maps the selected holiday calendar's events.
    ///
    /// The calendar carries two kinds of entries:
    /// - normal calendar entries (festivals, solar terms), e.g. "白露", "中秋节";
    /// - holiday-arrangement entries with a （休）/（班） suffix, e.g.
    ///   "中秋节（休）" (rest range) or "国庆节（班）" (adjusted workday).
    ///
    /// Arrangement entries only set the 休/班 marker and are never shown as a
    /// festival name, so 休/班 never gets smeared and a 补班 day shows only the
    /// marker. Normal entries show their name on the first day only.
    nonisolated static func map(events: [EKEvent], range: DateInterval, calendar: Calendar) -> (festivals: [String: [Festival]], arrangements: [String: [Festival]], markers: [String: Marker]) {
        var festivals: [String: [Festival]] = [:]
        var arrangements: [String: [Festival]] = [:]
        var markers: [String: Marker] = [:]
        for event in events {
            guard let start = event.startDate, let end = event.endDate else { continue }
            let rawTitle = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawTitle.isEmpty else { continue }
            let sourceTitle = event.calendar?.title
            let marker = marker(forTitle: rawTitle)
            let firstDay = calendar.startOfDay(for: max(start, range.start))
            let limit = min(end, range.end)
            var day = firstDay
            var guardCount = 0
            while day < limit && guardCount < 400 {
                let key = Self.dayKey(day, calendar: calendar)
                if let marker {
                    markers[key] = marker
                    // The arrangement title (e.g. "国庆节（休）") is shown for every
                    // day of the range in the detail, but never smeared on the grid.
                    let arrangement = Festival(
                        id: "\(event.eventIdentifier ?? UUID().uuidString)-\(key)",
                        title: rawTitle,
                        sourceTitle: sourceTitle,
                        marker: marker
                    )
                    var list = arrangements[key] ?? []
                    if !list.contains(where: { Self.normalize($0.title) == Self.normalize(rawTitle) }) {
                        list.append(arrangement)
                    }
                    arrangements[key] = list
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                guardCount += 1
            }

            // Plain calendar entries contribute a display name once, on the first day.
            if marker == nil {
                let name = festivalTitle(rawTitle)
                guard !name.isEmpty else { continue }
                let key = Self.dayKey(firstDay, calendar: calendar)
                let normalized = Self.normalize(name)
                let festival = Festival(id: "\(event.eventIdentifier ?? UUID().uuidString)-\(key)", title: name, sourceTitle: sourceTitle)
                var list = festivals[key] ?? []
                if !list.contains(where: { Self.normalize($0.title) == normalized }) {
                    list.append(festival)
                }
                festivals[key] = list
            }
        }
        return (festivals, arrangements, markers)
    }

    /// A 休/班 marker from an arrangement entry. Recognises the （休）/（班）
    /// suffix used by the system China holiday calendar, plus bare 休/班 titles.
    nonisolated static func marker(forTitle title: String) -> Marker? {
        if title.contains("（休）") || title.contains("(休)") { return .holiday }
        if title.contains("（班）") || title.contains("(班)") { return .workday }
        switch normalize(title) {
        case "休", "休息", "放假", "holiday": return .holiday
        case "班", "上班", "补班", "workday": return .workday
        default: return nil
        }
    }

    /// The display name for a plain calendar entry, with any arrangement suffix
    /// stripped.
    nonisolated static func festivalTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "（休）", with: "")
            .replacingOccurrences(of: "(休)", with: "")
            .replacingOccurrences(of: "（班）", with: "")
            .replacingOccurrences(of: "(班)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Per-day queries

    /// EventKit festivals for a local date, deduplicated.
    func systemFestivals(on date: Date) -> [Festival] {
        eventsByKey[Self.dayKey(date, calendar: calendar)] ?? []
    }

    /// Explicit 休/班 marker for a local date, if the system source provides one.
    func marker(on date: Date) -> Marker? {
        markersByKey[Self.dayKey(date, calendar: calendar)]
    }

    /// Combined list for the detail panel: plain festival entries plus the
    /// holiday-arrangement titles (e.g. "国庆节（休）"), deduplicated by title.
    func detailFestivals(on date: Date) -> [Festival] {
        let key = Self.dayKey(date, calendar: calendar)
        var result = eventsByKey[key] ?? []
        for arrangement in arrangementsByKey[key] ?? [] {
            if !result.contains(where: { Self.normalize($0.title) == Self.normalize(arrangement.title) }) {
                result.append(arrangement)
            }
        }
        return result
    }

    // MARK: - Helpers

    nonisolated static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    nonisolated static func normalize(_ title: String) -> String {
        title
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{3000}", with: "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
            .lowercased()
    }
}
