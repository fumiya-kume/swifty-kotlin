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

public struct GoldenHarnessBatchResult: Codable, Sendable {
    public let sourcePath: String
    public let output: String?
    public let errorDescription: String?

    public init(sourcePath: String, output: String?, errorDescription: String?) {
        self.sourcePath = sourcePath
        self.output = output
        self.errorDescription = errorDescription
    }
}

enum GoldenHarnessAPIError: Error, CustomStringConvertible {
    case unknownSuite(String)
    case workerExecutableNotFound(String)
    case workerFailed(Int32, String)
    case workerTimedOut(String)
    case invalidWorkerOutput(String)

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
        case let .invalidWorkerOutput(details):
            return "Golden worker returned invalid output: \(details)"
        }
    }
}

public enum GoldenHarness {
    private static let subprocessTimeout: TimeInterval = 30
    private static let terminationGracePeriodSeconds: TimeInterval = 1.0
    private static let sigkillGracePeriodSeconds: TimeInterval = 1.0
    private static let processPollIntervalSeconds: TimeInterval = 0.05

    /// Environment variable carrying a prebuilt stdlib `.kklib` path into the
    /// worker process. When set, each dump compiles the case against the
    /// artifact's serialized metadata instead of re-running the bundled-stdlib
    /// source pipeline for every case.
    static let stdlibLibraryEnvironmentKey = "KSWIFTK_GOLDEN_STDLIB_LIBRARY"

    public static func loadCasesOrCrash(suiteName: String) -> [GoldenHarnessCase] {
        do {
            return try GoldenHarnessCaseDiscovery.loadCases(suite: try suite(named: suiteName)).map {
                GoldenHarnessCase(sourcePath: $0.sourcePath, basename: $0.basename)
            }
        } catch {
            preconditionFailure("GoldenHarness case discovery failed for \(suiteName): \(error)")
        }
    }

    /// Renders and normalizes suite output for one source file. Normalizing here
    /// (rather than only at comparison/persistence time) means every caller —
    /// including a `GoldenHarnessWorker` invocation run directly from the
    /// command line — gets output that is already a fixed point of
    /// `normalizedForComparison`, so a `.golden` file can never be committed
    /// with process-local ordinals (symbol namespace counters, expression
    /// occurrence indices) baked in.
    public static func render(suiteName: String, sourcePath: String) throws -> String {
        let resolvedSuite = try suite(named: suiteName)
        let stdlibLibraryPath = ProcessInfo.processInfo.environment[stdlibLibraryEnvironmentKey]
        let raw: String = switch resolvedSuite {
        case .lexer:
            try GoldenHarnessDump.dumpLexer(sourcePath: sourcePath, stdlibLibraryPath: stdlibLibraryPath)
        case .parser:
            try GoldenHarnessDump.dumpParser(sourcePath: sourcePath, stdlibLibraryPath: stdlibLibraryPath)
        case .sema:
            try GoldenHarnessDump.dumpSema(sourcePath: sourcePath, stdlibLibraryPath: stdlibLibraryPath)
        case .diagnostics:
            try GoldenHarnessDump.dumpDiagnostics(sourcePath: sourcePath, stdlibLibraryPath: stdlibLibraryPath)
        }
        return normalizedForComparison(suite: resolvedSuite, output: raw)
    }

    public static func renderInSubprocess(
        suiteName: String,
        sourcePath: String,
        stdlibLibraryPath: String? = nil
    ) throws -> String {
        let stdoutData = try runWorker(
            arguments: [suiteName, sourcePath],
            timeout: subprocessTimeout,
            stdlibLibraryPath: stdlibLibraryPath
        )
        return String(decoding: stdoutData, as: UTF8.self)
    }

    public static func renderBatchInSubprocess(
        suiteName: String,
        sourcePaths: [String],
        stdlibLibraryPath: String? = nil
    ) throws -> [GoldenHarnessBatchResult] {
        guard !sourcePaths.isEmpty else {
            return []
        }

        let stdoutData = try runWorker(
            arguments: ["--batch", suiteName] + sourcePaths,
            timeout: subprocessTimeout * TimeInterval(sourcePaths.count),
            stdlibLibraryPath: stdlibLibraryPath
        )
        let results: [GoldenHarnessBatchResult]
        do {
            results = try JSONDecoder().decode([GoldenHarnessBatchResult].self, from: stdoutData)
        } catch {
            throw GoldenHarnessAPIError.invalidWorkerOutput(
                "could not decode batch response: \(error)"
            )
        }
        guard results.map(\.sourcePath) == sourcePaths else {
            throw GoldenHarnessAPIError.invalidWorkerOutput(
                "batch response paths did not match the requested paths"
            )
        }
        return results
    }

