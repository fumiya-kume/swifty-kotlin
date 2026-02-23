import Foundation

public struct CommandResult {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum CommandRunnerError: Error {
    case launchFailed(String)
    case nonZeroExit(CommandResult)
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
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
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
