import Darwin
import Foundation

public struct ProcessSampler: Sendable {
    private let timebase: (numer: UInt64, denom: UInt64)

    public init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebase = (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }

    public func sample() -> [ProcessSnapshot] {
        Self.allPids().compactMap { read($0) }
    }

    public func snapshot(pid: Int32) -> ProcessSnapshot? {
        read(pid)
    }

    static func allPids() -> [Int32] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).filter { $0 > 0 }
    }

    private func read(_ pid: Int32) -> ProcessSnapshot? {
        guard let base = Self.basics(pid) else { return nil }
        let args = Self.arguments(pid)
        var usage = rusage_info_v6()
        let rusageOK = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) == 0 }
        }
        let cpuAbs = rusageOK ? usage.ri_user_time + usage.ri_system_time : 0
        return ProcessSnapshot(
            id: pid,
            ppid: base.ppid,
            uid: base.uid,
            name: base.name,
            executablePath: Self.path(pid),
            arguments: args,
            cwd: Self.cwd(pid),
            startTime: base.start,
            state: base.state,
            footprintBytes: rusageOK ? usage.ri_phys_footprint : 0,
            cpuTimeNs: cpuAbs * timebase.numer / timebase.denom,
            ttyName: Self.ttyName(base.tdev),
            energyNj: rusageOK ? usage.ri_energy_nj : 0,
            wakeups: rusageOK ? usage.ri_interrupt_wkups + usage.ri_pkg_idle_wkups : 0
        )
    }

    private struct Basics {
        var ppid: Int32
        var uid: UInt32
        var name: String
        var start: Date
        var state: ProcessState
        var tdev: UInt32
    }

    private static func basics(_ pid: Int32) -> Basics? {
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size {
            return Basics(ppid: Int32(bsd.pbi_ppid), uid: bsd.pbi_uid, name: name(bsd),
                          start: Date(timeIntervalSince1970: Double(bsd.pbi_start_tvsec) + Double(bsd.pbi_start_tvusec) / 1_000_000),
                          state: state(Int32(bsd.pbi_status)), tdev: bsd.e_tdev)
        }
        var info = kinfo_proc()
        var length = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &length, nil, 0) == 0, length == MemoryLayout<kinfo_proc>.size, info.kp_proc.p_pid == pid else { return nil }
        let comm = withUnsafeBytes(of: &info.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let tv = info.kp_proc.p_starttime
        return Basics(ppid: info.kp_eproc.e_ppid, uid: info.kp_eproc.e_ucred.cr_uid, name: comm,
                      start: Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000),
                      state: state(Int32(info.kp_proc.p_stat)), tdev: UInt32(bitPattern: info.kp_eproc.e_tdev))
    }

    private static func state(_ status: Int32) -> ProcessState {
        switch status {
        case SRUN, SSLEEP, SIDL: .running
        case SSTOP: .stopped
        case SZOMB: .zombie
        default: .other
        }
    }

    private static func name(_ bsd: proc_bsdinfo) -> String {
        var b = bsd
        let full = withUnsafeBytes(of: &b.pbi_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        if !full.isEmpty { return full }
        return withUnsafeBytes(of: &b.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    private static func path(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func cwd(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let value = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return value.isEmpty ? nil : value
    }

    private static let ttyCache = TTYCache()

    static var ttyCacheCount: Int { ttyCache.count }

    static func ttyName(_ dev: UInt32) -> String? {
        guard dev != UInt32.max, dev != 0 else { return nil }
        return ttyCache.name(for: dev) {
            devname(dev_t(bitPattern: dev), mode_t(S_IFCHR)).map { String(cString: $0) }
        }
    }

    static func arguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var result: [String] = []
        while result.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            result.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return result
    }
}

private final class TTYCache: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [UInt32: String?] = [:]

    var count: Int { lock.withLock { names.count } }

    func name(for dev: UInt32, resolve: () -> String?) -> String? {
        if let cached = lock.withLock({ names[dev] }) { return cached }
        let value = resolve()
        lock.withLock { names[dev] = value }
        return value
    }
}