    private static func runWorker(
        arguments: [String],
        timeout: TimeInterval,
        stdlibLibraryPath: String? = nil
    ) throws -> Data {
        let process = Process()
        let stdout = Pipe(), stderr = Pipe()
        let stdoutAccumulator = DataAccumulator()
        let stderrAccumulator = DataAccumulator()
        let stdoutHandle = stdout.fileHandleForReading
        let stderrHandle = stderr.fileHandleForReading
        let stdoutWriteHandle = stdout.fileHandleForWriting
        let stderrWriteHandle = stderr.fileHandleForWriting

        process.executableURL = try workerExecutableURL()
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        if let stdlibLibraryPath {
            environment[stdlibLibraryEnvironmentKey] = stdlibLibraryPath
        }
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        // Drain stdout and stderr on dedicated threads so the subprocess is never
        // stalled by a full pipe buffer (~64 KB on Linux). A single
        // readDataToEndOfFile() per pipe reads all bytes in arrival order without
        // the data-interleaving race that occurs when readabilityHandler callbacks
        // run concurrently with a subsequent readDataToEndOfFile() call.
        let ioGroup = DispatchGroup()
        let stdoutDrain = PipeDrain(
            handle: stdoutHandle,
            accumulator: stdoutAccumulator,
            group: ioGroup,
            name: "GoldenHarness.stdout"
        )
        let stderrDrain = PipeDrain(
            handle: stderrHandle,
            accumulator: stderrAccumulator,
            group: ioGroup,
            name: "GoldenHarness.stderr"
        )
        stdoutDrain.start()
        stderrDrain.start()

        let terminatedSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminatedSemaphore.signal() }
        do {
            try process.run()
        } catch {
            stdoutWriteHandle.closeFile()
            stderrWriteHandle.closeFile()
            ioGroup.wait()
            throw error
        }
        stdoutWriteHandle.closeFile()
        stderrWriteHandle.closeFile()
        if terminatedSemaphore.wait(timeout: .now() + timeout) == .timedOut {
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
            }
            // Process has exited (or survived SIGKILL). The write ends of the pipes are
            // now closed, so the reader tasks reach EOF and complete.
            ioGroup.wait()
            let stderrText = String(data: stderrAccumulator.snapshot(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorMessage = process.isRunning
                ? "Worker timed out and survived SIGKILL. \(stderrText)"
                : stderrText
            throw GoldenHarnessAPIError.workerTimedOut(errorMessage)
        }

        // Process terminated normally; wait for readers to finish collecting all data.
        ioGroup.wait()

        let stdoutData = stdoutAccumulator.snapshot()
        let stderrData = stderrAccumulator.snapshot()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw GoldenHarnessAPIError.workerFailed(process.terminationStatus, stderrText)
        }
        return stdoutData
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
        guard let suite = GoldenHarnessGoldenSuite(rawValue: suiteName) else {
            return output
        }
        return normalizedForComparison(suite: suite, output: output)
    }

    static func normalizedForComparison(suite: GoldenHarnessGoldenSuite, output: String) -> String {
        switch suite {
        case .sema:
            GoldenHarnessSemaComparisonNormalizer.normalize(output)
        case .diagnostics:
            GoldenHarnessDiagnosticsComparisonNormalizer.normalize(output)
        case .lexer, .parser:
            GoldenHarnessFileIDNormalizer.normalize(output)
        }
    }

    static func stableOutputForPersistence(suiteName: String, output: String) -> String {
        guard let suite = GoldenHarnessGoldenSuite(rawValue: suiteName) else {
            return output
        }
        return normalizedForComparison(suite: suite, output: output)
    }

    private static func suite(named suiteName: String) throws -> GoldenHarnessGoldenSuite {
        guard let suite = GoldenHarnessGoldenSuite(rawValue: suiteName) else {
            throw GoldenHarnessAPIError.unknownSuite(suiteName)
        }
        return suite
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
            // swiftlint:disable:next for_where
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

}

private enum GoldenHarnessFileIDNormalizer {
    // swiftlint:disable:next force_try
    private static let fileIDRegex = try! NSRegularExpression(pattern: "f\\d+:")

    static func normalize(_ output: String) -> String {
        let nsOutput = output as NSString
        let range = NSRange(location: 0, length: nsOutput.length)
        return fileIDRegex.stringByReplacingMatches(in: output, range: range, withTemplate: "f0:")
    }
}

private enum GoldenHarnessDiagnosticsComparisonNormalizer {
    // swiftlint:disable:next force_try
    private static let symbolReferenceRegex = try! NSRegularExpression(pattern: "(Class#|T#)(\\d+)")

