import AppKit
import Darwin
import Foundation

/// Abstraction over the process sampler so `SystemMonitor` can be unit-tested
/// with a gated double that controls exactly when a sample completes.
protocol AppMemoryReading: AnyObject {
    func runningApplications() -> [AppMemoryReader.AppDescriptor]
    func sample(applications: [AppMemoryReader.AppDescriptor]) -> AppMemoryReader.SampleResult
    func purge()
    func trimCache()
}

/// Enumerates the application processes, reads resource usage with the public
/// libproc API and attributes each PID to its owning application.
///
/// It has no timer of its own: `SystemMonitor` calls `sample` on the shared
/// 3 s schedule only while the monitoring popover is visible.
final class AppMemoryReader: AppMemoryReading {

    struct AppDescriptor {
        let bundleIdentifier: String
        let name: String
        let bundlePath: String
        /// Top-level `.app` bundle that owns this bundle. A nested helper shares
        /// the main app's root, so helpers aggregate into the main software row.
        let rootPath: String
        let icon: NSImage?
    }

    struct AppUsage: Identifiable {
        enum Status {
            case ok
            case partial   // some processes in the group could not be read
            case unreadable
        }

        let id: String
        let name: String
        let icon: NSImage?
        let bytes: UInt64?
        let processCount: Int
        let readableCount: Int
        let status: Status
    }

    struct SampleResult {
        var rows: [AppUsage]
        var state: SystemMonitor.ApplicationState
    }

    private var iconCache: [String: NSImage] = [:]
    private let cacheLock = NSLock()

    // MARK: - Application discovery (main thread)

    /// Running graphical / accessory applications with a bundle identity, reduced
    /// to one descriptor per top-level software bundle. A nested helper (for
    /// example “Lark Helper” inside “飞书”) shares its root with the main app and
    /// is folded into it rather than shown as a separate row.
    nonisolated func runningApplications() -> [AppDescriptor] {
        let running = NSWorkspace.shared.runningApplications
        var byRoot: [String: AppDescriptor] = [:]
        var order: [String] = []
        for app in running {
            let policy = app.activationPolicy
            guard policy == .regular || policy == .accessory else { continue }
            guard let bundleURL = app.bundleURL else { continue }
            let path = bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
            let root = Self.rootBundle(path)
            let identifier = app.bundleIdentifier ?? path
            let name = app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent
            let candidate = AppDescriptor(
                bundleIdentifier: identifier,
                name: name,
                bundlePath: path,
                rootPath: root,
                icon: cachedIcon(for: app, root: root)
            )
            if let existing = byRoot[root] {
                // Prefer the top-level bundle over a nested helper.
                if existing.bundlePath != root, path == root {
                    byRoot[root] = candidate
                }
            } else {
                byRoot[root] = candidate
                order.append(root)
            }
        }
        return order.compactMap { byRoot[$0] }
    }

