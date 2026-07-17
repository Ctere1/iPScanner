import Foundation

/// Runs a system binary and hands back what it wrote.
///
/// Two callers needed `/usr/sbin/arp` and `/sbin/ping`, and both had grown the same Process/Pipe
/// block — down to a copy of the same three-line comment explaining the deadlock below.
enum Subprocess {
    /// Runs `path` with `arguments` and returns its exit status and stdout.
    ///
    /// Returns nil if the binary could not be launched at all, which is distinct from a non-zero
    /// exit — a missing `/sbin/ping` is a broken system, an exit code of 2 is just an unreachable
    /// host.
    static func run(
        _ path: String,
        _ arguments: [String],
        qos: DispatchQoS.QoSClass = .userInitiated
    ) async -> (status: Int32, stdout: Data)? {
        await withCheckedContinuation { (continuation: CheckedContinuation<(Int32, Data)?, Never>) in
            DispatchQueue.global(qos: qos).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let stdout = Pipe()
                process.standardOutput = stdout
                // An attached-but-undrained pipe deadlocks the child once it fills the buffer:
                // stdout never closes, readDataToEndOfFile never returns, and the continuation is
                // never resumed. Nothing reads stderr, so discard it at the kernel instead.
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, data))
            }
        }
    }

    /// Convenience for the callers that only care about stdout as text.
    static func text(
        _ path: String,
        _ arguments: [String],
        qos: DispatchQoS.QoSClass = .userInitiated
    ) async -> (status: Int32, output: String)? {
        guard let (status, data) = await run(path, arguments, qos: qos) else { return nil }
        return (status, String(data: data, encoding: .utf8) ?? "")
    }
}
