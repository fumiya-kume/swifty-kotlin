import Foundation

final class SemaPhase: CompilerPhase {
    static let name = "Sema"

    private let passes: [CompilerPhase] = [
        DataFlowSemaPhase(),
        TypeCheckSemaPhase(),
    ]

    init() {}

    func run(_ ctx: CompilationContext) throws {
        guard ctx.ast != nil else {
            throw CompilerPipelineError.invalidInput("AST phase did not run.")
        }
        for phase in passes {
            try phase.run(ctx)
        }
    }
}
