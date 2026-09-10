import CompilerCore
import Foundation

/// Bridges the language server to the KSwiftK compiler frontend.
///
/// Each analysis runs the frontend (`LoadSources → Lex → Parse → BuildAST →
/// Sema`) over a single open document using its in-memory contents, and caches
/// the resulting `CompilationContext` so position-based queries (hover,
/// definition, document symbols) can reuse it.
public final class Analyzer: @unchecked Sendable {
    enum AnalysisEvent: Sendable {
        case started(uri: String, text: String)
        case completed(uri: String, text: String)
    }

    /// The outcome of analyzing one document.
    public struct Analysis {
        public let uri: String
        public let path: String
        public let result: FrontendResult
        public let fileID: FileID?

        public var context: CompilationContext { result.context }
        public var diagnostics: [Diagnostic] { result.diagnostics }
    }

    private let driver = CompilerDriver()
    private let moduleName: String
    /// Explicit stdlib artifact used by the LSP process, when one is prepared
    /// by its startup entry point. Keeping this per-analyzer avoids relying on
    /// the process-global CompilerOptions default while documents are analyzed
    /// concurrently.
    private let stdlibLibraryPath: String?
    private let analysisLock = NSLock()
    private let cacheLock = NSLock()
    private let analysisEvent: (@Sendable (AnalysisEvent) -> Void)?
    private var cache: [String: Analysis] = [:]

    public convenience init(
        moduleName: String = "LSPModule",
        stdlibLibraryPath: String? = nil
    ) {
        self.init(
            moduleName: moduleName,
            stdlibLibraryPath: stdlibLibraryPath,
            analysisEvent: nil
        )
    }

    init(
        moduleName: String = "LSPModule",
        stdlibLibraryPath: String? = nil,
        analysisEvent: (@Sendable (AnalysisEvent) -> Void)?
    ) {
        self.moduleName = moduleName
        self.stdlibLibraryPath = stdlibLibraryPath
        self.analysisEvent = analysisEvent
    }

    /// Runs the frontend over the given document text and caches the result.
    @discardableResult
    public func analyze(uri: String, text: String) -> Analysis {
        analysisLock.lock()
        let analysis = makeAnalysis(uri: uri, text: text)
        analysisLock.unlock()

        cacheLock.lock()
        cache[uri] = analysis
        cacheLock.unlock()
        return analysis
    }

    /// Runs the frontend without changing the cached analysis.
    ///
    /// Servers can use this for work that may become stale while the frontend
    /// is running, then cache the result only after validating its generation.
    func analyzeWithoutCaching(uri: String, text: String) -> Analysis {
        analysisLock.lock()
        let analysis = makeAnalysis(uri: uri, text: text)
        analysisLock.unlock()
        return analysis
    }

    /// Stores an analysis after its caller has validated that it is current.
    func cache(_ analysis: Analysis) {
        cacheLock.lock()
        cache[analysis.uri] = analysis
        cacheLock.unlock()
    }

    private func makeAnalysis(uri: String, text: String) -> Analysis {
        analysisEvent?(.started(uri: uri, text: text))

        let path = Analyzer.path(forURI: uri)
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [path],
            outputPath: "/dev/null",
            emit: .object,
            target: .hostDefault(),
            stdlibLibraryPath: stdlibLibraryPath,
            allowDefaultStdlibLibrary: false
        )
        let result = driver.runFrontend(
            options: options,
            inMemorySources: [path: Data(text.utf8)],
            continuationPolicy: .continueAfterParseError
        )
        let fileID = result.context.sourceManager.fileID(forPath: path)
        let analysis = Analysis(uri: uri, path: path, result: result, fileID: fileID)
        analysisEvent?(.completed(uri: uri, text: text))
        return analysis
    }

    /// Returns the cached analysis for a URI, if one exists.
    public func analysis(for uri: String) -> Analysis? {
        cacheLock.lock()
        let analysis = cache[uri]
        cacheLock.unlock()
        return analysis
    }

    /// Drops a cached analysis (e.g. when a document is closed).
    public func remove(uri: String) {
        cacheLock.lock()
        cache.removeValue(forKey: uri)
        cacheLock.unlock()
    }

    /// Resolves a document URI to the filesystem path used as the compiler
    /// input. Falls back to the raw URI string for non-file schemes so that an
    /// in-memory buffer can still be analyzed.
    public static func path(forURI uri: String) -> String {
        DocumentURI.path(fromURI: uri) ?? uri
    }
}
