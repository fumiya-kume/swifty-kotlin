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
        let stdout = Pipe(), stderr = Pipe()
        let stdoutAccumulator = DataAccumulator()
        let stderrAccumulator = DataAccumulator()
        let stdoutGroup = DispatchGroup()
        let stderrGroup = DispatchGroup()

        process.executableURL = try workerExecutableURL()
        process.arguments = [suiteName, sourcePath]
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = stdout
        process.standardError = stderr

        drain(pipe: stdout, into: stdoutAccumulator, group: stdoutGroup)
        drain(pipe: stderr, into: stderrAccumulator, group: stderrGroup)

        try process.run()
        process.waitUntilExit()

        stdoutGroup.wait()
        stderrGroup.wait()

        let stdoutData = stdoutAccumulator.snapshot()
        let stderrData = stderrAccumulator.snapshot()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        
        // Check common build directories with platform-specific paths
        var candidates: [URL] = []
        
        #if os(Linux)
        candidates.append(contentsOf: [
            cwd.appendingPathComponent(".build/debug/\(workerName)"),
            cwd.appendingPathComponent(".build/x86_64-unknown-linux-gnu/debug/\(workerName)"),
            cwd.appendingPathComponent(".build/aarch64-unknown-linux-gnu/debug/\(workerName)")
        ])
        #else
        candidates.append(contentsOf: [
            cwd.appendingPathComponent(".build/debug/\(workerName)"),
            cwd.appendingPathComponent(".build/arm64-apple-macosx/debug/\(workerName)"),
            cwd.appendingPathComponent(".build/x86_64-apple-macosx/debug/\(workerName)")
        ])
        #endif
        
        // Add the directory of the current executable as fallback
        if let currentExecutable = Bundle.main.executablePath {
            candidates.append(URL(fileURLWithPath: currentExecutable).deletingLastPathComponent().appendingPathComponent(workerName))
        }

        for candidate in candidates {
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
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

        // Provide detailed error information for debugging
        let searchedPaths = candidates.map { $0.path }.joined(separator: ", ")
        throw GoldenHarnessAPIError.workerExecutableNotFound("\(workerName) (searched: \(searchedPaths))")
    }

    private static func drain(
        pipe: Pipe,
        into accumulator: DataAccumulator,
        group: DispatchGroup
    ) {
        let handle = pipe.fileHandleForReading
        group.enter()
        handle.readabilityHandler = { readableHandle in
            let data = readableHandle.availableData
            if data.isEmpty {
                readableHandle.readabilityHandler = nil
                group.leave()
                return
            }
            accumulator.append(data)
        }
    }
}

private final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
