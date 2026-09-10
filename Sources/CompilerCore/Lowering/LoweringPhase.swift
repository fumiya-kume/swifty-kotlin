
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

/// Marker protocol for lowering passes whose `transformFunctions` closure
/// is safe for concurrent per-function execution.  The closure must not
/// mutate cross-function state — only `arena.appendExpr` (which is locked
/// when parallel mode is active) and per-function-local variables.
protocol ParallelLoweringPass: LoweringPass {}

public final class LoweringPhase: CompilerPhase {
    public static let name = "Lowerings"

    private let passes: [any LoweringPass] = [
        TailrecLoweringPass(), // Must run before NormalizeBlocksPass (relies on beginBlock)
        NormalizeBlocksPass(),
        OperatorLoweringPass(),
        ForLoweringPass(),
        CollectionLiteralLoweringPass(),
        FlowLoweringPass(),

        ValueClassUnboxingPass(), // VAL-001: must run before PropertyLowering
        PropertyLoweringPass(),
        JvmStaticLoweringPass(),
        JvmOverloadsLoweringPass(),
        DataEnumSealedSynthesisPass(),
        EnumEntriesLoweringPass(),
        ConsolePrintLoweringPass(),
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
        // BUG-240: ImportedInlineKIRMaterializer.materialize() corrupts
        // unrelated imported-inline KIR at runtime; disabled until fixed.
        // Re-enabling condition and regression scope: TODO.md BUG-240.
        module.scanFeatures()
        // Parallel lowering is disabled: appendExpr assigns IDs under lock
        // in non-deterministic order, breaking KIR determinism tests.
        // ParallelLoweringPass conformance and KIRArena infrastructure are
        // kept for future enablement once per-function expression arenas
        // provide deterministic ID assignment.
        for pass in passes {
            if pass.shouldRun(module: module, ctx: kirCtx) {
                try pass.run(module: module, ctx: kirCtx)
            } else {
                module.recordLowering(type(of: pass).name)
            }
        }
    }
}
