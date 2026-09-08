/// Rebind expression IDs from imported inline KIR bodies to the consumer arena.
///
/// Inline KIR artifacts intentionally do not serialize expression kinds or
/// types.  The importer therefore shifts their IDs out of the consumer arena,
/// which keeps accidental ID aliasing from changing semantics.  Before
/// inlining, give every imported body ID a fresh consumer expression while
/// recovering only the concrete Boolean result needed by callback invokes.
enum ImportedInlineKIRMaterializer {
    private static let callbackInvokeNames: Set<String> = [
        "kk_function_invoke",
        "kk_function_invoke_0",
        "kk_function_invoke_2",
        "kk_function_invoke_3",
        "kk_function_invoke_4",
        "kk_suspend_function_invoke",
        "kk_suspend_function_invoke_0",
        "kk_suspend_function_invoke_2",
    ]

    static func materialize(
        importedFunctions: inout [SymbolID: KIRFunction],
        arena: KIRArena,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for symbol in importedFunctions.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard var function = importedFunctions[symbol] else { continue }

            let concreteBooleanResults = inferConcreteBooleanInvokeResults(
                in: function,
                types: types,
                interner: interner
            )
            var sourceToConsumer: [KIRExprID: KIRExprID] = [:]

            func remap(_ source: KIRExprID) -> KIRExprID {
                if let existing = sourceToConsumer[source] {
                    return existing
                }
                // Imported bodies may carry exception-slot IDs that are only
                // observed by an implicit throw check and have no defining
                // instruction in the lowered body.  Keep their historical
                // unresolved-value fallback at zero while still giving every
                // ID a consumer-arena entry for type recovery and remapping.
                let consumer = arena.appendExpr(.temporary(0))
                sourceToConsumer[source] = consumer
                return consumer
            }

            let body = function.body.map { remapInstruction($0, using: remap) }
            function.replaceBody(body)
            for (source, type) in concreteBooleanResults {
                if let consumer = sourceToConsumer[source] {
                    arena.setExprType(type, for: consumer)
                }
            }
            importedFunctions[symbol] = function
        }
    }

    private static func inferConcreteBooleanInvokeResults(
        in function: KIRFunction,
        types: TypeSystem,
        interner: StringInterner
    ) -> [KIRExprID: TypeID] {
        let parameterTypes = Dictionary(
            uniqueKeysWithValues: function.params.map { ($0.symbol, $0.type) }
        )
        var expressionTypes: [KIRExprID: TypeID] = [:]
        var resultTypes: [KIRExprID: TypeID] = [:]

        func invalidate(_ id: KIRExprID) {
            expressionTypes.removeValue(forKey: id)
            resultTypes.removeValue(forKey: id)
        }

        for instruction in function.body {
            switch instruction {
            case let .constValue(result, value):
                invalidate(result)
                guard case let .symbolRef(symbol) = value else { continue }
                if let type = parameterTypes[symbol] {
                    expressionTypes[result] = type
                }

            case let .copy(from, to):
                let sourceType = expressionTypes[from]
                invalidate(to)
                if let sourceType {
                    expressionTypes[to] = sourceType
                }

            case let .binary(_, _, _, result), let .unary(_, _, result), let .nullAssert(_, result),
                 let .loadGlobal(result, _):
                invalidate(result)

            case let .call(_, callee, arguments, result, _, thrownResult, _, _):
                if let thrownResult {
                    invalidate(thrownResult)
                }
                guard let result else { continue }
                invalidate(result)
                if callbackInvokeNames.contains(interner.resolve(callee)),
                   let callback = arguments.first,
                   let callbackType = expressionTypes[callback],
                   case let .functionType(functionType) = types.kind(of: callbackType),
                   case .primitive(.boolean, .nonNull) = types.kind(of: functionType.returnType)
                {
                    expressionTypes[result] = functionType.returnType
                    resultTypes[result] = functionType.returnType
                }

            case let .virtualCall(_, _, _, _, result, _, thrownResult, _):
                if let result {
                    invalidate(result)
                }
                if let thrownResult {
                    invalidate(thrownResult)
                }

            default:
                break
            }
        }
        return resultTypes
    }

    private static func remapInstruction(
        _ instruction: KIRInstruction,
        using remap: (KIRExprID) -> KIRExprID
    ) -> KIRInstruction {
        switch instruction {
        case .nop, .beginBlock, .endBlock, .label, .jump, .returnUnit,
             .beginFinallyGuard, .endFinallyGuard:
            return instruction
        case let .jumpIfEqual(lhs, rhs, target):
            return .jumpIfEqual(lhs: remap(lhs), rhs: remap(rhs), target: target)
        case let .constValue(result, value):
            return .constValue(result: remap(result), value: value)
        case let .binary(op, lhs, rhs, result):
            return .binary(op: op, lhs: remap(lhs), rhs: remap(rhs), result: remap(result))
        case let .unary(op, operand, result):
            return .unary(op: op, operand: remap(operand), result: remap(result))
        case let .nullAssert(operand, result):
            return .nullAssert(operand: remap(operand), result: remap(result))
        case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
            return .call(
                symbol: symbol,
                callee: callee,
                arguments: arguments.map(remap),
                result: result.map(remap),
                canThrow: canThrow,
                thrownResult: thrownResult.map(remap),
                isSuperCall: isSuperCall,
                qualifiedSuperType: qualifiedSuperType
            )
        case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
            return .virtualCall(
                symbol: symbol,
                callee: callee,
                receiver: remap(receiver),
                arguments: arguments.map(remap),
                result: result.map(remap),
                canThrow: canThrow,
                thrownResult: thrownResult.map(remap),
                dispatch: dispatch
            )
        case let .jumpIfNotNull(value, target):
            return .jumpIfNotNull(value: remap(value), target: target)
        case let .copy(from, to):
            return .copy(from: remap(from), to: remap(to))
        case let .storeGlobal(value, symbol):
            return .storeGlobal(value: remap(value), symbol: symbol)
        case let .loadGlobal(result, symbol):
            return .loadGlobal(result: remap(result), symbol: symbol)
        case let .rethrow(value):
            return .rethrow(value: remap(value))
        case let .returnIfEqual(lhs, rhs):
            return .returnIfEqual(lhs: remap(lhs), rhs: remap(rhs))
        case let .returnValue(value):
            return .returnValue(remap(value))
        case let .nonLocalReturn(value):
            return .nonLocalReturn(value.map(remap))
        }
    }
}
