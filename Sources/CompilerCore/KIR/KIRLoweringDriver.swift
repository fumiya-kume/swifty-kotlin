import Foundation

/// Dispatch hub for KIR lowering. Replaces the monolithic extension-based splitting
/// of `BuildKIRPhase` with independent delegate classes.
///
/// Each delegate holds an `unowned` back-reference to this driver so that mutually
/// recursive calls (e.g. `lowerExpr` → `lowerCallExpr` → `lowerExpr`) can be
/// dispatched through the driver rather than sharing a single fat class instance.
final class KIRLoweringDriver {
    let ctx: KIRLoweringContext

    // Delegates (lazy to break initialization ordering; each holds unowned back-reference)
    private(set) lazy var exprLowerer = ExprLowerer(driver: self)
    private(set) lazy var callLowerer = CallLowerer(driver: self)
    private(set) lazy var controlFlowLowerer = ControlFlowLowerer(driver: self)
    private(set) lazy var memberLowerer = MemberLowerer(driver: self)
    private(set) lazy var lambdaLowerer = LambdaLowerer(driver: self)
    private(set) lazy var objectLiteralLowerer = ObjectLiteralLowerer(driver: self)
    private(set) lazy var callSupportLowerer = CallSupportLowerer(driver: self)

    // Stateless utilities (no back-reference needed)
    let constantCollector = ConstantCollector()

    init(ctx: KIRLoweringContext) {
        self.ctx = ctx
    }

    // MARK: - Main Recursive Dispatch Entry Point

    func lowerExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        return exprLowerer.lowerExpr(
            exprID,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }


    func lowerExpr(
        _ exprID: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        return exprLowerer.lowerExpr(
            exprID,
            shared: shared,
            emit: &instructions
        )
    }

}
