import Foundation

extension ControlFlowLowerer {
    func appendThrowAwareInstructions(
        _ loweredInstructions: KIRLoweringEmitContext,
        exceptionSlot: KIRExprID,
        exceptionTypeSlot: KIRExprID,
        thrownTarget: Int32,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        emit instructions: inout KIRLoweringEmitContext
    ) {
        appendThrowAwareInstructions(
            Array(loweredInstructions),
            exceptionSlot: exceptionSlot,
            exceptionTypeSlot: exceptionTypeSlot,
            thrownTarget: thrownTarget,
            sema: sema,
            interner: interner,
            arena: arena,
            instructions: &instructions.instructions
        )
    }

    func resolveCatchClauseBinding(
        _ clause: CatchClause,
        sema: SemaModule,
        interner: StringInterner
    ) -> CatchClauseBinding {
        if let binding = sema.bindings.catchClauseBinding(for: clause.body) {
            return binding
        }
        let fallbackType = resolveLegacyCatchClauseType(
            clause.paramTypeName,
            sema: sema,
            interner: interner
        )
        let fallbackSymbol = sema.bindings.identifierSymbols[clause.body] ?? .invalid
        return CatchClauseBinding(parameterSymbol: fallbackSymbol, parameterType: fallbackType)
    }

    func resolveLegacyCatchClauseType(
        _ typeName: InternedString?,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let typeName else {
            return sema.types.anyType
        }
        if let builtin = BuiltinTypeNames(interner: interner).resolveBuiltinType(typeName, types: sema.types) {
            return builtin
        }
        let candidates = sema.symbols.lookupAll(fqName: [typeName])
            .filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                switch symbol.kind {
                case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                    return true
                default:
                    return false
                }
            }
            .sorted { $0.rawValue < $1.rawValue }
        guard let symbol = candidates.first else {
            return sema.types.errorType
        }
        return sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
    }

    func isCatchAllType(_ type: TypeID, sema: SemaModule) -> Bool {
        type == sema.types.anyType || type == sema.types.nullableAnyType || type == sema.types.errorType
    }

    func isCatchAllType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        if isCatchAllType(type, sema: sema) {
            return true
        }
        if type == sema.types.anyType || type == sema.types.nullableAnyType {
            return true
        }
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return KnownCompilerNames(interner: interner).isThrowableCatchAllSymbol(symbol)
    }

    func isCancellationExceptionType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return KnownCompilerNames(interner: interner).isCancellationExceptionSymbol(symbol)
    }

    func lowerForDestructuringExpr(
        _ exprID: ExprID,
        names: [InternedString?],
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerForDestructuringExpr(
            exprID,
            names: names,
            iterableExpr: iterableExpr,
            bodyExpr: bodyExpr,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }

    func lowerWhenExpr(
        _ exprID: ExprID,
        subject: ExprID?,
        branches: [WhenBranch],
        elseExpr: ExprID?,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerWhenExpr(
            exprID,
            subject: subject,
            branches: branches,
            elseExpr: elseExpr,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }
}
