import Darwin
import XCTest
@testable import CalMon

@MainActor
final class MonitoringTests: XCTestCase {

    // MARK: - CPU

    private func ticks(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64 = 0) -> SystemMonitor.CPUTicks {
        SystemMonitor.CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    func testCPUIdleIsZero() {
        let previous = ticks(user: 0, system: 0, idle: 0)
        let current = ticks(user: 0, system: 0, idle: 1000)
        XCTAssertEqual(SystemMonitor.cpuUsage(current: current, previous: previous) ?? .nan, 0, accuracy: 0.0001)
    }

    func testCPUFullIsOneHundred() {
        let previous = ticks(user: 0, system: 0, idle: 0)
        let current = ticks(user: 700, system: 300, idle: 0)
        XCTAssertEqual(SystemMonitor.cpuUsage(current: current, previous: previous) ?? .nan, 100, accuracy: 0.0001)
    }

    func testCPUMixed() {
        let previous = ticks(user: 0, system: 0, idle: 0)
        let current = ticks(user: 300, system: 200, idle: 500)
        XCTAssertEqual(SystemMonitor.cpuUsage(current: current, previous: previous) ?? .nan, 50, accuracy: 0.0001)
    }

    func testCPUBreakdownSplitsUserAndSystem() {
        let previous = ticks(user: 0, system: 0, idle: 0)
        let current = ticks(user: 300, system: 200, idle: 500)
        let breakdown = SystemMonitor.cpuBreakdown(current: current, previous: previous)
        XCTAssertEqual(breakdown?.user ?? .nan, 30, accuracy: 0.0001)
        XCTAssertEqual(breakdown?.system ?? .nan, 20, accuracy: 0.0001)
        XCTAssertEqual(breakdown?.idle ?? .nan, 50, accuracy: 0.0001)
        // usage stays the total busy share (user + system; nice folded into system).
        XCTAssertEqual(SystemMonitor.cpuUsage(current: current, previous: previous) ?? .nan, 50, accuracy: 0.0001)
    }

    func testCPUZeroDeltaIsInvalid() {
        let sample = ticks(user: 10, system: 20, idle: 30)
        XCTAssertNil(SystemMonitor.cpuUsage(current: sample, previous: sample))
    }

    func testCPUNoPreviousBaselineIsInvalid() {
        XCTAssertNil(SystemMonitor.cpuUsage(current: ticks(user: 10, system: 0, idle: 10), previous: nil))
    }

    func testCPUResetIsInvalid() {
        // A genuine reset sends the counters back to a tiny value; the wrapped
        // delta would collapse to ~2^32 and must be rejected, not shown as a %.
        let previous = ticks(user: 1_000_000, system: 1_000_000, idle: 1_000_000)
        let current = ticks(user: 50, system: 50, idle: 100)
        XCTAssertNil(SystemMonitor.cpuUsage(current: current, previous: previous, elapsed: 3, coreCount: 10))
        XCTAssertNil(SystemMonitor.cpuBreakdown(current: current, previous: previous, elapsed: 3, coreCount: 10))
    }

    func testCPULargeCounterResetIsInvalid() {
        // A reset from a large (but below 2^31) old value still yields a wrapped
        // delta of ~1.29e9; the interval/core bound must reject it.
        let previous = ticks(user: 3_000_000_000, system: 0, idle: 0)
        let current = ticks(user: 100, system: 0, idle: 0)
        XCTAssertNil(SystemMonitor.cpuUsage(current: current, previous: previous, elapsed: 3, coreCount: 10))
    }

    func testCPUPlausibleBusyIntervalIsAccepted() {
        // 10 cores × ~106 ticks/s × 3 s ≈ 3180; a full-busy interval is accepted.
        let previous = ticks(user: 0, system: 0, idle: 0)
        let current = ticks(user: 2100, system: 1000, idle: 0)
        XCTAssertEqual(SystemMonitor.cpuUsage(current: current, previous: previous, elapsed: 3, coreCount: 10) ?? .nan, 100, accuracy: 0.001)
    }

    func testCPU32BitCounterWrap() {
        let mask = UInt64(UInt32.max)
        let previous = ticks(user: mask - 5, system: 0, idle: 0)
        let current = ticks(user: 5, system: 0, idle: 10)
        // user delta = 11, idle delta = 10 -> 11/21
        let usage = SystemMonitor.cpuUsage(current: current, previous: previous, elapsed: 3, coreCount: 10)
        XCTAssertNotNil(usage)
        XCTAssertEqual(usage!, 11.0 / 21.0 * 100, accuracy: 0.0001)
    }

    // MARK: - Memory

    private func vm(
        physical: UInt64 = 1_000,
        free: UInt64 = 100,
        speculative: UInt64 = 0,
        external: UInt64 = 200,
        purgeable: UInt64 = 50,
        wired: UInt64 = 100,
        compressor: UInt64 = 100,
        internalPages: UInt64 = 400
    ) -> SystemMonitor.VMRaw {
        SystemMonitor.VMRaw(
            pageSize: 16384,
            physical: physical,
            free: free,
            wired: wired,
            purgeable: purgeable,
            speculative: speculative,
            compressor: compressor,
            external: external,
            internalPages: internalPages
        )
    }

    func testMemoryUsedMatchesActivityMonitorFormula() {
        // used = physical - (free - speculative) - fileBacked
        let snapshot = SystemMonitor.memorySnapshot(vm: vm())
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot!.total, 1000)
        XCTAssertEqual(snapshot!.used, 700)         // 1000 - 100 - 200
    }

