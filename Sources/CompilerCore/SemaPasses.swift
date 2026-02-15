import Foundation

public final class SemaPassesPhase: CompilerPhase {
    public static let name = "SemaPasses"

    private let passes: [CompilerPhase] = [
        DataFlowSemaPassPhase(),
        TypeCheckSemaPassPhase()
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
