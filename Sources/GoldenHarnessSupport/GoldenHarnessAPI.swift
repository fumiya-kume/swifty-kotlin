@testable import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct GoldenHarnessCase: Sendable {
    public let sourcePath: String
    public let basename: String
}

enum GoldenHarnessAPIError: Error, CustomStringConvertible {
    case unknownSuite(String)
    case workerExecutableNotFound(String)
    case workerFailed(Int32, String)
    case workerTimedOut(String)

    var description: String {
        switch self {
        case let .unknownSuite(name):
            return "Unknown golden suite: \(name)"
        case let .workerExecutableNotFound(name):
            return "Golden worker executable not found: \(name)"
        case let .workerFailed(status, details):
            let suffix = details.isEmpty ? "" : "\n\(details)"
            return "Golden worker failed with exit status \(status)\(suffix)"
        case let .workerTimedOut(details):
            let suffix = details.isEmpty ? "" : "\n\(details)"
            return "Golden worker timed out\(suffix)"
        }
    }
}

public enum GoldenHarness {
    private static let subprocessTimeout: TimeInterval = 30
    private static let terminationGracePeriodSeconds: TimeInterval = 1.0
    private static let sigkillGracePeriodSeconds: TimeInterval = 1.0
    private static let processPollIntervalSeconds: TimeInterval = 0.05

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
        let stdoutHandle = stdout.fileHandleForReading
        let stderrHandle = stderr.fileHandleForReading

        process.executableURL = try workerExecutableURL()
        process.arguments = [suiteName, sourcePath]
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = stdout
        process.standardError = stderr

        drain(pipe: stdout, into: stdoutAccumulator, group: stdoutGroup)
        drain(pipe: stderr, into: stderrAccumulator, group: stderrGroup)
        defer {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
        }