    static func normalize(_ output: String) -> String {
        let nsOutput = output as NSString
        let range = NSRange(location: 0, length: nsOutput.length)
        let matches = symbolReferenceRegex.matches(in: output, range: range)
        guard !matches.isEmpty else {
            return output
        }

        var remappedIDs: [String: Int] = [:]
        for match in matches {
            let fullRange = match.range
            guard fullRange.location != NSNotFound else { continue }
            let key = nsOutput.substring(with: fullRange)
            if remappedIDs[key] == nil {
                remappedIDs[key] = remappedIDs.count
            }
        }

        let mutable = NSMutableString(string: output)
        for match in matches.reversed() {
            let prefixRange = match.range(at: 1)
            let fullRange = match.range
            guard prefixRange.location != NSNotFound,
                  fullRange.location != NSNotFound
            else { continue }
            let key = nsOutput.substring(with: fullRange)
            let prefix = nsOutput.substring(with: prefixRange)
            guard let newID = remappedIDs[key] else { continue }
            mutable.replaceCharacters(in: fullRange, with: "\(prefix)\(newID)")
        }
        return mutable as String
    }
}

private enum GoldenHarnessSemaComparisonNormalizer {
    // swiftlint:disable:next force_try
    private static let semaFileIDRegex = try! NSRegularExpression(pattern: "(\\bfile f)(\\d+)(?= package=)")
    // swiftlint:disable:next force_try
    private static let negativeSymbolReferenceRegex = try! NSRegularExpression(pattern: "(s-)(\\d+)")
    // swiftlint:disable:next force_try
    private static let syntheticScopeOrdinalRegex = try! NSRegularExpression(pattern: "(\\.\\$)(\\d+)(?=\\.)")
    // swiftlint:disable:next force_try
    private static let classScopeOrdinalRegex = try! NSRegularExpression(pattern: "(\\.\\$class)(\\d+)(?=\\.)")
    // swiftlint:disable:next force_try
    private static let tpScopeOrdinalRegex = try! NSRegularExpression(pattern: "(\\.\\$tp)(\\d+)(?=\\.)")
    // Multi-type-parameter variant of tpScopeOrdinalRegex: registerSyntheticNativeTopLevelFunction
    // discriminates value-parameter FQNames with all of a function's reified type-parameter raw
    // symbol IDs joined by "_" (e.g. `.$tp123_456.`) once it has 2+ type parameters. Each
    // underscore-separated number is its own process-local ID and is renumbered independently.
    // swiftlint:disable:next force_try
    private static let tpMultiValueScopeOrdinalRegex = try! NSRegularExpression(
        pattern: "(\\.\\$tp)((?:\\d+_)+\\d+)(?=\\.)"
    )
    // swiftlint:disable:next force_try
    private static let ifaceScopeOrdinalRegex = try! NSRegularExpression(pattern: "(\\.\\$iface)(\\d+)(?=\\.)")
    // Secondary-constructor local namespace: `$sec<ctorIndex>_<rawValue>`. ctorIndex is a stable,
    // source-order position (not process-local) and is kept as part of the literal prefix; only the
    // trailing rawValue is renumbered.
    // swiftlint:disable:next force_try
    private static let secScopeOrdinalRegex = try! NSRegularExpression(pattern: "(\\.\\$sec\\d+_)(\\d+)(?=\\.)")
    // swiftlint:disable:next force_try
    private static let localNameOrdinalRegex = try! NSRegularExpression(pattern: "(__local_)(\\d+)")
    // swiftlint:disable:next force_try
    private static let forVarOrdinalRegex = try! NSRegularExpression(pattern: "(__for_)(\\d+)")
    // swiftlint:disable:next force_try
    private static let destructuringOrdinalRegex = try! NSRegularExpression(pattern: "(__destructuring_)(\\d+)")
    // swiftlint:disable:next force_try
    private static let forDestructuringOrdinalRegex = try! NSRegularExpression(pattern: "(__for_destructuring_)(\\d+)")
    // swiftlint:disable:next force_try
    private static let tryOrdinalRegex = try! NSRegularExpression(pattern: "(__try_)(\\d+)")
    // swiftlint:disable:next force_try
    private static let whenOrdinalRegex = try! NSRegularExpression(pattern: "(__when_)(\\d+)")
    // swiftlint:disable:next force_try
    private static let localFunOrdinalRegex = try! NSRegularExpression(pattern: "(__localfun_)(\\d+)")
    // swiftlint:disable:next force_try
    private static let importedInlineOrdinalRegex = try! NSRegularExpression(pattern: "(__imported_inline_)(\\d+)")
    // swiftlint:disable:next force_try
    private static let fileOrdinalRegex = try! NSRegularExpression(pattern: "(file f)(\\d+)(?= package=)")
    // swiftlint:disable:next force_try
    private static let objectLiteralOrdinalRegex = try! NSRegularExpression(pattern: "(__ObjectLiteral_)(\\d+)(?=_)")
    // swiftlint:disable:next force_try
    private static let exprIDRegex = try! NSRegularExpression(pattern: "\\b(e@\\d+:\\d+)(?:#\\d+)?")

