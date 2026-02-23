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
    public static func run(
        executable: String,
        arguments: [String],
        currentDirectoryPath: String? = nil
    ) throws -> CommandResult {
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
        if result.exitCode != 0 {
            throw CommandRunnerError.nonZeroExit(result)
        }
        return result
    }
}