        try process.run()
        let deadline = Date().addingTimeInterval(subprocessTimeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: processPollIntervalSeconds)
        }
        if process.isRunning {
            process.terminate()
            // Wait for process to exit after terminate to avoid zombie processes
            let terminateDeadline = Date().addingTimeInterval(terminationGracePeriodSeconds)
            while process.isRunning, Date() < terminateDeadline {
                Thread.sleep(forTimeInterval: processPollIntervalSeconds)
            }
            // If process is still running, send SIGKILL
            if process.isRunning {
                // Note: There's a race condition between this check and the kill() call where the process
                // could exit and the PID could be reused. This is a fundamental limitation of the kill() API.
                let killResult = kill(process.processIdentifier, SIGKILL)
                if killResult != 0 && errno != ESRCH {
                    // kill() failed with error other than ESRCH (no such process)
                    // ESRCH is expected if process exited between isRunning check and kill call
                    // Other errors are unusual but we continue anyway
                }
                let sigkillDeadline = Date().addingTimeInterval(sigkillGracePeriodSeconds)
                while process.isRunning, Date() < sigkillDeadline {
                    Thread.sleep(forTimeInterval: processPollIntervalSeconds)
                }
                // Verify process exited after SIGKILL
                if process.isRunning {
                    // Process is still running despite SIGKILL - this is unusual but possible
                    // Include this information in the error message
                }
            }
            let stderrText = String(data: stderrAccumulator.snapshot(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorMessage = process.isRunning 
                ? "Worker timed out and survived SIGKILL. \(stderrText)"
                : stderrText
            throw GoldenHarnessAPIError.workerTimedOut(errorMessage)
        }

        // Process has terminated, so stop event-based drain and read remaining data
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil

        // Read any remaining data from pipes (safe since process has terminated)
        let remainingStdout = stdoutHandle.readDataToEndOfFile()
        let remainingStderr = stderrHandle.readDataToEndOfFile()
        stdoutAccumulator.append(remainingStdout)
        stderrAccumulator.append(remainingStderr)

        let stdoutData = stdoutAccumulator.snapshot()
        let stderrData = stderrAccumulator.snapshot()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw GoldenHarnessAPIError.workerFailed(process.terminationStatus, stderrText)
        }
        return String(decoding: stdoutData, as: UTF8.self)
    }

    @discardableResult
    public static func persistIfUpdating(
        suiteName: String,
        sourcePath: String,
        actual: String
    ) throws -> Bool {
        try persistIfUpdating(
            suiteName: suiteName,
            sourcePath: sourcePath,
            actual: actual,
            updateMode: GoldenHarnessGoldenFileIO.isUpdateMode
        )
    }

    @discardableResult
    static func persistIfUpdating(
        suiteName: String,
        sourcePath: String,
        actual: String,
        updateMode: Bool
    ) throws -> Bool {
        try GoldenHarnessGoldenFileIO.persistIfUpdating(
            caseFile: caseFile(sourcePath: sourcePath),
            actual: stableOutputForPersistence(suiteName: suiteName, output: actual),
            updateMode: updateMode
        )
    }

    public static func loadExpectedGolden(sourcePath: String) throws -> String {
        try GoldenHarnessGoldenFileIO.loadExpectedGolden(caseFile: caseFile(sourcePath: sourcePath))
    }

    /// Normalizes suite output before comparison so the checked-in golden can stay
    /// stable even when a platform injects extra synthetic symbols into the dump.
    public static func normalizedForComparison(suiteName: String, output: String) -> String {
        switch suiteName {
        case "Sema":
            GoldenHarnessSemaComparisonNormalizer.normalize(output)
        default:
            output
        }
    }

    static func stableOutputForPersistence(suiteName: String, output: String) -> String {
        normalizedForComparison(suiteName: suiteName, output: output)
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

private enum GoldenHarnessSemaComparisonNormalizer {
    private static let positiveSymbolReferenceRegex = try! NSRegularExpression(pattern: "(Class#|T#|s)(\\d+)")
    private static let negativeSymbolReferenceRegex = try! NSRegularExpression(pattern: "(s-)(\\d+)")
    private static let syntheticScopeOrdinalRegex = try! NSRegularExpression(pattern: "(\\.\\$)(\\d+)(?=\\.)")
    private static let localNameOrdinalRegex = try! NSRegularExpression(pattern: "(__local_)(\\d+)")

    static func normalize(_ output: String) -> String {
        let hasTrailingNewline = output.hasSuffix("\n")
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if hasTrailingNewline, lines.last == "" {
            lines.removeLast()
        }

        var symbolLinesByID: [Int: String] = [:]
        var symbolOrder: [Int] = []
        var bodyLines: [String] = []
        bodyLines.reserveCapacity(lines.count)

        for line in lines {
            if let symbolID = symbolID(from: line) {
                symbolLinesByID[symbolID] = line
                symbolOrder.append(symbolID)
            } else {
                bodyLines.append(line)
            }
        }

        var requiredSymbols = Set<Int>()
        var queue: [Int] = []

        for line in bodyLines {
            enqueueReferences(in: line, requiredSymbols: &requiredSymbols, queue: &queue)
        }

        var nextIndex = 0
        while nextIndex < queue.count {
            let symbolID = queue[nextIndex]
            nextIndex += 1
            guard let symbolLine = symbolLinesByID[symbolID] else {
                continue
            }
            enqueueReferences(in: symbolLine, requiredSymbols: &requiredSymbols, queue: &queue)
        }

        guard !requiredSymbols.isEmpty else {
            return output
        }

        let keptSymbolIDs = symbolOrder.filter { requiredSymbols.contains($0) }
        let remappedIDs = Dictionary(uniqueKeysWithValues: keptSymbolIDs.enumerated().map { rawID, symbolID in
            (symbolID, rawID)
        })

        var normalizedLines: [String] = []
        normalizedLines.reserveCapacity(keptSymbolIDs.count + bodyLines.count)

        for symbolID in keptSymbolIDs {
            guard let symbolLine = symbolLinesByID[symbolID] else {
                continue
            }
            normalizedLines.append(rewrite(symbolLine, remappedIDs: remappedIDs))
        }

        for line in bodyLines {
            normalizedLines.append(rewrite(line, remappedIDs: remappedIDs))
        }

        var normalized = normalizedLines.joined(separator: "\n")
        normalized = rewriteOrdinalMatches(
            in: normalized,
            regex: syntheticScopeOrdinalRegex
        )
        normalized = rewriteOrdinalMatches(
            in: normalized,
            regex: localNameOrdinalRegex
        )
        normalized = rewriteOrdinalMatches(
            in: normalized,
            regex: negativeSymbolReferenceRegex
        )
        return hasTrailingNewline ? normalized + "\n" : normalized
    }

    private static func symbolID(from line: String) -> Int? {
        guard line.hasPrefix("symbol s") else {
            return nil
        }

        let start = line.index(line.startIndex, offsetBy: "symbol s".count)
        var end = start
        while end < line.endIndex, line[end].isNumber {
            end = line.index(after: end)
        }
        guard end > start else {
            return nil
        }
        return Int(line[start ..< end])
    }

    private static func enqueueReferences(
        in line: String,
        requiredSymbols: inout Set<Int>,
        queue: inout [Int]
    ) {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        for match in positiveSymbolReferenceRegex.matches(in: line, range: range) {
            let idRange = match.range(at: 2)
            guard idRange.location != NSNotFound,
                  let symbolID = Int(nsLine.substring(with: idRange)),
                  requiredSymbols.insert(symbolID).inserted
            else {
                continue
            }
            queue.append(symbolID)
        }
    }

    private static func rewrite(_ line: String, remappedIDs: [Int: Int]) -> String {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        let matches = positiveSymbolReferenceRegex.matches(in: line, range: range)
        guard !matches.isEmpty else {
            return line
        }

        let mutable = NSMutableString(string: line)
        for match in matches.reversed() {
            let prefixRange = match.range(at: 1)
            let idRange = match.range(at: 2)
            guard prefixRange.location != NSNotFound,
                  idRange.location != NSNotFound,
                  let oldID = Int(nsLine.substring(with: idRange)),
                  let newID = remappedIDs[oldID]
            else {
                continue
            }
            let prefix = nsLine.substring(with: prefixRange)
            mutable.replaceCharacters(in: match.range, with: "\(prefix)\(newID)")
        }
        return mutable as String
    }

    private static func rewriteOrdinalMatches(
        in text: String,
        regex: NSRegularExpression
    ) -> String {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return text
        }

        var remappedIDs: [Int: Int] = [:]
        for match in matches {
            let idRange = match.range(at: 2)
            guard idRange.location != NSNotFound,
                  let oldID = Int(nsText.substring(with: idRange))
            else {
                continue
            }
            if remappedIDs[oldID] == nil {
                remappedIDs[oldID] = remappedIDs.count
            }
        }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let prefixRange = match.range(at: 1)
            let idRange = match.range(at: 2)
            guard prefixRange.location != NSNotFound,
                  idRange.location != NSNotFound,
                  let oldID = Int(nsText.substring(with: idRange)),
                  let newID = remappedIDs[oldID]
            else {
                continue
            }
            let prefix = nsText.substring(with: prefixRange)
            mutable.replaceCharacters(in: match.range, with: "\(prefix)\(newID)")
        }
        return mutable as String
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
