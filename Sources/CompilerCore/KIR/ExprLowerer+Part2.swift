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

        // Look up the source range for this expression from the AST.
        let exprRange: SourceRange? = shared.ast.arena.expr(exprID).flatMap { expr in
            ExprSourceRange.range(of: expr)
        }

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

/// Helper to extract the ``SourceRange`` from an ``Expr`` value without a
/// giant switch in the call-site. Every ``Expr`` case carries a range as its
/// last associated value (or named `range:`).
enum ExprSourceRange {
    static func range(of expr: Expr) -> SourceRange? {
        switch expr {
        case let .intLiteral(_, r): r
        case let .longLiteral(_, r): r
        case let .floatLiteral(_, r): r
        case let .doubleLiteral(_, r): r
        case let .charLiteral(_, r): r
        case let .boolLiteral(_, r): r
        case let .stringLiteral(_, r): r
        case let .stringTemplate(_, range: r): r
        case let .nameRef(_, r): r
        case let .forExpr(_, _, _, _, range: r): r
        case let .whileExpr(_, _, _, range: r): r
        case let .doWhileExpr(_, _, _, range: r): r
        case let .breakExpr(_, range: r): r
        case let .continueExpr(_, range: r): r
        case let .localDecl(_, _, _, _, range: r): r
        case let .localAssign(_, _, range: r): r
        case let .memberAssign(_, _, _, range: r): r
        case let .indexedAssign(_, _, _, range: r): r
        case let .call(_, _, _, range: r): r
        case let .memberCall(_, _, _, _, range: r): r
        case let .indexedAccess(_, _, range: r): r
        case let .binary(_, _, _, range: r): r
        case let .whenExpr(_, _, _, range: r): r
        case let .returnExpr(_, _, range: r): r
        case let .ifExpr(_, _, _, range: r): r
        case let .tryExpr(_, _, _, range: r): r
        case let .unaryExpr(_, _, range: r): r
        case let .isCheck(_, _, _, range: r): r
        case let .asCast(_, _, _, range: r): r
        case let .nullAssert(_, range: r): r
        case let .safeMemberCall(_, _, _, _, range: r): r
        case let .compoundAssign(_, _, _, range: r): r
        case let .indexedCompoundAssign(_, _, _, _, range: r): r
        case let .throwExpr(_, range: r): r
        case let .lambdaLiteral(_, _, _, range: r): r
        case let .objectLiteral(_, range: r): r
        case let .callableRef(_, _, range: r): r
        case let .localFunDecl(_, _, _, _, range: r): r
        case let .blockExpr(_, _, range: r): r
        case let .superRef(_, r): r
        case let .thisRef(_, r): r
        case let .inExpr(_, _, range: r): r
        case let .notInExpr(_, _, range: r): r
        case let .destructuringDecl(_, _, _, range: r): r
        case let .forDestructuringExpr(_, _, _, range: r): r
        }
    }
}
