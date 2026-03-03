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
    // swiftlint:disable:next cyclomatic_complexity
    static func range(of expr: Expr) -> SourceRange? {
        switch expr {
        case let .intLiteral(_, range): range
        case let .longLiteral(_, range): range
        case let .floatLiteral(_, range): range
        case let .doubleLiteral(_, range): range
        case let .charLiteral(_, range): range
        case let .boolLiteral(_, range): range
        case let .stringLiteral(_, range): range
        case let .stringTemplate(_, range: range): range
        case let .nameRef(_, range): range
        case let .forExpr(_, _, _, _, range: range): range
        case let .whileExpr(_, _, _, range: range): range
        case let .doWhileExpr(_, _, _, range: range): range
        case let .breakExpr(_, range: range): range
        case let .continueExpr(_, range: range): range
        case let .localDecl(_, _, _, _, range: range): range
        case let .localAssign(_, _, range: range): range
        case let .memberAssign(_, _, _, range: range): range
        case let .indexedAssign(_, _, _, range: range): range
        case let .call(_, _, _, range: range): range
        case let .memberCall(_, _, _, _, range: range): range
        case let .indexedAccess(_, _, range: range): range
        case let .binary(_, _, _, range: range): range
        case let .whenExpr(_, _, _, range: range): range
        case let .returnExpr(_, _, range: range): range
        case let .ifExpr(_, _, _, range: range): range
        case let .tryExpr(_, _, _, range: range): range
        case let .unaryExpr(_, _, range: range): range
        case let .isCheck(_, _, _, range: range): range
        case let .asCast(_, _, _, range: range): range
        case let .nullAssert(_, range: range): range
        case let .safeMemberCall(_, _, _, _, range: range): range
        case let .compoundAssign(_, _, _, range: range): range
        case let .indexedCompoundAssign(_, _, _, _, range: range): range
        case let .throwExpr(_, range: range): range
        case let .lambdaLiteral(_, _, _, range: range): range
        case let .objectLiteral(_, range: range): range
        case let .callableRef(_, _, range: range): range
        case let .localFunDecl(_, _, _, _, range: range): range
        case let .blockExpr(_, _, range: range): range
        case let .superRef(_, range): range
        case let .thisRef(_, range): range
        case let .inExpr(_, _, range: range): range
        case let .notInExpr(_, _, range: range): range
        case let .destructuringDecl(_, _, _, range: range): range
        case let .forDestructuringExpr(_, _, _, range: range): range
        }
    }
}
