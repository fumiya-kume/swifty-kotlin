import Foundation

// Typealias expansion and substitution helpers.

extension TypeCheckHelpers {
    /// Maximum depth for recursive typealias expansion to prevent infinite loops.
    static let maxAliasExpansionDepth = 32

    /// Expand a typealias symbol to its underlying type, substituting type arguments.
    /// Handles generic aliases, cycle detection, and depth limiting.
    // swiftlint:disable:next function_body_length
    func expandTypeAlias(
        _ symbolID: SymbolID,
        typeArgs: [TypeArg],
        sema: SemaModule,
        visited: Set<SymbolID>,
        depth: Int,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID? {
        // Cycle detection
        guard !visited.contains(symbolID) else {
            diagnostics?.error(
                "KSWIFTK-SEMA-ALIAS-CYCLE",
                "Cyclic typealias definition detected.",
                range: sema.symbols.symbol(symbolID)?.declSite
            )
            return nil
        }
        // Depth limit
        guard depth < TypeCheckHelpers.maxAliasExpansionDepth else {
            diagnostics?.error(
                "KSWIFTK-SEMA-ALIAS-DEPTH",
                "Typealias expansion exceeded maximum depth of \(TypeCheckHelpers.maxAliasExpansionDepth).",
                range: sema.symbols.symbol(symbolID)?.declSite
            )
            return nil
        }
        guard let underlying = sema.symbols.typeAliasUnderlyingType(for: symbolID) else {
            return nil
        }
        // Substitute type parameters
        let expanded = substituteTypeAliasParamsForTypeCheck(
            underlying,
            aliasSymbol: symbolID,
            typeArgs: typeArgs,
            sema: sema,
            diagnostics: diagnostics
        )
        // Validate variance constraints after expansion
        validateVarianceAfterExpansion(
            expanded, aliasSymbol: symbolID, typeArgs: typeArgs,
            sema: sema, diagnostics: diagnostics
        )
        // If expanded type is itself a typealias, continue expansion
        if case let .classType(classType) = sema.types.kind(of: expanded),
           let targetSymbol = sema.symbols.symbol(classType.classSymbol),
           targetSymbol.kind == .typeAlias
        { // swiftlint:disable:this opening_brace
            var newVisited = visited
            newVisited.insert(symbolID)
            let chainArgs = classType.args
            if let resolved = expandTypeAlias(
                classType.classSymbol,
                typeArgs: chainArgs,
                sema: sema,
                visited: newVisited,
                depth: depth + 1,
                diagnostics: diagnostics
            ) {
                if classType.nullability == .nullable {
                    return applyNullabilityForTypeCheck(resolved, types: sema.types)
                }
                return resolved
            }
            return nil
        }
        return expanded
    }

    /// Substitute type alias type parameters with provided type arguments.
    func substituteTypeAliasParamsForTypeCheck(
        _ typeID: TypeID,
        aliasSymbol: SymbolID,
        typeArgs: [TypeArg],
        sema: SemaModule,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        let typeParamSymbols = sema.symbols.typeAliasTypeParameters(for: aliasSymbol)
        if typeParamSymbols.isEmpty {
            if !typeArgs.isEmpty {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0062",
                    "Type argument count mismatch: expected 0 but got \(typeArgs.count).",
                    range: nil
                )
            }
            return typeID
        }
        if typeArgs.count != typeParamSymbols.count {
            diagnostics?.error(
                "KSWIFTK-SEMA-0062",
                "Type argument count mismatch: expected \(typeParamSymbols.count) but got \(typeArgs.count).",
                range: nil
            )
        }
        var argSubstitution: [SymbolID: TypeArg] = [:]
        for (index, paramSymbol) in typeParamSymbols.enumerated() {
            guard index < typeArgs.count else { break }
            argSubstitution[paramSymbol] = typeArgs[index]
        }
        guard !argSubstitution.isEmpty else {
            return typeID
        }
        return applyAliasSubstitution(typeID, argSubstitution: argSubstitution, sema: sema)
    }

    /// Recursively apply type argument substitution to a type.
    // swiftlint:disable:next cyclomatic_complexity
    func applyAliasSubstitution(
        _ typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeID {
        let types = sema.types
        switch types.kind(of: typeID) {
        case let .typeParam(typeParam):
            if let replacement = argSubstitution[typeParam.symbol] {
                let replacementType: TypeID = switch replacement {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    inner
                case .star:
                    types.nullableAnyType
                }
                if typeParam.nullability == .nullable {
                    return applyNullabilityForTypeCheck(replacementType, types: types)
                }
                return replacementType
            }
            return typeID
        case let .classType(clsType):
            let newArgs = clsType.args.map { arg -> TypeArg in
                substituteAliasArg(arg, argSubstitution: argSubstitution, sema: sema)
            }
            if newArgs == clsType.args { return typeID }
            return types.make(.classType(ClassType(
                classSymbol: clsType.classSymbol, args: newArgs, nullability: clsType.nullability
            )))
        case let .functionType(fnType):
            let newReceiver = fnType.receiver.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            let newParams = fnType.params.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            let newReturn = applyAliasSubstitution(
                fnType.returnType, argSubstitution: argSubstitution, sema: sema
            )
            if newReceiver == fnType.receiver, newParams == fnType.params, newReturn == fnType.returnType {
                return typeID
            }
            return types.make(.functionType(FunctionType(
                receiver: newReceiver, params: newParams, returnType: newReturn,
                isSuspend: fnType.isSuspend, nullability: fnType.nullability
            )))
        case let .intersection(parts):
            let newParts = parts.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            if newParts == parts { return typeID }
            return types.make(.intersection(newParts))
        default:
            return typeID
        }
    }
}
