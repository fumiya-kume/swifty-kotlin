import Foundation

public final class SemaPhase: CompilerPhase {
    public static let name = "Sema"

    private let passes: [CompilerPhase] = [
        DataFlowSemaPhase(),
        TypeCheckSemaPhase()
    ]

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard ctx.ast != nil else {
            throw CompilerPipelineError.invalidInput("AST phase did not run.")
        }
        for phase in passes {
            try phase.run(ctx)
        }
    }
}
