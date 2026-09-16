import AppKit
import Darwin
import Foundation
import Observation

/// Owns the single 3 s monitoring schedule, the raw Mach/libproc reads and the
/// current whole-machine snapshot. Menu bar, rings, capacity text and the
/// composition bar all read the same snapshot published here.
@MainActor
@Observable
final class SystemMonitor {

    // MARK: - Snapshot types

    struct CPUSnapshot {
        /// Whole-machine CPU usage, 0–100, normalised across all cores.
        /// `nil` means "no valid sample yet" (first sample / after wake).
        var usage: Double?
    }

    /// Whole-machine memory in raw bytes. `used` matches Activity Monitor's
    /// "Memory Used" (see docs/validation/METRICS.md for the verified mapping).
    struct MemorySnapshot {
        var total: UInt64
        var used: UInt64

        var usedPercent: Double? { total > 0 ? Double(used) / Double(total) * 100 : nil }
    }

    struct DiskSnapshot {
        var volumePath: String
        var volumeIdentifier: String?
        var total: UInt64
        var available: UInt64
        var used: UInt64
        var usedPercent: Double? { total > 0 ? Double(used) / Double(total) * 100 : nil }
    }

    struct DeviceSnapshot {
        var chip: String
        var osVersion: String
    }

    struct Snapshot {
        var cpu = CPUSnapshot()
        var memory: MemorySnapshot?
        var disk: DiskSnapshot?
        var device = DeviceSnapshot(chip: "未知", osVersion: "未知")
        var timestamp = Date.distantPast

        var isValid: Bool { memory != nil || cpu.usage != nil }
    }

    enum ApplicationState: Equatable {
        case idle
        case loading
        case ready
        case unavailable(String)
    }

    // MARK: - Published state

    private(set) var snapshot = Snapshot()
    private(set) var applications: [AppMemoryReader.AppUsage] = []
    private(set) var applicationState: ApplicationState = .idle

    // MARK: - Control

    private(set) var isRunning = false
    private var panelVisible = false
    private var timer: Timer?
    private(set) var isSampling = false
    private var pendingImmediate = false
    private var nextDiskRead = DispatchTime.now()
    private var previousTicks: CPUTicks?
    /// Bumped whenever the sampling lifecycle changes so results from a stale
    /// in-flight sample can be discarded instead of written back.
    private var generation = 0

    nonisolated(unsafe) private let reader: any AppMemoryReading
    private let sampleQueue = DispatchQueue(label: "com.calmon.monitoring.sample", qos: .utility)

    init(reader: any AppMemoryReading = AppMemoryReader()) {
        self.reader = reader
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation &+= 1
        previousTicks = nil
        snapshot.cpu.usage = nil
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation &+= 1
        pendingImmediate = false
        timer?.invalidate()
        timer = nil
        previousTicks = nil
        snapshot.cpu.usage = nil
        snapshot.disk = nil
        applications = []
        applicationState = .idle
        panelVisible = false
        reader.purge()
    }

    /// Called by the menu bar controller when the monitoring popover opens/closes.
    func setPanelVisible(_ visible: Bool) {
        guard panelVisible != visible else { return }
        panelVisible = visible
        generation &+= 1
        if visible {
            nextDiskRead = .now()
            applicationState = applications.isEmpty ? .loading : .ready
            tick(force: true)
        } else {
            applications = []
            applicationState = .idle
            reader.trimCache()
        }
    }

    /// Sleep/wake: rebuild the CPU baseline so the next sample is a fresh interval.
    func handleWake() {
        generation &+= 1
        previousTicks = nil
        snapshot.cpu.usage = nil
        nextDiskRead = .now()
        if isRunning { tick(force: true) }
    }

    // MARK: - Scheduling