    /// Filters aggregated app rows by display name only (continuous,
    /// case-insensitive substring). No pinyin, process name, bundle ID or PID.
    /// A blank query returns the input unchanged.
    nonisolated static func filter(_ apps: [AppUsage], query: String) -> [AppUsage] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return apps }
        return apps.filter { $0.name.range(of: needle, options: .caseInsensitive) != nil }
    }

    /// Returns the outermost `.app` bundle in a path (the software boundary).
    /// If no `.app` component exists, the whole path is returned.
    nonisolated static func rootBundle(_ path: String) -> String {
        var result = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            result += "/" + component
            if component.hasSuffix(".app") { return result }
        }
        return path
    }

    // MARK: - Sampling (background)

    func sample(applications: [AppDescriptor]) -> SampleResult {
        guard !applications.isEmpty else {
            return SampleResult(rows: [], state: .unavailable("未发现可读取的应用"))
        }

        // Shortest root first so a PID inside a nested helper attributes to the
        // outermost (main) software bundle rather than creating a helper row.
        let ordered = applications
            .enumerated()
            .sorted { $0.element.rootPath.count < $1.element.rootPath.count }

        var totals = [UInt64](repeating: 0, count: applications.count)
        var readable = [Int](repeating: 0, count: applications.count)
        var counts = [Int](repeating: 0, count: applications.count)
        var anyReadable = false

        let pids = Self.allPIDs()
        for pid in pids {
            guard pid > 0 else { continue }
            guard let path = Self.executablePath(for: pid) else { continue }
            guard let appIndex = Self.ownerIndex(for: path, ordered: ordered) else { continue }
            counts[appIndex] += 1
            if let footprint = Self.footprint(for: pid) {
                totals[appIndex] += footprint
                readable[appIndex] += 1
                anyReadable = true
            }
        }

        var rows: [AppUsage] = []
        for (i, app) in applications.enumerated() {
            let count = counts[i]
            let read = readable[i]
            if count == 0 {
                // No attributable process right now (for example an app that is
                // terminating). Keep the row so the list does not jump around.
                rows.append(AppUsage(id: app.rootPath, name: app.name, icon: app.icon, bytes: nil, processCount: 0, readableCount: 0, status: .unreadable))
                continue
            }
            let status: AppUsage.Status = read == 0 ? .unreadable : (read < count ? .partial : .ok)
            let bytes: UInt64? = read == 0 ? nil : totals[i]
            rows.append(AppUsage(id: app.rootPath, name: app.name, icon: app.icon, bytes: bytes, processCount: count, readableCount: read, status: status))
        }

        guard anyReadable else {
            return SampleResult(rows: rows, state: .unavailable("无法读取进程资源，请检查系统权限"))
        }

        rows.sort { lhs, rhs in
            let l = lhs.bytes ?? 0
            let r = rhs.bytes ?? 0
            if l != r { return l > r }
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.id < rhs.id
        }
        return SampleResult(rows: rows, state: .ready)
    }

    // MARK: - Cache

    func purge() {
        cacheLock.lock()
        iconCache.removeAll()
        cacheLock.unlock()
    }

    /// Called when the panel closes: drop the temporary sampling buffer.
    func trimCache() {
        purge()
    }

    /// Returns the cached downsampled icon, decoding it only on the first sight
    /// of a software bundle so repeated samples do not re-fetch every app icon.
    private func cachedIcon(for app: NSRunningApplication, root: String) -> NSImage? {
        cacheLock.lock()
        if let cached = iconCache[root] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        guard let source = app.icon else { return nil }
        let resized = Self.downsampled(source, pointSize: 20) ?? source
        cacheLock.lock()
        iconCache[root] = resized
        cacheLock.unlock()
        return resized
    }

    // MARK: - libproc helpers

    /// `proc_listallpids` already converts the byte count to a PID count inside
    /// libproc (`__proc_listpids(...) / sizeof(int)`), so its return value is a
    /// number of PIDs, not bytes. Do not divide it a second time. If the buffer
    /// is exactly filled it may be too small, so grow and retry.
    nonisolated static func allPIDs() -> [pid_t] {
        var capacity = 8192
        let maxCapacity = 262_144
        while true {
            var pids = [pid_t](repeating: 0, count: capacity)
            let count = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
            guard count > 0 else { return [] }
            let n = Int(count)
            if n < capacity || capacity >= maxCapacity {
                return Array(pids.prefix(min(n, capacity)))
            }
            capacity *= 2
        }
    }

    nonisolated static func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 2)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    nonisolated static func footprint(for pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { pointer in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, pointer)
            }
        }
        guard result == 0 else { return nil }
        return info.ri_phys_footprint
    }

    /// Picks the outermost software bundle that owns `path`. Helpers nested under
    /// a main app share its root, so they aggregate into the main row instead of
    /// appearing separately.
    nonisolated static func ownerIndex(for path: String, ordered: [(offset: Int, element: AppDescriptor)]) -> Int? {
        for entry in ordered {
            let root = entry.element.rootPath
            if path == root || path.hasPrefix(root + "/") {
                return entry.offset
            }
        }
        return nil
    }

    nonisolated static func downsampled(_ image: NSImage, pointSize: CGFloat) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelSize = Int((pointSize * scale).rounded())
        guard pixelSize > 0 else { return nil }
        var rect = NSRect(x: 0, y: 0, width: pointSize, height: pointSize)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        guard let scaled = context.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: NSSize(width: pointSize, height: pointSize))
    }
}
