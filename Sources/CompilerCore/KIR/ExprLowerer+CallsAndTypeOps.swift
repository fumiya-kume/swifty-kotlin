import Foundation

extension ExprLowerer {
    func lowerIsCheckTypeTokenExpr(
        typeRefID: TypeRefID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))

        func emitLiteral(_ literal: Int64) -> KIRExprID {
            let tokenExpr = arena.appendExpr(.intLiteral(literal), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(literal)))
            return tokenExpr
        }

        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return emitLiteral(RuntimeTypeCheckToken.unknownBase)
        }

        switch typeRef {
        case let .named(path, _, nullable):
            guard let last = path.last else {
                return emitLiteral(RuntimeTypeCheckToken.unknownBase)
            }
            if path.count == 1,
               let tokenSymbol = reifiedTypeTokenSymbol(for: last, sema: sema)
            {
                let tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
                instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
                return tokenExpr
            }
            if let symbol = sema.symbols.lookup(fqName: path),
               let nominal = sema.symbols.symbol(symbol),
               nominal.kind == .class || nominal.kind == .interface || nominal.kind == .object || nominal.kind == .enumClass
            {
                let nominalTypeID = RuntimeTypeCheckToken.stableNominalTypeID(symbol: symbol, sema: sema, interner: interner)
                return emitLiteral(
                    RuntimeTypeCheckToken.encode(
                        base: RuntimeTypeCheckToken.nominalBase,
                        nullable: nullable,
                        payload: nominalTypeID
                    )
                )
            }
            let literal = RuntimeTypeCheckToken.encodeBuiltinTypeName(
                last,
                nullable: nullable,
                builtinNames: BuiltinTypeNames(interner: interner)
            )
                ?? RuntimeTypeCheckToken.encode(base: RuntimeTypeCheckToken.unknownBase, nullable: nullable)
            return emitLiteral(literal)

        case let .functionType(_, _, _, nullable):
            return emitLiteral(
                RuntimeTypeCheckToken.encode(
                    base: RuntimeTypeCheckToken.unknownBase,
                    nullable: nullable
                )
            )

        case .intersection:
            return emitLiteral(RuntimeTypeCheckToken.unknownBase)
        }
    }

    func lowerTypeCheckTokenExpr(
        targetType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let encoded = RuntimeTypeCheckToken.encode(type: targetType, sema: sema, interner: interner)
        let tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
        return tokenExpr
    }

    func reifiedTypeTokenSymbol(
        for typeName: InternedString,
        sema: SemaModule
    ) -> SymbolID? {
        guard let currentFunctionSymbol = driver.ctx.activeFunctionSymbol(),
              let signature = sema.symbols.functionSignature(for: currentFunctionSymbol)
        else {
            return nil
        }
        for typeParameterSymbol in signature.typeParameterSymbols {
            guard let symbol = sema.symbols.symbol(typeParameterSymbol),
                  symbol.kind == .typeParameter,
                  symbol.name == typeName,
                  symbol.flags.contains(.reifiedTypeParameter)
            else {
                continue
            }
            return SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParameterSymbol)
        }
        return nil
    }
}