    private func tick(force: Bool = false) {
        guard isRunning else { return }
        if isSampling {
            // A forced tick (panel opened) is queued so the panel still samples
            // immediately once the in-flight sample finishes.
            if force { pendingImmediate = true }
            return
        }
        isSampling = true

        let wantApps = panelVisible
        let now = DispatchTime.now()
        let doDisk = panelVisible && (force || now >= nextDiskRead)
        if doDisk { nextDiskRead = now + 30_000_000_000 }

        let priorTicks = previousTicks
        let runningApps = wantApps ? AppMemoryReader.runningApplications() : []
        let taskGeneration = generation

        sampleQueue.async { [weak self] in
            guard let self else { return }
            let ticks = Self.readCPUTicks()
            let vm = Self.readVMStatistics()
            var disk: DiskSnapshot?
            if doDisk { disk = Self.readDisk() }
            var apps: [AppMemoryReader.AppUsage] = []
            var appState: ApplicationState = .idle
            if wantApps {
                let result = self.reader.sample(applications: runningApps)
                apps = result.rows
                appState = result.state
            }
            Task { @MainActor in
                self.isSampling = false
                let stale = !self.isRunning || taskGeneration != self.generation
                if stale {
                    // Discard the result (and any icon cache the stale sample
                    // refilled) so a closed panel cannot be repopulated.
                    if wantApps { self.reader.trimCache() }
                } else {
                    self.apply(ticks: ticks, prior: priorTicks, vm: vm, disk: disk, diskAttempted: doDisk, apps: apps, appState: appState, wantApps: wantApps)
                }
                if self.pendingImmediate, self.isRunning {
                    self.pendingImmediate = false
                    self.tick()
                }
            }
        }
    }

    private func apply(ticks: CPUTicks?, prior: CPUTicks?, vm: VMRaw?, disk: DiskSnapshot?, diskAttempted: Bool, apps: [AppMemoryReader.AppUsage], appState: ApplicationState, wantApps: Bool) {
        var newSnapshot = snapshot

        if let ticks {
            // A nil usage (zero delta / counter reset) clears the old value so it
            // is not shown as fresh; the next valid interval restores it.
            newSnapshot.cpu.usage = Self.cpuUsage(current: ticks, previous: prior)
            previousTicks = ticks
        } else {
            previousTicks = nil
            newSnapshot.cpu.usage = nil
        }

        if let vm, let memory = Self.memorySnapshot(vm: vm) {
            newSnapshot.memory = memory
        } else {
            newSnapshot.memory = nil
        }

        // Distinguish "not scheduled this tick" from "asked and failed": only an
        // attempted read may clear the previous disk value to `--`.
        if diskAttempted {
            newSnapshot.disk = disk
        }
        if newSnapshot.device.chip == "未知" {
            newSnapshot.device = Self.deviceSnapshot()
        }
        newSnapshot.timestamp = Date()
        snapshot = newSnapshot

        if wantApps {
            applications = apps
            applicationState = appState
        }
    }

    // MARK: - CPU

    struct CPUTicks: Equatable {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64
    }