    static func normalize(_ output: String) -> String {
        var normalized = output
        normalized = rewriteExpressionIDs(in: normalized)
        normalized = rewriteOrdinalMatches(in: normalized, regex: semaFileIDRegex)
        // Scope prefix ordinals
        normalized = rewriteOrdinalMatches(in: normalized, regex: classScopeOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: ifaceScopeOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: secScopeOrdinalRegex)
        normalized = rewriteMultiValueOrdinalMatches(in: normalized, regex: tpMultiValueScopeOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: tpScopeOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: syntheticScopeOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: objectLiteralOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: localNameOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: forDestructuringOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: forVarOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: destructuringOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: tryOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: whenOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: localFunOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: importedInlineOrdinalRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: negativeSymbolReferenceRegex)
        normalized = rewriteOrdinalMatches(in: normalized, regex: fileOrdinalRegex)
        return normalized
    }

    private static func rewriteExpressionIDs(in text: String) -> String {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = exprIDRegex.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return text
        }

        var remappedIDs: [String: [String: Int]] = [:]
        for match in matches {
            let baseRange = match.range(at: 1)
            let fullRange = match.range
            guard baseRange.location != NSNotFound,
                  fullRange.location != NSNotFound
            else {
                continue
            }
            let base = nsText.substring(with: baseRange)
            let full = nsText.substring(with: fullRange)
            var baseMap = remappedIDs[base, default: [:]]
            if baseMap[full] == nil {
                baseMap[full] = baseMap.count
            }
            remappedIDs[base] = baseMap
        }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let baseRange = match.range(at: 1)
            let fullRange = match.range
            guard baseRange.location != NSNotFound,
                  fullRange.location != NSNotFound
            else {
                continue
            }
            let base = nsText.substring(with: baseRange)
            let full = nsText.substring(with: fullRange)
            guard let newID = remappedIDs[base]?[full] else {
                continue
            }
            let replacement = newID == 0 ? base : "\(base)#\(newID)"
            mutable.replaceCharacters(in: fullRange, with: replacement)
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

    /// Multi-value variant of `rewriteOrdinalMatches` for patterns where group 2 holds several
    /// underscore-joined process-local IDs (e.g. `$tp123_456`) instead of a single one. Every
    /// number shares one ordinal counter across all matches of `regex`, so the same raw ID always
    /// renumbers to the same small value wherever it appears.
    private static func rewriteMultiValueOrdinalMatches(
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
            let valuesRange = match.range(at: 2)
            guard valuesRange.location != NSNotFound else { continue }
            for rawValue in nsText.substring(with: valuesRange).split(separator: "_") {
                guard let oldID = Int(rawValue) else { continue }
                if remappedIDs[oldID] == nil {
                    remappedIDs[oldID] = remappedIDs.count
                }
            }
        }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let prefixRange = match.range(at: 1)
            let valuesRange = match.range(at: 2)
            guard prefixRange.location != NSNotFound,
                  valuesRange.location != NSNotFound
            else {
                continue
            }
            let rawValues = nsText.substring(with: valuesRange).split(separator: "_")
            let newValues = rawValues.compactMap { rawValue -> String? in
                guard let oldID = Int(rawValue), let newID = remappedIDs[oldID] else { return nil }
                return String(newID)
            }
            guard newValues.count == rawValues.count else { continue }
            let prefix = nsText.substring(with: prefixRange)
            mutable.replaceCharacters(in: match.range, with: "\(prefix)\(newValues.joined(separator: "_"))")
        }
        return mutable as String
    }
}

private final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

private final class PipeDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let accumulator: DataAccumulator
    private let group: DispatchGroup
    private let name: String

    init(handle: FileHandle, accumulator: DataAccumulator, group: DispatchGroup, name: String) {
        self.handle = handle
        self.accumulator = accumulator
        self.group = group
        self.name = name
    }

    func start() {
        group.enter()
        let thread = Thread { [self] in
            accumulator.append(handle.readDataToEndOfFile())
            group.leave()
        }
        thread.name = name
        thread.start()
    }
}
