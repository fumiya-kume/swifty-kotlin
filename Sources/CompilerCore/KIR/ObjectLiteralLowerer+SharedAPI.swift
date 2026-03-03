import Foundation

/// Forwarding overload for ObjectLiteralLowerer that accepts KIRLoweringSharedContext
/// and KIRLoweringEmitContext, delegating to the old-API function.
extension ObjectLiteralLowerer {
    func lowerObjectLiteralExpr(
        _ exprID: ExprID,
        superTypes: [TypeRefID],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerObjectLiteralExpr(
            exprID,
            superTypes: superTypes,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            instructions: &instructions.instructions
        )
    }
}
