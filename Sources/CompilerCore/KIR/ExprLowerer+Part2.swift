import Foundation

extension ExprLowerer {
    func lowerExpr(
        _ exprID: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        var old = Array(instructions)
        let result = lowerExpr(
            exprID,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &old
        )
        instructions = KIRLoweringEmitContext(old)
        return result
    }
}
