extension OverloadResolver {
    func checkForUninferredTypeVariables(
        signature: FunctionSignature,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        range: SourceRange,
        typeSystem: TypeSystem
    ) -> Diagnostic? {
        for typeParamSymbol in signature.typeParameterSymbols {
            guard let typeVar = typeVarBySymbol[typeParamSymbol] else {
                continue
            }
            let resolved = substitution[typeVar]
            // A type variable is "uninferred" when it was either never
            // included in the substitution (no constraints at all) or the
            // solver explicitly set it to errorType.
            guard resolved == nil || resolved == typeSystem.errorType else {
                continue
            }
            // Only report for type parameters that actually appear in the
            // return type or parameter types. Unused type parameters
            // (e.g. `fun <T, U> foo(x: T): T` where U is never used)
            // are silently ignored.
            let usedInReturn = containsTypeVariable(
                signature.returnType,
                typeVarBySymbol: [typeParamSymbol: typeVar],
                typeSystem: typeSystem
            )
            let usedInParams = signature.parameterTypes.contains {
                containsTypeVariable(
                    $0,
                    typeVarBySymbol: [typeParamSymbol: typeVar],
                    typeSystem: typeSystem
                )
            }
            if usedInReturn || usedInParams {
                return Diagnostic(
                    severity: .error,
                    code: "KSWIFTK-SEMA-INFER",
                    message: "Cannot infer type argument; provide explicit type arguments.",
                    primaryRange: range,
                    secondaryRanges: []
                )
            }
        }
        return nil
    }

    func checkTypeParameterBounds(
        signature: FunctionSignature,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        range: SourceRange,
        ctx: SemaModule
    ) -> Diagnostic? {
        for (index, typeParamSymbol) in signature.typeParameterSymbols.enumerated() {
            let upperBound: TypeID?
            if index < signature.typeParameterUpperBounds.count {
                upperBound = signature.typeParameterUpperBounds[index]
            } else {
                upperBound = ctx.symbols.typeParameterUpperBound(for: typeParamSymbol)
            }
            guard let bound = upperBound else { continue }
            guard let typeVar = typeVarBySymbol[typeParamSymbol],
                  let substitutedType = substitution[typeVar] else {
                continue
            }
            if !ctx.types.isSubtype(substitutedType, bound) {
                return Diagnostic(
                    severity: .error,
                    code: "KSWIFTK-SEMA-0030",
                    message: "Type argument does not satisfy upper bound constraint.",
                    primaryRange: range,
                    secondaryRanges: []
                )
            }
        }
        return nil
    }

}
