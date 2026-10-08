import MachO
import Network
import Observation
import UIKit

struct BootLine: Identifiable {
    enum Kind {
        case plain, dim, info, warn, good, strong
    }

    let id: Int
    let text: String
    let kind: Kind
}

@MainActor
@Observable
final class BootLog {
    static let shared = BootLog()
    nonisolated static let origin = ProcessInfo.processInfo.systemUptime
    nonisolated(unsafe) static var recording = true

    private(set) var lines: [BootLine] = []
    @ObservationIgnored private var nextID = 0

    nonisolated static func elapsed() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime - origin
    }

    nonisolated static func post(_ tag: String, _ message: String) {
        guard recording else { return }
        let time = elapsed()
        Task { @MainActor in shared.append(time: time, tag: tag, message: message) }
    }

    func note(_ tag: String, _ message: String) {
        append(time: Self.elapsed(), tag: tag, message: message)
    }

    func append(time: TimeInterval, tag: String, message: String) {
        let stamp = String(format: "[%11.6f]", time)
        let kind: BootLine.Kind
        switch tag {
        case "dyld", "env": kind = .dim
        case "http", "net": kind = .info
        case "auth": kind = .warn
        case "library", "home", "player", "cache", "settings": kind = .good
        case "boot": kind = .strong
        default: kind = .plain
        }
        lines.append(BootLine(id: nextID, text: "\(stamp) \(tag): \(message)", kind: kind))
        nextID += 1
        if lines.count > 2500 { lines.removeFirst(500) }
    }

    func finish() {
        let total = Self.elapsed()
        append(time: total, tag: "boot", message: String(format: "complete in %.2f s", total))
        Self.recording = false
    }
}

enum SystemBoot {
    @MainActor
    static func record() {
        let log = BootLog.shared
        func add(_ tag: String, _ message: String) {
            log.append(time: BootLog.elapsed(), tag: tag, message: message)
        }

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        add("boot", "Swiftify \(version) (\(build)) verbose boot")
        add("boot", "pid \(ProcessInfo.processInfo.processIdentifier) \(ProcessInfo.processInfo.processName)")

        var name = utsname()
        uname(&name)
        func field<T>(_ value: T) -> String {
            withUnsafeBytes(of: value) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        }
        add("kernel", field(name.version))
        add("kernel", "\(field(name.sysname)) \(field(name.release)) \(field(name.machine))")
        if let build = sysctlString("kern.osversion") { add("kernel", "osversion \(build)") }
        if let model = sysctlString("hw.model") { add("hw", "model \(model)") }
        if let machine = sysctlString("hw.machine") { add("hw", "machine \(machine)") }
        add("hw", "cpu \(ProcessInfo.processInfo.processorCount) cores, \(ProcessInfo.processInfo.activeProcessorCount) active")
        let memory = ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)
        add("hw", "memory \(memory)")
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        if sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 {
            add("kernel", "boottime \(Date(timeIntervalSince1970: TimeInterval(boot.tv_sec)).formatted(date: .abbreviated, time: .standard))")
        }
        add("kernel", String(format: "uptime %.1f s", ProcessInfo.processInfo.systemUptime))

        let device = UIDevice.current
        add("ios", "\(device.systemName) \(device.systemVersion) \(device.model)")
        device.isBatteryMonitoringEnabled = true
        if device.batteryLevel >= 0 {
            let state: String
            switch device.batteryState {
            case .charging: state = "charging"
            case .full: state = "full"
            case .unplugged: state = "unplugged"
            default: state = "unknown"
            }
            add("power", "battery \(Int(device.batteryLevel * 100))% \(state)")
        }
        add("power", "low power mode \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")")
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        add("thermal", thermal)

        let screen = UIScreen.main
        add("display", "\(Int(screen.bounds.width))x\(Int(screen.bounds.height)) @\(Int(screen.scale))x, \(screen.maximumFramesPerSecond) Hz max")
        add("locale", "\(Locale.current.identifier) \(TimeZone.current.identifier) \(Locale.current.calendar.identifier)")

        let keys: [URLResourceKey] = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        if let values = try? URL.documentsDirectory.resourceValues(forKeys: Set(keys)),
           let free = values.volumeAvailableCapacityForImportantUsage, let total = values.volumeTotalCapacity {
            let freeText = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            let totalText = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
            add("disk", "\(freeText) available of \(totalText)")
        }
        add("fs", "bundle \(Bundle.main.bundlePath)")
        add("fs", "caches \(URL.cachesDirectory.path())")
        add("env", "\(ProcessInfo.processInfo.environment.count) variables, \(ProcessInfo.processInfo.arguments.count) arguments")

        let count = _dyld_image_count()
        add("dyld", "\(count) images loaded")
        for index in 0..<count {
            if let path = _dyld_get_image_name(index) {
                add("dyld", String(format: "[%3d/%d] ", index + 1, count) + String(cString: path))
            }
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            var interfaces: [String] = []
            if path.usesInterfaceType(.wifi) { interfaces.append("wifi") }
            if path.usesInterfaceType(.cellular) { interfaces.append("cellular") }
            if path.usesInterfaceType(.wiredEthernet) { interfaces.append("ethernet") }
            let status = path.status == .satisfied ? "satisfied" : "unsatisfied"
            BootLog.post("net", "path \(status) via \(interfaces.isEmpty ? "none" : interfaces.joined(separator: ",")) expensive=\(path.isExpensive) constrained=\(path.isConstrained)")
            monitor.cancel()
        }
        monitor.start(queue: DispatchQueue(label: "swiftify.bootlog.net"))
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
