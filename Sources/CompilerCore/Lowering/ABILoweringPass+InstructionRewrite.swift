import Foundation

extension ABILoweringPass {
    func applyArgumentBoxing(
        arguments: [KIRExprID],
        signature: FunctionSignature,
        receiverOffset: Int,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        boxIntCallee: InternedString,
        boxBoolCallee: InternedString,
        boxLongCallee: InternedString,
        boxFloatCallee: InternedString,
        boxDoubleCallee: InternedString,
        boxCharCallee: InternedString,
        newBody: inout [KIRInstruction]
    ) -> [KIRExprID] {
        var boxedArguments = arguments
        let parameterTypes = signature.parameterTypes
        let varargFlags = signature.valueParameterIsVararg
        for argIndex in arguments.indices {
            let paramIndex = argIndex - receiverOffset
            guard paramIndex >= 0, paramIndex < parameterTypes.count else {
                continue
            }
            if paramIndex < varargFlags.count, varargFlags[paramIndex] {
                continue
            }
            let paramType = parameterTypes[paramIndex]
            let argType = intrinsicArgType(arguments[argIndex], arena: module.arena, types: types)
            guard let argType else {
                continue
            }
            if let boxCallee = boxingCallee(
                argType: argType,
                paramType: paramType,
                types: types,
                boxIntCallee: boxIntCallee,
                boxBoolCallee: boxBoolCallee,
                boxLongCallee: boxLongCallee,
                boxFloatCallee: boxFloatCallee,
                boxDoubleCallee: boxDoubleCallee,
                boxCharCallee: boxCharCallee,
                symbols: symbols
            ) {
                let boxedResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: paramType
                )
                newBody.append(.call(
                    symbol: nil,
                    callee: boxCallee,
                    arguments: [arguments[argIndex]],
                    result: boxedResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                boxedArguments[argIndex] = boxedResult
            }
        }
        return boxedArguments
    }

    func resolveUnboxForCall(
        callSymbol: SymbolID?,
        callee: InternedString,
        result: KIRExprID?,
        signatureByName: [InternedString: FunctionSignature],
        module: KIRModule,
        types: TypeSystem?,
        symbols: SymbolTable?,
        unboxIntCallee: InternedString,
        unboxBoolCallee: InternedString,
        unboxLongCallee: InternedString,
        unboxFloatCallee: InternedString,
        unboxDoubleCallee: InternedString,
        unboxCharCallee: InternedString
    ) -> (InternedString, TypeID)? {
        guard let types, let result else { return nil }
        var returnType: TypeID?
        if let callSymbol {
            returnType = returnTypeForCall(callSymbol: callSymbol, symbols: symbols)
        }
        if returnType == nil {
            returnType = signatureByName[callee]?.returnType
        }
        guard let returnType else { return nil }
        let returnKind = resolveValueClassKind(types.kind(of: returnType), types: types, symbols: symbols)
        let resultType = module.arena.exprType(result)
        guard let resultType else { return nil }
        let resultKind = resolveValueClassKind(types.kind(of: resultType), types: types, symbols: symbols)
        guard needsUnboxing(sourceKind: returnKind, targetKind: resultKind, symbols: symbols) else {
            return nil
        }
        guard let unboxCallee = unboxingCallee(
            sourceKind: returnKind,
            targetKind: resultKind,
            unboxIntCallee: unboxIntCallee,
            unboxBoolCallee: unboxBoolCallee,
            unboxLongCallee: unboxLongCallee,
            unboxFloatCallee: unboxFloatCallee,
            unboxDoubleCallee: unboxDoubleCallee,
            unboxCharCallee: unboxCharCallee,
            types: types,
            symbols: symbols
        ) else {
            return nil
        }
        return (unboxCallee, returnType)
    }

    func returnTypeForCall(
        callSymbol: SymbolID?,
        symbols: SymbolTable?
    ) -> TypeID? {
        guard let callSymbol, let symbols else {
            return nil
        }
        return symbols.functionSignature(for: callSymbol)?.returnType
    }
}
