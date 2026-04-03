import Foundation

extension CallLowerer {
    func lowerSuspendCoroutineUninterceptedOrReturnCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let specialKind = sema.bindings.stdlibSpecialCallKind(for: exprID),
              specialKind == .suspendCoroutineUninterceptedOrReturn,
              args.count == 1
        else {
            return nil
        }

        let resultType = sema.bindings.exprType(for: exprID) ?? sema.types.anyType
        let continuationType = makeContinuationType(
            resultType: resultType,
            sema: sema,
            interner: interner
        ) ?? sema.types.anyType
        let loweredBlockExpr = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let blockResultExpr: KIRExprID
        if let callableInfo = driver.ctx.callableValueInfo(for: loweredBlockExpr) {
            let continuationExpr = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: continuationType
            )
            let callResultExpr = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: resultType
            )
            instructions.append(.call(
                symbol: callableInfo.symbol,
                callee: callableInfo.callee,
                arguments: callableInfo.captureArguments + [continuationExpr],
                result: callResultExpr,
                canThrow: false,
                thrownResult: nil
            ))
            blockResultExpr = callResultExpr
        } else {
            blockResultExpr = loweredBlockExpr
        }

        let suspendedExpr = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: resultType
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_coroutine_suspended"),
            arguments: [],
            result: suspendedExpr,
            canThrow: false,
            thrownResult: nil
        ))

        let suspendLabel = driver.ctx.makeLoopLabel()
        let resumeLabel = driver.ctx.makeLoopLabel()
        instructions.append(.jumpIfEqual(
            lhs: blockResultExpr,
            rhs: suspendedExpr,
            target: suspendLabel
        ))
        instructions.append(.jump(resumeLabel))
        instructions.append(.label(suspendLabel))
        instructions.append(.returnValue(blockResultExpr))
        instructions.append(.label(resumeLabel))

        return blockResultExpr
    }

    private func makeContinuationType(
        resultType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let fqName = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
            interner.intern("Continuation")
        ]
        guard let symbol = sema.symbols.lookup(fqName: fqName) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [.invariant(resultType)],
            nullability: .nonNull
        )))
    }
}
