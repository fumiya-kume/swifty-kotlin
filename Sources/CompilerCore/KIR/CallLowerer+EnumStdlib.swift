import Foundation

extension CallLowerer {
    func lowerEnumValuesCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .enumValues,
              args.isEmpty,
              let callBinding = sema.bindings.callBindings[exprID],
              let typeArg = callBinding.substitutedTypeArguments.first,
              case let .classType(classType) = sema.types.kind(of: typeArg),
              let nominalSymbol = sema.symbols.symbol(classType.classSymbol),
              nominalSymbol.kind == .enumClass
        else {
            return nil
        }

        let intType = sema.types.intType
        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType

        // Look up Color$enumValuesCount or values() to get the count
        let enumName = interner.resolve(nominalSymbol.name)
        let countHelperName = interner.intern("\(enumName)$enumValuesCount")
        let countHelperFQName = nominalSymbol.fqName + [countHelperName]
        let countSymbol = sema.symbols.lookupAll(fqName: countHelperFQName).first

        let countExpr: KIRExprID
        if let countSymbol {
            let countResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            instructions.append(.call(
                symbol: countSymbol,
                callee: countHelperName,
                arguments: [],
                result: countResult,
                canThrow: false,
                thrownResult: nil
            ))
            countExpr = countResult
        } else {
            // Fallback: use entries count from children
            let entries = sema.symbols.children(ofFQName: nominalSymbol.fqName)
                .compactMap { sema.symbols.symbol($0) }
                .filter { $0.kind == .field }
            let countLiteral = arena.appendExpr(.intLiteral(Int64(entries.count)), type: intType)
            instructions.append(.constValue(result: countLiteral, value: .intLiteral(Int64(entries.count))))
            countExpr = countLiteral
        }

        let kkEnumMakeValuesArray = interner.intern("kk_enum_make_values_array")
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        instructions.append(.call(
            symbol: nil,
            callee: kkEnumMakeValuesArray,
            arguments: [countExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    func lowerEnumValueOfCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .enumValueOf,
              args.count == 1,
              let callBinding = sema.bindings.callBindings[exprID],
              let typeArg = callBinding.substitutedTypeArguments.first,
              case let .classType(classType) = sema.types.kind(of: typeArg),
              let nominalSymbol = sema.symbols.symbol(classType.classSymbol),
              nominalSymbol.kind == .enumClass,
              let companionSymbol = sema.symbols.companionObjectSymbol(for: classType.classSymbol)
        else {
            return nil
        }

        let valueOfName = interner.intern("valueOf")
        let companionFQName = nominalSymbol.fqName + [interner.intern("Companion")]
        let valueOfFQName = companionFQName + [valueOfName]
        let valueOfSymbol = sema.symbols.lookupAll(fqName: valueOfFQName).first
        guard let valueOfSymbol else {
            return nil
        }

        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType

        let companionReceiverExpr = arena.appendExpr(.symbolRef(companionSymbol), type: companionType)
        instructions.append(.constValue(result: companionReceiverExpr, value: .symbolRef(companionSymbol)))

        let nameArg = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        instructions.append(.call(
            symbol: valueOfSymbol,
            callee: valueOfName,
            arguments: [companionReceiverExpr, nameArg],
            result: result,
            canThrow: true,
            thrownResult: nil
        ))
        return result
    }
}
