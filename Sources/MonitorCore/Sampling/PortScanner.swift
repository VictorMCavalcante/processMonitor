import Foundation

public enum PortScanner {
    public static func parse(lsofOutput: String) -> [Int32: [UInt16]] {
        var result: [Int32: Set<UInt16>] = [:]
        var current: Int32?
        for line in lsofOutput.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            if tag == "p" {
                current = Int32(value)
            } else if tag == "n", let pid = current, let colon = value.lastIndex(of: ":"), let port = UInt16(value[value.index(after: colon)...]) {
                result[pid, default: []].insert(port)
            }
        }
        return result.mapValues { $0.sorted() }
    }

    public static func scan() -> [Int32: [UInt16]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [:] }
        let deadline = DispatchTime.now() + 3
        DispatchQueue.global().asyncAfter(deadline: deadline) { if process.isRunning { process.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(lsofOutput: String(decoding: data, as: UTF8.self))
    }
}
