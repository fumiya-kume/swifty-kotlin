import Foundation

public final class CompilerDriver {
    private let version: CompilerVersion
    private let kotlinVersion: KotlinLanguageVersion

    public init(version: CompilerVersion, kotlinVersion: KotlinLanguageVersion) {
        self.version = version
        self.kotlinVersion = kotlinVersion
    }

    public func run(options: CompilerOptions) -> Int {
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
                ctx.diagnostics.error("KSWIFTK-ICE-0001", "Compiler internal error: \(error)", range: nil)
            }
        }

        ctx.diagnostics.printDiagnostics(from: sourceManager)

        return ctx.diagnostics.hasError ? 1 : 0
    }
}
