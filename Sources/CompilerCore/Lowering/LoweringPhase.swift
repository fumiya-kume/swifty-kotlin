import Foundation

protocol LoweringPass: KIRPass {
    /// Returns `false` when the module contains no instructions that this
    /// pass would rewrite, allowing the driver to skip `run` entirely.
    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool
}

extension LoweringPass {
    func shouldRun(module _: KIRModule, ctx _: KIRContext) -> Bool {
        true
    }
}

final class LoweringPhase: CompilerPhase {
    static let name = "Lowerings"

    private let passes: [any LoweringPass] = [
        TailrecLoweringPass(), // Must run before NormalizeBlocksPass (relies on beginBlock)
        NormalizeBlocksPass(),
        OperatorLoweringPass(),
        ForLoweringPass(),
        CollectionLiteralLoweringPass(),
        FlowLoweringPass(),

        ValueClassUnboxingPass(), // VAL-001: must run before PropertyLowering
        PropertyLoweringPass(),
        StdlibDelegateLoweringPass(),
        JvmStaticLoweringPass(),
        JvmOverloadsLoweringPass(),
        DataEnumSealedSynthesisPass(),
        EnumEntriesLoweringPass(),
        EnumNameAccessLoweringPass(),
        LambdaClosureConversionPass(),
        InlineLoweringPass(),
        CoroutineLoweringPass(),
        // Must run after every pass that emits integer arithmetic builtins
        // (Operator/For/Inline/...) and before ABILoweringPass so the inserted
        // narrowing calls participate in throw-channel resolution.
        IntegerNarrowingPass(),
        ABILoweringPass(),
    ]

    init() {}

    func run(_ ctx: CompilationContext) throws {
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
