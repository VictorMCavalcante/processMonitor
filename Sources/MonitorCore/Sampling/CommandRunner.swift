import Foundation

public protocol CommandRunner: Sendable {
    func run(_ path: String, _ args: [String], timeout: TimeInterval) -> (status: Int32, output: String)?
}

public struct SystemCommandRunner: CommandRunner {
    public init() {}

    public func run(_ path: String, _ args: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let buffer = OutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in buffer.append(handle.availableData) }
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        buffer.append(pipe.fileHandleForReading.readDataToEndOfFile())
        return (process.terminationStatus, buffer.string)
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
