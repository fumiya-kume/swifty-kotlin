import Foundation

/// Lowering for `lateinit` property initialization checks.
extension CallLowerer {
    func tryLowerLateinitIsInitialized(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers _: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              calleeName == KnownCompilerNames(interner: interner).isInitialized,
              case .callableRef = ast.arena.expr(receiverExpr),
              let propertySymbol = sema.bindings.identifierSymbol(for: receiverExpr),
              let propertyInfo = sema.symbols.symbol(propertySymbol),
              propertyInfo.kind == .property,
              propertyInfo.flags.contains(.lateinitProperty)
        else {
            return nil
        }

        let storageExpr: KIRExprID
        if let parentSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let parentInfo = sema.symbols.symbol(parentSymbol),
           parentInfo.kind != .package,
           parentInfo.kind != .object
        {
            guard let receiverExpr = driver.ctx.activeImplicitReceiverExprID(),
                  let fieldOffset = sema.symbols.nominalLayout(for: parentSymbol)?.fieldOffsets[
                      sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
                  ]
            else {
                return nil
            }
            let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let loaded = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: propertyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverExpr, offsetExpr],
                result: loaded,
                canThrow: false,
                thrownResult: nil
            ))
            storageExpr = loaded
        } else {
            let storageSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            let storageType = sema.symbols.propertyType(for: storageSymbol)
                ?? sema.symbols.propertyType(for: propertySymbol)
                ?? sema.types.anyType
            let loaded = arena.appendExpr(.symbolRef(storageSymbol), type: storageType)
            instructions.append(.loadGlobal(result: loaded, symbol: storageSymbol))
            storageExpr = loaded
        }

        let resultType = sema.bindings.exprType(for: exprID)
            ?? sema.types.make(.primitive(.boolean, .nonNull))
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_lateinit_is_initialized"),
            arguments: [storageExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

}
