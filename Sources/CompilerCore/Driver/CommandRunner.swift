import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum CommandRunnerError: Error, Sendable {
    case launchFailed(String)
    case nonZeroExit(CommandResult)
}

private enum CommandOutputStream {
    case stdout
    case stderr
}

private final class LockedCommandOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    func store(_ data: Data, for stream: CommandOutputStream) {
        lock.lock()
        switch stream {
        case .stdout:
            stdoutData = data
        case .stderr:
            stderrData = data
        }
        lock.unlock()
    }

    func data(for stream: CommandOutputStream) -> Data {
        lock.lock()
        defer { lock.unlock() }
        switch stream {
        case .stdout:
            return stdoutData
        case .stderr:
            return stderrData
        }
    }
}

public enum CommandRunner {
    /// Resolves the absolute path for an executable by searching the PATH environment variable.
    /// Falls back to the provided default path if the executable is not found in PATH.
    public static func resolveExecutable(_ name: String, fallback: String) -> String {
        let fileManager = FileManager.default
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for directory in pathEnv.split(separator: ":") {
                let candidate = String(directory) + "/" + name
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return fallback
    }

    /// Runs a command and records its wall-clock time as a sub-phase in the
    /// given `PhaseTimer`, if non-nil.  The `subPhaseName` label appears in
    /// the `time-phases` output.
    public static func run(
        executable: String,
        arguments: [String],
        currentDirectoryPath: String? = nil,
        phaseTimer: PhaseTimer? = nil,
        subPhaseName: String? = nil
    ) throws -> CommandResult {
        let startTime: UInt64 = (phaseTimer != nil && subPhaseName != nil) ? DispatchTime.now().uptimeNanoseconds : 0
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectoryPath {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.launchFailed("Failed to launch \(executable): \(error)")
        }
        // Drain both pipes before waiting for process termination to avoid
        // deadlocks when child output exceeds the kernel pipe buffer.
        let output = LockedCommandOutput()
        let drainGroup = DispatchGroup()

        drainGroup.enter()
        DispatchQueue.global().async {
            defer { drainGroup.leave() }
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            output.store(data, for: .stdout)
        }
        drainGroup.enter()
        DispatchQueue.global().async {
            defer { drainGroup.leave() }
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            output.store(data, for: .stderr)
        }
        drainGroup.wait()
        process.waitUntilExit()

        let stdoutData = output.data(for: .stdout)
        let stderrData = output.data(for: .stderr)

        let result = CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
        // Record subprocess wall-clock time when a timer is active.
        if let timer = phaseTimer, let label = subPhaseName {
            let endTime = DispatchTime.now().uptimeNanoseconds
            timer.recordSubPhase(label, startTime: startTime, endTime: endTime)
        }

        if result.exitCode != 0 {
            throw CommandRunnerError.nonZeroExit(result)
        }
        return result
    }
}
