import Foundation

public final class CompilerDriver {
    private let version: CompilerVersion
    private let kotlinVersion: KotlinLanguageVersion

    public init(version: CompilerVersion, kotlinVersion: KotlinLanguageVersion) {
        self.version = version
        self.kotlinVersion = kotlinVersion
    }

    public func run(options: CompilerOptions) -> Int {
        let result = runInternal(options: options, printDiagnostics: true)
        return result.exitCode
    }

    func runForTesting(options: CompilerOptions) -> (exitCode: Int, diagnostics: [Diagnostic]) {
        runInternal(options: options, printDiagnostics: false)
    }

    static func fallbackDiagnostic(for error: Error) -> (code: String, message: String)? {
        guard let pipelineError = error as? CompilerPipelineError else {
            return nil
        }
        switch pipelineError {
        case .loadError:
            return (
                code: "KSWIFTK-PIPELINE-0001",
                message: "Compiler pipeline failed while loading input sources."
            )
        case .invalidInput(let detail):
            return (
                code: "KSWIFTK-PIPELINE-0002",
                message: "Compiler pipeline received invalid intermediate state: \(detail)"
            )
        case .outputUnavailable:
            return (
                code: "KSWIFTK-PIPELINE-0003",
                message: "Compiler pipeline could not produce requested output."
            )
        }
    }

    private func runInternal(
        options: CompilerOptions,
        printDiagnostics: Bool
    ) -> (exitCode: Int, diagnostics: [Diagnostic]) {
        let sourceManager = SourceManager()
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let ctx = CompilationContext(
            options: options,
            sourceManager: sourceManager,
            diagnostics: diagnostics,
            interner: interner
        )

        let phases: [CompilerPhase] = [
            LoadSourcesPhase(),
            LexPhase(),
            ParsePhase(),
            BuildASTPhase(),
            SemaPassesPhase(),
            BuildKIRPhase(),
            LoweringPhase(),
            CodegenPhase(),
            LinkPhase()
        ]

        do {
            for phase in phases {
                try phase.run(ctx)
                if ctx.diagnostics.hasError {
                    break
                }
            }
        } catch {
            if !ctx.diagnostics.hasError {
                if let fallback = Self.fallbackDiagnostic(for: error) {
                    ctx.diagnostics.error(fallback.code, fallback.message, range: nil)
                } else {
                    ctx.diagnostics.error("KSWIFTK-ICE-0001", "Compiler internal error: \(error)", range: nil)
                }
            }
        }

        if printDiagnostics {
            ctx.diagnostics.printDiagnostics(from: sourceManager)
        }

        return (ctx.diagnostics.hasError ? 1 : 0, ctx.diagnostics.diagnostics)
    }
}
