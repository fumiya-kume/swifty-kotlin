import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum CommandRunnerError: Error, Sendable {
    case launchFailed(String)
    case nonZeroExit(CommandResult)
    case timedOut(String)
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
    private static let defaultTimeoutSeconds: TimeInterval = 120
    private static let drainTimeoutSeconds: TimeInterval = 20
    private static let terminationGracePeriodSeconds: TimeInterval = 1

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
        subPhaseName: String? = nil,
        timeout: TimeInterval = 120
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
        let exitGroup = DispatchGroup()

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

        exitGroup.enter()
        DispatchQueue.global().async {
            defer { exitGroup.leave() }
            process.waitUntilExit()
        }

        var didExit = wait(for: exitGroup, timeout: timeout)
        let didTimeOut = !didExit
        if !didExit {
            process.terminate()
            didExit = wait(for: exitGroup, timeout: terminationGracePeriodSeconds)
            if !didExit {
                kill(process.processIdentifier, SIGKILL)
                didExit = wait(for: exitGroup, timeout: terminationGracePeriodSeconds)
                // Verify process exited after SIGKILL
                if !didExit && process.isRunning {
                    // Process is still running despite SIGKILL - this is unusual but possible
                    // Log warning and continue - process should be dead by now
                    // (We don't have a logging mechanism here, but the drain operations may fail)
                }
            }
        }

        let didDrain = wait(for: drainGroup, timeout: drainTimeoutSeconds)

        let stdoutData = output.data(for: .stdout)
        let stderrData = output.data(for: .stderr)

        // Check timeout conditions, but prioritize actual exit status over drain failures
        if !didExit {
            // Process didn't exit at all - this is a timeout
            let stdout = String(decoding: stdoutData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw CommandRunnerError.timedOut(timeoutMessage(
                executable: executable,
                arguments: arguments,
                timeout: timeout,
                stdout: stdout,
                stderr: stderr,
                didExit: didExit,
                didDrain: didDrain
            ))
        }

        let result = CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )

        // If process exited but drain failed, check exit status
        if !didDrain {
            if result.exitCode == 0 {
                // Process succeeded but drain failed - report as timeout
                throw CommandRunnerError.timedOut(timeoutMessage(
                    executable: executable,
                    arguments: arguments,
                    timeout: timeout,
                    stdout: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                    stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                    didExit: didExit,
                    didDrain: didDrain
                ))
            }
            // Process failed with non-zero exit code - fall through to throw nonZeroExit below
        }
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

    private static func wait(for group: DispatchGroup, timeout: TimeInterval) -> Bool {
        let milliseconds = max(1, Int((timeout * 1000).rounded()))
        return group.wait(timeout: .now() + .milliseconds(milliseconds)) == .success
    }

    private static func timeoutMessage(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        stdout: String,
        stderr: String,
        didExit: Bool,
        didDrain: Bool
    ) -> String {
        let command = ([executable] + arguments).joined(separator: " ")
        let phase: String
        if !didExit {
            phase = "waiting for process exit"
        } else if !didDrain {
            phase = "draining process output"
        } else {
            phase = "running command"
        }
        let stdoutSuffix = stdout.isEmpty ? "" : "\nSTDOUT: \(stdout)"
        let stderrSuffix = stderr.isEmpty ? "" : "\nSTDERR: \(stderr)"
        return "Timed out after \(timeout)s while \(phase): \(command)\(stdoutSuffix)\(stderrSuffix)"
    }
}
