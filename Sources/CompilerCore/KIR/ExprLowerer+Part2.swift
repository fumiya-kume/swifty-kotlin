import Foundation

extension ExprLowerer {
    func lowerExpr(
        _ exprID: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        // Capture the instruction count before lowering so we can associate
        // source locations with all newly emitted instructions afterwards.
        let beforeCount = instructions.instructions.count

        // Look up the source range for this expression from the AST arena,
        // which already provides a range-extraction helper for all Expr cases.
        let exprRange = shared.ast.arena.exprRange(exprID)

        let result = lowerExpr(
            exprID,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )

        // Pad instructionLocations to match the new instruction count,
        // recording the expression's source range for every instruction
        // that was emitted during this lowerExpr call.
        let afterCount = instructions.instructions.count
        while instructions.instructionLocations.count < beforeCount {
            instructions.instructionLocations.append(nil)
        }
        for _ in beforeCount ..< afterCount {
            instructions.instructionLocations.append(exprRange)
        }

        return result
    }
}