    func testMemoryUsedTreatsSpeculativeAsUsed() {
        XCTAssertEqual(SystemMonitor.memorySnapshot(vm: vm(speculative: 30))?.used, 730)
    }

    func testMemoryUsedPercent() {
        XCTAssertEqual(SystemMonitor.memorySnapshot(vm: vm(physical: 1000, free: 0, external: 0))?.usedPercent ?? .nan, 100, accuracy: 0.0001)
    }

    func testMemoryRejectsSpeculativeLargerThanFree() {
        XCTAssertNil(SystemMonitor.memorySnapshot(vm: vm(free: 10, speculative: 40)))
    }

    func testMemoryRejectsFreeExceedingPhysical() {
        XCTAssertNil(SystemMonitor.memorySnapshot(vm: vm(free: 2000, external: 500)))
    }

    func testMemoryRejectsPurgeableExceedingInternal() {
        XCTAssertNil(SystemMonitor.memorySnapshot(vm: vm(purgeable: 50, internalPages: 10)))
    }

    func testMemoryRejectsComponentsAboveMeasuredUsage() {
        XCTAssertNil(SystemMonitor.memorySnapshot(vm: vm(external: 700, purgeable: 0, internalPages: 300)))
    }

    func testMemoryRejectsFreeAndExternalAbovePhysical() {
        XCTAssertNil(SystemMonitor.memorySnapshot(vm: vm(free: 400, external: 700)))
    }

    func testMemoryRejectsOverflowingComponentSum() {
        XCTAssertNil(SystemMonitor.memorySnapshot(vm: vm(physical: .max, free: 0, external: 0, purgeable: 0, wired: .max, compressor: 1, internalPages: 1)))
    }

    func testMemorySnapshotRejectsZeroPhysical() {
        XCTAssertNil(SystemMonitor.memorySnapshot(vm: vm(physical: 0)))
    }

    /// Reproduces the recorded real sample from docs/validation/METRICS.md
    /// (same instant as the Activity Monitor English screenshot).
    func testRecordedMemorySampleReproducesRawBytes() throws {
        let page: UInt64 = 16384
        let raw = vm(physical: 34359738368, free: 34593 * page, speculative: 3655 * page,
                     external: 411945 * page, purgeable: 19885 * page, wired: 201643 * page,
                     compressor: 321946 * page, internalPages: 1089589 * page)
        let snapshot = try XCTUnwrap(SystemMonitor.memorySnapshot(vm: raw))
        XCTAssertEqual(snapshot.used, 27103543296)   // 25.2421 GiB, matches Memory Used 25.24
    }

    // MARK: - Process enumeration (R1)

