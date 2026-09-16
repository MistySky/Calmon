import XCTest
@testable import CalMon

@MainActor
final class LifecycleTests: XCTestCase {

    private func freshDefaults() -> (UserDefaults, String) {
        let name = "CalMonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    func testDefaultPreferences() {
        let (defaults, _) = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.showCalendar)
        XCTAssertTrue(preferences.showMonitoring)
        XCTAssertTrue(preferences.showWeekday)
        XCTAssertTrue(preferences.showLunar)
        XCTAssertTrue(preferences.showChineseHolidays)
        XCTAssertTrue(preferences.weekStartsOnMonday)
    }

    func testPreferencesPersist() {
        let (defaults, name) = freshDefaults()
        let first = Preferences(defaults: defaults)
        first.showCalendar = false
        first.showMonitoring = true
        first.showWeekday = false
        first.showLunar = false
        first.showChineseHolidays = false
        first.weekStartsOnMonday = false

        let second = Preferences(defaults: defaults)
        XCTAssertFalse(second.showCalendar)
        XCTAssertTrue(second.showMonitoring)
        XCTAssertFalse(second.showWeekday)
        XCTAssertFalse(second.showLunar)
        XCTAssertFalse(second.showChineseHolidays)
        XCTAssertFalse(second.weekStartsOnMonday)

        defaults.removePersistentDomain(forName: name)
    }

    func testDisablingCalendarRetainsChildSettings() {
        let (defaults, name) = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.showWeekday = false
        preferences.showLunar = false
        preferences.showCalendar = false

        let reloaded = Preferences(defaults: defaults)
        XCTAssertFalse(reloaded.showCalendar)
        XCTAssertFalse(reloaded.showWeekday)
        XCTAssertFalse(reloaded.showLunar)

        defaults.removePersistentDomain(forName: name)
    }

    func testMonitorNotStartedHasNoSnapshot() {
        let monitor = SystemMonitor()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertNil(monitor.snapshot.memory)
        XCTAssertNil(monitor.snapshot.cpu.usage)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertTrue(monitor.applications.isEmpty)
    }

    func testMonitorStartStopLifecycle() {
        let monitor = SystemMonitor()
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.start() // idempotent, no duplicate timer
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertNil(monitor.snapshot.cpu.usage)
        monitor.setPanelVisible(false)
        XCTAssertNil(monitor.snapshot.disk)
    }

    func testMonitorWakeResetsBaseline() {
        let monitor = SystemMonitor()
        monitor.start()
        monitor.handleWake()
        XCTAssertNil(monitor.snapshot.cpu.usage)
        monitor.stop()
    }

    func testPanelOpenCloseControlsApplicationSampling() {
        let monitor = SystemMonitor()
        monitor.start()
        monitor.setPanelVisible(true)
        XCTAssertTrue(monitor.isRunning)
        monitor.setPanelVisible(false)
        XCTAssertTrue(monitor.applications.isEmpty)
        XCTAssertEqual(monitor.applicationState, .idle)
        monitor.stop()
    }

    /// R2: the settings toggle drives sampling; stopping must clear live values.
    func testStopClearsLiveMonitoringValues() {
        let monitor = SystemMonitor()
        monitor.start()
        monitor.setPanelVisible(true)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertNil(monitor.snapshot.cpu.usage)
        XCTAssertNil(monitor.snapshot.disk)
        XCTAssertTrue(monitor.applications.isEmpty)
        // Re-enabling starts a fresh schedule.
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
    }

    /// R6/F4: a real application sample that completes after the panel closed
    /// must be discarded, and the icon cache it refilled must be trimmed. A gated
    /// reader makes the completion point deterministic (no fixed sleeps).
    func testStaleApplicationSampleAfterPanelCloseIsDiscarded() {
        let reader = GatedReader()
        let monitor = SystemMonitor(reader: reader)
        monitor.start()
        waitUntilIdle(monitor)

        reader.startGating()
        monitor.setPanelVisible(true)
        XCTAssertTrue(reader.waitUntilSampling(), "application sample never started")

        monitor.setPanelVisible(false)
        let trimsBeforeCompletion = reader.trimCount
        reader.stopGating()
        reader.releaseSample()

        waitUntilIdle(monitor)
        XCTAssertTrue(monitor.applications.isEmpty, "stale sample repopulated the closed panel")
        XCTAssertEqual(monitor.applicationState, .idle)
        XCTAssertGreaterThan(reader.trimCount, trimsBeforeCompletion, "completed stale sample did not trigger another trim")
        XCTAssertFalse(reader.hasCachedSample, "stale sample refilled the cache after close")
        monitor.stop()
    }

    /// F4: opening the panel while a sample is in flight must still sample
    /// applications immediately once that sample finishes.
    func testPanelOpenQueuesImmediateSample() {
        let reader = GatedReader()
        let monitor = SystemMonitor(reader: reader)
        monitor.start()
        reader.startGating()
        // The very first tick may already be running; force a follow-up.
        monitor.setPanelVisible(true)
        XCTAssertTrue(reader.waitUntilSampling(), "application sample never started")
        reader.stopGating()
        reader.releaseSample()
        // Wait for both the in-flight and the queued sample to finish.
        let deadline = Date().addingTimeInterval(3)
        while (monitor.applications.isEmpty || monitor.isSampling) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertFalse(monitor.applications.isEmpty, "panel did not get an application sample")
        monitor.setPanelVisible(false)
        monitor.stop()
    }

    private func waitUntilIdle(_ monitor: SystemMonitor, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while monitor.isSampling && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
}

/// Test double whose `sample` blocks until released, so the caller controls when
/// an application sample completes.
final class GatedReader: AppMemoryReading {
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var gated = false
    private var trims = 0
    private var cached = false
    var trimCount: Int { lock.lock(); defer { lock.unlock() }; return trims }
    var hasCachedSample: Bool { lock.lock(); defer { lock.unlock() }; return cached }

    func runningApplications() -> [AppMemoryReader.AppDescriptor] {
        [AppMemoryReader.AppDescriptor(
            bundleIdentifier: "test.app",
            name: "TestApp",
            bundlePath: "/Applications/TestApp.app",
            rootPath: "/Applications/TestApp.app",
            icon: nil
        )]
    }

    func startGating() { lock.lock(); gated = true; lock.unlock() }
    func stopGating() { lock.lock(); gated = false; lock.unlock() }

    func sample(applications: [AppMemoryReader.AppDescriptor]) -> AppMemoryReader.SampleResult {
        lock.lock()
        let shouldBlock = gated
        lock.unlock()
        if shouldBlock {
            entered.signal()
            release.wait()
        }
        lock.lock()
        cached = true
        lock.unlock()
        let rows = applications.map {
            AppMemoryReader.AppUsage(id: $0.bundleIdentifier, name: $0.name, icon: nil, bytes: 42, processCount: 1, readableCount: 1, status: .ok)
        }
        return AppMemoryReader.SampleResult(rows: rows, state: .ready)
    }

    func waitUntilSampling(timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if entered.wait(timeout: .now() + 0.05) == .success { return true }
            // Pump the main run loop so a queued follow-up sample can start.
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return false
    }

    func releaseSample() { release.signal() }

    func purge() { lock.lock(); cached = false; lock.unlock() }

    func trimCache() { lock.lock(); trims += 1; cached = false; lock.unlock() }
}
