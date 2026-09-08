#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ImportedInlineKIRMaterializerTests {
    @Test
    func remapsEachImportedBodyIndependentlyAndBindsConcreteBooleanResult() {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let callbackSymbol = SymbolID(rawValue: -200_001)
        let producerExpr = KIRExprID(rawValue: 4_900_000)
        let producerResult = KIRExprID(rawValue: 4_900_001)
        let invoke = interner.intern("kk_function_invoke")

        let booleanCallback = types.make(.functionType(FunctionType(
            params: [types.charType],
            returnType: types.booleanType
        )))
        let nullableBooleanCallback = types.make(.functionType(FunctionType(
            params: [types.charType],
            returnType: types.make(.primitive(.boolean, .nullable))
        )))
        let genericCallback = types.make(.functionType(FunctionType(
            params: [types.charType],
            returnType: types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 91))))
        )))

        func makeFunction(symbol: SymbolID, callbackType: TypeID) -> KIRFunction {
            let locations: [SourceRange?] = [nil, nil, nil]
            return KIRFunction(
                symbol: symbol,
                name: interner.intern("imported_\(symbol.rawValue)"),
                params: [KIRParameter(symbol: callbackSymbol, type: callbackType)],
                returnType: types.booleanType,
                body: [
                    .constValue(result: producerExpr, value: .symbolRef(callbackSymbol)),
                    .call(
                        symbol: nil,
                        callee: invoke,
                        arguments: [producerExpr],
                        result: producerResult,
                        canThrow: false,
                        thrownResult: nil
                    ),
                    .returnValue(producerResult),
                ],
                isSuspend: false,
                isInline: true,
                sourceRange: nil,
                instructionLocations: locations
            )
        }

        var imported: [SymbolID: KIRFunction] = [
            SymbolID(rawValue: 1): makeFunction(symbol: SymbolID(rawValue: 1), callbackType: booleanCallback),
            SymbolID(rawValue: 2): makeFunction(symbol: SymbolID(rawValue: 2), callbackType: nullableBooleanCallback),
            SymbolID(rawValue: 3): makeFunction(symbol: SymbolID(rawValue: 3), callbackType: genericCallback),
            SymbolID(rawValue: 4): makeFunction(symbol: SymbolID(rawValue: 4), callbackType: types.anyType),
        ]

        ImportedInlineKIRMaterializer.materialize(
            importedFunctions: &imported,
            arena: arena,
            types: types,
            interner: interner
        )

        let booleanBody = imported[SymbolID(rawValue: 1)]!.body
        let nullableBody = imported[SymbolID(rawValue: 2)]!.body
        let genericBody = imported[SymbolID(rawValue: 3)]!.body
        let unknownBody = imported[SymbolID(rawValue: 4)]!.body
        let booleanResult = resultID(in: booleanBody[1])
        let nullableResult = resultID(in: nullableBody[1])
        let genericResult = resultID(in: genericBody[1])
        let unknownResult = resultID(in: unknownBody[1])

        #expect(booleanResult != nullableResult)
        #expect(arena.expr(booleanResult) != nil)
        #expect(arena.expr(nullableResult) != nil)
        #expect(arena.exprType(booleanResult) == types.booleanType)
        #expect(arena.exprType(nullableResult) == nil)
        #expect(arena.exprType(genericResult) == nil)
        #expect(arena.exprType(unknownResult) == nil)
        #expect(imported[SymbolID(rawValue: 1)]!.instructionLocations == [nil, nil, nil])
        #expect(imported[SymbolID(rawValue: 2)]!.instructionLocations == [nil, nil, nil])

        for function in imported.values {
            for instruction in function.body {
                for id in expressionIDs(instruction) {
                    #expect(arena.expr(id) != nil)
                }
            }
        }
    }

    @Test
    func clearsInferredResultTypeWhenAProducerIDIsRedefined() {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let callbackSymbol = SymbolID(rawValue: -200_020)
        let callbackExpr = KIRExprID(rawValue: 4_900_200)
        let resultExpr = KIRExprID(rawValue: 4_900_201)
        let invoke = interner.intern("kk_function_invoke")
        let callbackType = types.make(.functionType(FunctionType(
            params: [types.charType],
            returnType: types.booleanType
        )))

        func makeFunction(
            symbol: SymbolID,
            redefinition: (KIRExprID, KIRExprID) -> KIRInstruction
        ) -> KIRFunction {
            KIRFunction(
                symbol: symbol,
                name: interner.intern("redefined_\(symbol.rawValue)"),
                params: [KIRParameter(symbol: callbackSymbol, type: callbackType)],
                returnType: types.booleanType,
                body: [
                    .constValue(result: callbackExpr, value: .symbolRef(callbackSymbol)),
                    .call(
                        symbol: nil,
                        callee: invoke,
                        arguments: [callbackExpr],
                        result: resultExpr,
                        canThrow: false,
                        thrownResult: nil
                    ),
                    redefinition(callbackExpr, resultExpr),
                    .returnValue(resultExpr),
                ],
                isSuspend: false,
                isInline: true
            )
        }

        let symbols = (1...4).map { SymbolID(rawValue: Int32($0)) }
        var imported: [SymbolID: KIRFunction] = [
            symbols[0]: makeFunction(symbol: symbols[0]) { _, result in
                .constValue(result: result, value: .boolLiteral(false))
            },
            symbols[1]: makeFunction(symbol: symbols[1]) { source, result in
                .copy(from: source, to: result)
            },
            symbols[2]: makeFunction(symbol: symbols[2]) { source, result in
                .binary(op: .equal, lhs: source, rhs: source, result: result)
            },
            symbols[3]: makeFunction(symbol: symbols[3]) { source, result in
                .virtualCall(
                    symbol: nil,
                    callee: interner.intern("redefinition"),
                    receiver: source,
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .vtable(slot: 0)
                )
            },
        ]

        ImportedInlineKIRMaterializer.materialize(
            importedFunctions: &imported,
            arena: arena,
            types: types,
            interner: interner
        )

        for symbol in symbols {
            guard case let .call(_, _, _, result, _, _, _, _) = imported[symbol]!.body[1],
                  let result
            else {
                Issue.record("Expected an invoke result")
                continue
            }
            #expect(arena.exprType(result) == nil)
        }
    }

    @Test
    func remapsAllInstructionOperandsWithoutChangingNonExpressionFields() {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let symbol = SymbolID(rawValue: 10)
        let callbackSymbol = SymbolID(rawValue: -200_010)
        let ids = (0..<18).map { KIRExprID(rawValue: 4_900_100 + Int32($0)) }
        let callee = interner.intern("kk_function_invoke")
        let virtualCallee = interner.intern("virtual_callee")
        let callbackType = types.make(.functionType(FunctionType(
            params: [types.charType],
            returnType: types.booleanType
        )))
        let body: [KIRInstruction] = [
            .label(6),
            .jumpIfEqual(lhs: ids[0], rhs: ids[1], target: 7),
            .constValue(result: ids[2], value: .symbolRef(callbackSymbol)),
            .binary(op: .equal, lhs: ids[2], rhs: ids[3], result: ids[4]),
            .unary(op: .not, operand: ids[4], result: ids[5]),
            .nullAssert(operand: ids[5], result: ids[6]),
            .call(
                symbol: symbol,
                callee: callee,
                arguments: [ids[2]],
                result: ids[7],
                canThrow: true,
                thrownResult: ids[8],
                isSuperCall: true,
                qualifiedSuperType: symbol
            ),
            .virtualCall(
                symbol: symbol,
                callee: virtualCallee,
                receiver: ids[9],
                arguments: [ids[10]],
                result: ids[11],
                canThrow: true,
                thrownResult: ids[12],
                dispatch: .itableDynamic(interfaceTypeID: 3, methodSlot: 4)
            ),
            .jumpIfNotNull(value: ids[13], target: 8),
            .copy(from: ids[14], to: ids[15]),
            .storeGlobal(value: ids[15], symbol: symbol),
            .loadGlobal(result: ids[16], symbol: symbol),
            .rethrow(value: ids[16]),
            .returnIfEqual(lhs: ids[16], rhs: ids[17]),
            .returnValue(ids[17]),
            .nonLocalReturn(ids[0]),
        ]
        let function = KIRFunction(
            symbol: symbol,
            name: interner.intern("all_operands"),
            params: [KIRParameter(symbol: callbackSymbol, type: callbackType)],
            returnType: types.booleanType,
            body: body,
            isSuspend: false,
            isInline: true,
            instructionLocations: Array(repeating: nil, count: body.count)
        )
        var imported = [symbol: function]

        ImportedInlineKIRMaterializer.materialize(
            importedFunctions: &imported,
            arena: arena,
            types: types,
            interner: interner
        )

        let remapped = imported[symbol]!
        #expect(remapped.body.count == body.count)
        #expect(remapped.instructionLocations.count == body.count)
        #expect(remapped.body[0] == .label(6))
        #expect(arena.expressions.count >= Set(ids).count)
        for instruction in remapped.body {
            for id in expressionIDs(instruction) {
                #expect(arena.expr(id) != nil)
            }
        }
        if case let .call(callSymbol, callCallee, _, _, canThrow, _, isSuperCall, qualifiedSuperType) = remapped.body[6] {
            #expect(callSymbol == symbol)
            #expect(callCallee == callee)
            #expect(canThrow)
            #expect(isSuperCall)
            #expect(qualifiedSuperType == symbol)
        } else {
            Issue.record("Expected the call instruction to remain a call")
        }
    }

    @Test
    func keepsZeroFallbackForUnresolvedImportedThrowCheckSlot() {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let symbol = SymbolID(rawValue: 11)
        let definedID = KIRExprID(rawValue: 4_900_300)
        let unresolvedThrowSlot = KIRExprID(rawValue: 4_900_301)
        let function = KIRFunction(
            symbol: symbol,
            name: interner.intern("unresolved_throw_slot"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: definedID, value: .unit),
                // A serialized body can retain a throw-check operand whose
                // defining exception channel is supplied only by codegen.
                .jumpIfNotNull(value: unresolvedThrowSlot, target: 1),
                .returnValue(definedID),
            ],
            isSuspend: false,
            isInline: true
        )
        var imported = [symbol: function]

        ImportedInlineKIRMaterializer.materialize(
            importedFunctions: &imported,
            arena: arena,
            types: types,
            interner: interner
        )

        guard case let .constValue(remappedDefinedID, _) = imported[symbol]!.body[0],
              case let .jumpIfNotNull(remappedThrowSlot, _) = imported[symbol]!.body[1]
        else {
            Issue.record("Expected remapped constant and throw-check instructions")
            return
        }
        #expect(remappedDefinedID != remappedThrowSlot)
        guard case let .temporary(definedFallback) = arena.expr(remappedDefinedID),
              case let .temporary(throwFallback) = arena.expr(remappedThrowSlot)
        else {
            Issue.record("Expected materialized temporary expressions")
            return
        }
        #expect(definedFallback == 0)
        #expect(throwFallback == 0)
    }

    private func resultID(in instruction: KIRInstruction) -> KIRExprID {
        guard case let .call(_, _, _, result, _, _, _, _) = instruction,
              let result
        else {
            Issue.record("Expected a call result")
            return .invalid
        }
        return result
    }

    private func expressionIDs(_ instruction: KIRInstruction) -> [KIRExprID] {
        switch instruction {
        case .nop, .beginBlock, .endBlock, .label, .jump, .returnUnit,
             .beginFinallyGuard, .endFinallyGuard:
            return []
        case let .jumpIfEqual(lhs, rhs, _):
            return [lhs, rhs]
        case let .constValue(result, _):
            return [result]
        case let .binary(_, lhs, rhs, result):
            return [lhs, rhs, result]
        case let .unary(_, operand, result), let .nullAssert(operand, result):
            return [operand, result]
        case let .call(_, _, arguments, result, _, thrownResult, _, _):
            var ids = arguments
            if let result { ids.append(result) }
            if let thrownResult { ids.append(thrownResult) }
            return ids
        case let .virtualCall(_, _, receiver, arguments, result, _, thrownResult, _):
            var ids = [receiver] + arguments
            if let result { ids.append(result) }
            if let thrownResult { ids.append(thrownResult) }
            return ids
        case let .jumpIfNotNull(value, _):
            return [value]
        case let .copy(from, to):
            return [from, to]
        case let .storeGlobal(value, _):
            return [value]
        case let .loadGlobal(result, _):
            return [result]
        case let .rethrow(value):
            return [value]
        case let .returnIfEqual(lhs, rhs):
            return [lhs, rhs]
        case let .returnValue(value):
            return [value]
        case let .nonLocalReturn(value):
            return value.map { [$0] } ?? []
        }
    }
}
#endif
