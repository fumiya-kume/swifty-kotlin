@testable import CompilerCore
import Foundation

public struct GoldenHarnessCase: Sendable {
    public let sourcePath: String
    public let basename: String
}

enum GoldenHarnessAPIError: Error, CustomStringConvertible {
    case unknownSuite(String)
    case workerExecutableNotFound(String)
    case workerFailed(Int32, String)

    var description: String {
        switch self {
        case let .unknownSuite(name):
            return "Unknown golden suite: \(name)"
        case let .workerExecutableNotFound(name):
            return "Golden worker executable not found: \(name)"
        case let .workerFailed(status, details):
            let suffix = details.isEmpty ? "" : "\n\(details)"
            return "Golden worker failed with exit status \(status)\(suffix)"
        }
    }
}

public enum GoldenHarness {
    public static func loadCasesOrCrash(suiteName: String) -> [GoldenHarnessCase] {
        do {
            return try GoldenHarnessCaseDiscovery.loadCases(suite: try suite(named: suiteName)).map {
                GoldenHarnessCase(sourcePath: $0.sourcePath, basename: $0.basename)
            }
        } catch {
            preconditionFailure("GoldenHarness case discovery failed for \(suiteName): \(error)")
        }
    }

    public static func render(suiteName: String, sourcePath: String) throws -> String {
        switch try suite(named: suiteName) {
        case .lexer:
            try GoldenHarnessDump.dumpLexer(sourcePath: sourcePath)
        case .parser:
            try GoldenHarnessDump.dumpParser(sourcePath: sourcePath)
        case .sema:
            try GoldenHarnessDump.dumpSema(sourcePath: sourcePath)
        case .diagnostics:
            try GoldenHarnessDump.dumpDiagnostics(sourcePath: sourcePath)
        }
    }

    public static func renderInSubprocess(suiteName: String, sourcePath: String) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let group = DispatchGroup()
        let stdoutHandle = stdout.fileHandleForReading
        let stderrHandle = stderr.fileHandleForReading
        var stdoutData = Data()
        var stderrData = Data()

        process.executableURL = try workerExecutableURL()
        process.arguments = [suiteName, sourcePath]
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = stdout
        process.standardError = stderr

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            stdoutData = stdoutHandle.readDataToEndOfFile()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            stderrData = stderrHandle.readDataToEndOfFile()
        }

        try process.run()
        process.waitUntilExit()
        group.wait()
        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw GoldenHarnessAPIError.workerFailed(process.terminationStatus, stderrText)
        }
        return String(decoding: stdoutData, as: UTF8.self)
    }

    @discardableResult
    public static func persistIfUpdating(sourcePath: String, actual: String) throws -> Bool {
        try GoldenHarnessGoldenFileIO.persistIfUpdating(caseFile: caseFile(sourcePath: sourcePath), actual: actual)
    }

    public static func loadExpectedGolden(sourcePath: String) throws -> String {
        try GoldenHarnessGoldenFileIO.loadExpectedGolden(caseFile: caseFile(sourcePath: sourcePath))
    }

    private static func suite(named suiteName: String) throws -> GoldenHarnessGoldenSuite {
        switch suiteName {
        case "Lexer":
            .lexer
        case "Parser":
            .parser
        case "Sema":
            .sema
        case "Diagnostics":
            .diagnostics
        default:
            throw GoldenHarnessAPIError.unknownSuite(suiteName)
        }
    }

    private static func caseFile(sourcePath: String) -> GoldenHarnessCaseFile {
        GoldenHarnessCaseFile(sourceURL: URL(fileURLWithPath: sourcePath))
    }

    private static func workerExecutableURL() throws -> URL {
        let fileManager = FileManager.default
        let workerName = "GoldenHarnessWorker"

        // Check environment override first
        if let overridePath = ProcessInfo.processInfo.environment["GOLDEN_HARNESS_WORKER"],
           fileManager.isExecutableFile(atPath: overridePath) {
            return URL(fileURLWithPath: overridePath)
        }

        // Check common build directories
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent(".build/debug/\(workerName)"),
            cwd.appendingPathComponent(".build/arm64-apple-macosx/debug/\(workerName)"),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent(workerName)
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        // Search in .build directory as last resort
        let buildRoot = cwd.appendingPathComponent(".build")
        if let enumerator = fileManager.enumerator(
            at: buildRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let candidate as URL in enumerator {
                if candidate.lastPathComponent == workerName,
                   fileManager.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        throw GoldenHarnessAPIError.workerExecutableNotFound(workerName)
    }
}
