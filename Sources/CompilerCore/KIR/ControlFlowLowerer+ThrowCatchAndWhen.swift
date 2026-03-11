import Foundation

extension ControlFlowLowerer {
    func appendThrowAwareInstructions(
        _ loweredInstructions: KIRLoweringEmitContext,
        exceptionSlot: KIRExprID,
        exceptionTypeSlot: KIRExprID,
        thrownTarget: Int32,
        sema: SemaModule,
        arena: KIRArena,
        emit instructions: inout KIRLoweringEmitContext
    ) {
        appendThrowAwareInstructions(
            Array(loweredInstructions),
            exceptionSlot: exceptionSlot,
            exceptionTypeSlot: exceptionTypeSlot,
            thrownTarget: thrownTarget,
            sema: sema,
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
        switch interner.resolve(typeName) {
        case "Int":
            return sema.types.make(.primitive(.int, .nonNull))
        case "Long":
            return sema.types.make(.primitive(.long, .nonNull))
        case "Float":
            return sema.types.make(.primitive(.float, .nonNull))
        case "Double":
            return sema.types.make(.primitive(.double, .nonNull))
        case "Boolean":
            return sema.types.make(.primitive(.boolean, .nonNull))
        case "Char":
            return sema.types.make(.primitive(.char, .nonNull))
        case "String":
            return sema.types.make(.primitive(.string, .nonNull))
        case "UInt":
            return sema.types.make(.primitive(.uint, .nonNull))
        case "ULong":
            return sema.types.make(.primitive(.ulong, .nonNull))
        case "UByte":
            return sema.types.make(.primitive(.ubyte, .nonNull))
        case "UShort":
            return sema.types.make(.primitive(.ushort, .nonNull))
        case "Any":
            return sema.types.anyType
        case "Unit":
            return sema.types.unitType
        case "Nothing":
            return sema.types.nothingType
        default:
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
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
        }
    }

    func isCatchAllType(_ type: TypeID, sema: SemaModule) -> Bool {
        type == sema.types.anyType || type == sema.types.nullableAnyType
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
        let name = interner.resolve(symbol.name)
        return name == "Throwable" || name == "Exception"
    }

    func isCancellationExceptionType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return interner.resolve(symbol.name) == "CancellationException"
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
