import Foundation

/// Result of a frontend-only compilation run used by IDE / language-server
/// scenarios. Holds the populated `CompilationContext` (AST, Sema, diagnostics)
/// together with a snapshot of the collected diagnostics.
public struct FrontendResult {
    public let context: CompilationContext
    public let diagnostics: [Diagnostic]

    public init(context: CompilationContext, diagnostics: [Diagnostic]) {
        self.context = context
        self.diagnostics = diagnostics
    }
}

public extension CompilerDriver {
    /// Runs only the frontend phases
    /// (`LoadSources → Lex → Parse → BuildAST → Sema`) without code generation
    /// or linking. Intended for language-server / editor integrations that need
    /// diagnostics and semantic information for open buffers.
    ///
    /// The returned `CompilationContext` exposes `ast`, `sema`, `sourceManager`
    /// and `interner`, enabling position-based queries (hover, definition,
    /// document symbols) on top of the collected diagnostics.
    ///
    /// - Parameters:
    ///   - options: Compiler options; `options.inputs` lists the files to analyze.
    ///   - inMemorySources: Optional map of file path → source bytes for unsaved
    ///     editor buffers. Each entry is pre-seeded into the `SourceManager`, so
    ///     `LoadSourcesPhase` (which skips already-registered paths) uses the
    ///     in-memory contents instead of reading from disk.
    /// - Returns: A `FrontendResult` with the populated context and diagnostics.
    func runFrontend(
        options: CompilerOptions,
        inMemorySources: [String: Data] = [:]
    ) -> FrontendResult {
        let context = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )

        for (path, data) in inMemorySources {
            _ = context.sourceManager.addFile(path: path, contents: data)
        }

        let phases: [CompilerPhase] = [
            LoadSourcesPhase(),
            LexPhase(),
            ParsePhase(),
            BuildASTPhase(),
            SemaPhase(),
        ]

        for phase in phases {
            do {
                try phase.run(context)
            } catch {
                if !context.diagnostics.hasError {
                    if let fallback = Self.fallbackDiagnostic(for: error) {
                        context.diagnostics.error(fallback.code, fallback.message, range: nil)
                    } else {
                        context.diagnostics.error(
                            "KSWIFTK-ICE-0001",
                            "Compiler internal error: \(error)",
                            range: nil
                        )
                    }
                }
                break
            }
            // Mirror the main pipeline: stop after the first phase that reports
            // an error so later phases never observe a partially-built program.
            if context.diagnostics.hasError {
                break
            }
        }

        context.diagnostics.sortBySourceLocation()
        return FrontendResult(context: context, diagnostics: context.diagnostics.diagnostics)
    }
}