    func testAllPIDsMatchesEnumeratedCount() {
        // `proc_listallpids` returns a PID count, not bytes: the wrapper must not
        // divide it again. Compare against a direct call.
        var buffer = [pid_t](repeating: 0, count: 32768)
        let rawCount = proc_listallpids(&buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        XCTAssertGreaterThan(rawCount, 0)
        let pids = AppMemoryReader.allPIDs()
        XCTAssertGreaterThan(pids.count, 100)
        XCTAssertEqual(Set(pids).count, pids.count)
        XCTAssertLessThanOrEqual(abs(pids.count - Int(rawCount)), 5)
    }

    // MARK: - App name search (docs/MONITORING_APP_SEARCH.md)

    private func usage(_ name: String, bundleID: String = "x") -> AppMemoryReader.AppUsage {
        AppMemoryReader.AppUsage(id: bundleID, name: name, icon: nil, bytes: 1, processCount: 1, readableCount: 1, status: .ok)
    }

    func testSearchMatchesChineseSubstring() {
        let apps = [usage("飞书"), usage("微信")]
        XCTAssertEqual(AppMemoryReader.filter(apps, query: "飞").map(\.name), ["飞书"])
        XCTAssertEqual(AppMemoryReader.filter(apps, query: "飞书").map(\.name), ["飞书"])
    }

    func testSearchIgnoresEnglishCase() {
        let apps = [usage("ChatGPT"), usage("ChatGPT Classic"), usage("微信")]
        XCTAssertEqual(Set(AppMemoryReader.filter(apps, query: "chat").map(\.name)), ["ChatGPT", "ChatGPT Classic"])
        XCTAssertEqual(Set(AppMemoryReader.filter(apps, query: "CHAT").map(\.name)), ["ChatGPT", "ChatGPT Classic"])
    }

    func testSearchTrimsWhitespaceAndBlankReturnsAll() {
        let apps = [usage("飞书"), usage("微信")]
        XCTAssertEqual(AppMemoryReader.filter(apps, query: "  飞  ").map(\.name), ["飞书"])
        XCTAssertEqual(AppMemoryReader.filter(apps, query: "   ").count, 2)
        XCTAssertEqual(AppMemoryReader.filter(apps, query: "").count, 2)
    }

    func testSearchDoesNotMatchPinyinOrBundleID() {
        let apps = [usage("微信", bundleID: "com.tencent.xin")]
        XCTAssertTrue(AppMemoryReader.filter(apps, query: "feishu").isEmpty)
        XCTAssertTrue(AppMemoryReader.filter(apps, query: "tencent").isEmpty)
    }

    func testSearchCoversFullListBeyondFirstEight() {
        var apps = (1...8).map { usage("App\($0)") }
        apps.append(usage("第九个应用"))
        XCTAssertEqual(AppMemoryReader.filter(apps, query: "第九").map(\.name), ["第九个应用"])
    }

    // MARK: - Software aggregation (P3)

    func testRootBundleExtractsTopLevelApp() {
        XCTAssertEqual(AppMemoryReader.rootBundle("/Applications/Lark.app/Contents/MacOS/Lark"), "/Applications/Lark.app")
        XCTAssertEqual(AppMemoryReader.rootBundle("/Applications/Lark.app/Contents/Frameworks/Lark Helper.app/Contents/MacOS/Lark Helper"), "/Applications/Lark.app")
        XCTAssertEqual(AppMemoryReader.rootBundle("/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/X/Helpers/Google Chrome Helper (Renderer)"), "/Applications/Google Chrome.app")
        XCTAssertEqual(AppMemoryReader.rootBundle("/usr/bin/top"), "/usr/bin/top")
    }

    func testNestedHelperAttributesToMainApp() {
        let main = AppMemoryReader.AppDescriptor(
            bundleIdentifier: "com.electron.lark", name: "飞书",
            bundlePath: "/Applications/Lark.app", rootPath: "/Applications/Lark.app", icon: nil
        )
        let ordered = [(offset: 0, element: main)]
        XCTAssertEqual(
            AppMemoryReader.ownerIndex(for: "/Applications/Lark.app/Contents/Frameworks/Lark Helper (Renderer).app/Contents/MacOS/Lark Helper (Renderer)", ordered: ordered),
            0
        )
    }

    func testIndependentAppsAreNotMerged() {
        let chat = AppMemoryReader.AppDescriptor(
            bundleIdentifier: "com.openai.chat", name: "ChatGPT",
            bundlePath: "/Applications/ChatGPT.app", rootPath: "/Applications/ChatGPT.app", icon: nil
        )
        let classic = AppMemoryReader.AppDescriptor(
            bundleIdentifier: "com.openai.chat.classic", name: "ChatGPT Classic",
            bundlePath: "/Applications/ChatGPT Classic.app", rootPath: "/Applications/ChatGPT Classic.app", icon: nil
        )
        let ordered = [(offset: 0, element: chat), (offset: 1, element: classic)]
        XCTAssertEqual(AppMemoryReader.ownerIndex(for: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT", ordered: ordered), 0)
        XCTAssertEqual(AppMemoryReader.ownerIndex(for: "/Applications/ChatGPT Classic.app/Contents/MacOS/ChatGPT Classic", ordered: ordered), 1)
    }

    // MARK: - Formatting / units

    func testPercentageRounding() {
        XCTAssertEqual(UIStyle.percentString(21_400_000_000.0 / 32_000_000_000.0 * 100), "67%")
        XCTAssertEqual(UIStyle.percentString(256.0 / 512.0 * 100), "50%")
        XCTAssertEqual(UIStyle.percentString(0), "0%")
        XCTAssertEqual(UIStyle.percentString(nil), "--%")
        XCTAssertEqual(UIStyle.percentString(.nan), "--%")
    }

    func testMemoryStringUsesBinaryUnits() {
        XCTAssertEqual(UIStyle.memoryString(0), "0 MB")
        XCTAssertEqual(UIStyle.memoryString(500_000), "<1 MB")
        XCTAssertEqual(UIStyle.memoryString(1_048_576), "1 MB")
        XCTAssertEqual(UIStyle.memoryString(999_000_000), "953 MB")
        XCTAssertEqual(UIStyle.memoryString(1_500_000_000), "1.40 GB")
        XCTAssertEqual(UIStyle.memoryString(1_073_741_824), "1.00 GB")
    }

    func testMemoryCapacityUsesBinaryUnits() {
        XCTAssertEqual(UIStyle.memoryCapacityString(34_359_738_368), "32 GB")
        XCTAssertEqual(UIStyle.memoryCapacityString(1_073_741_824), "1 GB")
        XCTAssertEqual(UIStyle.memoryCapacityString(21_474_836_480), "20 GB")
        XCTAssertEqual(UIStyle.memoryCapacityString(25_960_824_832), "24.2 GB")
    }

    func testDiskCapacityUsesDecimalUnits() {
        XCTAssertEqual(UIStyle.diskCapacityString(512_000_000_000), "512 GB")
        XCTAssertEqual(UIStyle.diskCapacityString(494_384_795_648), "494.4 GB")
        XCTAssertEqual(UIStyle.diskCapacityString(1_000_000_000), "1 GB")
    }

    // MARK: - Live read sanity (does not assert machine-specific values)

    func testLiveMemorySamplingForOneMinute() async throws {
        var minimum = Double.infinity
        var maximum = 0.0
        for index in 0..<21 {
            if index > 0 { try await Task.sleep(for: .seconds(3)) }
            let raw = try XCTUnwrap(SystemMonitor.readVMStatistics())
            let snapshot = try XCTUnwrap(SystemMonitor.memorySnapshot(vm: raw), "invalid live sample \(index): \(raw)")
            XCTAssertEqual(snapshot.used, raw.physical - (raw.free - raw.speculative) - raw.external)
            minimum = min(minimum, snapshot.usedPercent!)
            maximum = max(maximum, snapshot.usedPercent!)
        }
        print("CALMON_LIVE_VALIDATION samples=21 duration=60s valid=21 usedPercentMin=\(minimum) usedPercentMax=\(maximum)")
    }

    func testLiveReadsReturnPlausibleValues() throws {
        let vmStats = try XCTUnwrap(SystemMonitor.readVMStatistics())
        XCTAssertGreaterThan(vmStats.physical, 0)
        XCTAssertGreaterThan(vmStats.pageSize, 0)
        let snapshot = try XCTUnwrap(SystemMonitor.memorySnapshot(vm: vmStats))
        XCTAssertLessThanOrEqual(snapshot.used, snapshot.total)

        let ticks = try XCTUnwrap(SystemMonitor.readCPUTicks())
        XCTAssertGreaterThan(ticks.user + ticks.system + ticks.idle, 0)
    }

    // MARK: - Collapsible search entry (docs/SEARCH_AND_YEAR_NAVIGATION.md §2)

    func testSearchStartsCollapsedAndResetsBetweenPresentations() {
        let search = AppSearchModel()
        XCTAssertFalse(search.isExpanded)
        search.expand()
        search.query = "飞"
        search.beginPresentation()
        XCTAssertFalse(search.isExpanded)
        XCTAssertEqual(search.query, "")
    }

    func testSearchCollapsesOnBlurOnlyWhenEmpty() {
        let search = AppSearchModel()
        search.expand()
        search.endEditing()
        XCTAssertFalse(search.isExpanded, "empty query must collapse on blur")

        search.expand()
        search.query = "飞"
        search.endEditing()
        XCTAssertTrue(search.isExpanded, "an active filter must stay visible")

        search.query = "   "
        search.endEditing()
        XCTAssertFalse(search.isExpanded, "whitespace is not a filter")
    }

    func testSearchFilteringMatchesTrimmedQuery() {
        let search = AppSearchModel()
        XCTAssertFalse(search.isFiltering)
        search.query = " 飞 "
        XCTAssertTrue(search.isFiltering)
        XCTAssertEqual(search.trimmedQuery, "飞")
    }
}
