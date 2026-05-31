import CompilerCore
import Foundation

/// Bridges the language server to the KSwiftK compiler frontend.
///
/// Each analysis runs the frontend (`LoadSources → Lex → Parse → BuildAST →
/// Sema`) over a single open document using its in-memory contents, and caches
/// the resulting `CompilationContext` so position-based queries (hover,
/// definition, document symbols) can reuse it.
public final class Analyzer {
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
    private var cache: [String: Analysis] = [:]

    public init(moduleName: String = "LSPModule") {
        self.moduleName = moduleName
    }

    /// Runs the frontend over the given document text and caches the result.
    @discardableResult
    public func analyze(uri: String, text: String) -> Analysis {
        let path = Analyzer.path(forURI: uri)
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [path],
            outputPath: "/dev/null",
            emit: .object,
            target: .hostDefault()
        )
        let result = driver.runFrontend(
            options: options,
            inMemorySources: [path: Data(text.utf8)]
        )
        let fileID = result.context.sourceManager.fileID(forPath: path)
        let analysis = Analysis(uri: uri, path: path, result: result, fileID: fileID)
        cache[uri] = analysis
        return analysis
    }

    /// Returns the cached analysis for a URI, if one exists.
    public func analysis(for uri: String) -> Analysis? {
        cache[uri]
    }

    /// Drops a cached analysis (e.g. when a document is closed).
    public func remove(uri: String) {
        cache.removeValue(forKey: uri)
    }

    /// Resolves a document URI to the filesystem path used as the compiler
    /// input. Falls back to the raw URI string for non-file schemes so that an
    /// in-memory buffer can still be analyzed.
    public static func path(forURI uri: String) -> String {
        DocumentURI.path(fromURI: uri) ?? uri
    }
}