    nonisolated static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    /// Verified in docs/validation/METRICS.md: handles counter width (32-bit
    /// Mach ticks), zero deltas and unreadable counters without fabricating 0%.
    nonisolated static func cpuUsage(current: CPUTicks, previous: CPUTicks?) -> Double? {
        guard let previous else { return nil }
        let mask = UInt64(UInt32.max)
        func delta(_ now: UInt64, _ prev: UInt64) -> UInt64 {
            (now & mask) >= (prev & mask) ? (now & mask) - (prev & mask) : (mask - (prev & mask)) + (now & mask) + 1
        }
        let dUser = delta(current.user, previous.user)
        let dSystem = delta(current.system, previous.system)
        let dIdle = delta(current.idle, previous.idle)
        let dNice = delta(current.nice, previous.nice)
        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return nil }
        let busy = total - min(dIdle, total)
        return Double(busy) / Double(total) * 100
    }

    // MARK: - Memory

    struct VMRaw {
        var pageSize: UInt64
        var physical: UInt64
        var free: UInt64
        var active: UInt64
        var inactive: UInt64
        var wired: UInt64
        var purgeable: UInt64
        var speculative: UInt64
        var compressor: UInt64
        var external: UInt64
        var internalPages: UInt64
    }

    nonisolated static func readVMStatistics() -> VMRaw? {
        let host = mach_host_self()
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var physical: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &physical, &size, nil, 0) == 0, physical > 0 else { return nil }
        let p = UInt64(pageSize)
        func bytes(_ n: natural_t) -> UInt64 { UInt64(n) * p }
        return VMRaw(
            pageSize: p,
            physical: physical,
            free: bytes(stats.free_count),
            active: bytes(stats.active_count),
            inactive: bytes(stats.inactive_count),
            wired: bytes(stats.wire_count),
            purgeable: bytes(stats.purgeable_count),
            speculative: bytes(stats.speculative_count),
            compressor: bytes(stats.compressor_page_count),
            external: bytes(stats.external_page_count),
            internalPages: bytes(stats.internal_page_count)
        )
    }

    /// Memory Used = physical − (free − speculative) − file-backed pages.
    ///
    /// Verified against Activity Monitor on macOS 27 with a synchronized
    /// `vm_statistics64` dump (docs/validation/METRICS.md): speculative pages are
    /// treated as used, so the effective free term is `free_count − speculative_count`.
    ///
    /// Contradictory samples (a component larger than physical, or component sum
    /// exceeding physical) are rejected as invalid instead of being clamped into
    /// an impossible composition bar.
    nonisolated static func memorySnapshot(vm: VMRaw) -> MemorySnapshot? {
        guard vm.physical > 0,
              vm.free <= vm.physical,
              vm.speculative <= vm.free,
              vm.internalPages <= vm.physical,
              vm.purgeable <= vm.internalPages else { return nil }

        let app = vm.internalPages - vm.purgeable
        let wired = vm.wired
        let compressed = vm.compressor
        guard app <= vm.physical, wired <= vm.physical, compressed <= vm.physical else { return nil }
        // Subtract before adding to validate bounds without integer overflow.
        guard wired <= vm.physical - app,
              compressed <= vm.physical - app - wired else { return nil }
        let componentSum = app + wired + compressed

        let effectiveFree = vm.free - vm.speculative
        guard vm.external <= vm.physical - effectiveFree else { return nil }
        let used = vm.physical - effectiveFree - vm.external
        // Component bounds are still validated (invalid samples return nil); the
        // measurement itself is never adjusted to make a composition add up.
        guard componentSum <= used else { return nil }
        return MemorySnapshot(total: vm.physical, used: used)
    }

    // MARK: - Disk

    nonisolated static func readDisk() -> DiskSnapshot? {
        let url = FileManager.default.homeDirectoryForCurrentUser
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeURLKey,
            .volumeIdentifierKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacity,
              available >= 0, available <= total
        else { return nil }
        let volumeURL = values.volume ?? url
        return DiskSnapshot(
            volumePath: volumeURL.path,
            volumeIdentifier: values.volumeIdentifier.map { String(describing: $0) },
            total: UInt64(total),
            available: UInt64(available),
            used: UInt64(total - available)
        )
    }

    // MARK: - Device

    nonisolated static func deviceSnapshot() -> DeviceSnapshot {
        DeviceSnapshot(chip: chipName(), osVersion: osVersionString())
    }

    nonisolated static func chipName() -> String {
        if let brand = sysctlString("machdep.cpu.brand_string"), !brand.isEmpty {
            return brand
        }
        if let model = sysctlString("hw.model"), !model.isEmpty {
            return model
        }
        return "未知"
    }

    nonisolated static func osVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let base = "macOS \(version.majorVersion).\(version.minorVersion)"
        if let build = sysctlString("kern.osversion") {
            return "\(base) (\(build))"
        }
        return base
    }

    nonisolated static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
