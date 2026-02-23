import Foundation

protocol LoweringPass: KIRPass {
    /// Returns `false` when the module contains no instructions that this
    /// pass would rewrite, allowing the driver to skip `run` entirely.
    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool
}

extension LoweringPass {
    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool { true }
}

public final class LoweringPhase: CompilerPhase {
    public static let name = "Lowerings"

    private let passes: [any LoweringPass] = [
        NormalizeBlocksPass(),
        OperatorLoweringPass(),
        ForLoweringPass(),

        PropertyLoweringPass(),
        DataEnumSealedSynthesisPass(),
        LambdaClosureConversionPass(),
        InlineLoweringPass(),
        CoroutineLoweringPass(),
        ABILoweringPass()
    ]

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let module = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for lowering.")
        }
        let kirCtx = KIRContext(
            diagnostics: ctx.diagnostics,
            options: ctx.options,
            interner: ctx.interner,
            sema: ctx.sema
        )
        for pass in passes {
            if pass.shouldRun(module: module, ctx: kirCtx) {
                try pass.run(module: module, ctx: kirCtx)
            } else {
                module.recordLowering(type(of: pass).name)
            }
        }
    }
}
