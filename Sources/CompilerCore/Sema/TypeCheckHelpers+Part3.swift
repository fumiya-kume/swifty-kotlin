import Foundation

// Type alias substitution and expansion helpers.
// Split from TypeCheckHelpers.swift to stay within type-body-length limits.

extension TypeCheckHelpers {
    /// Maximum depth for recursive typealias expansion to prevent infinite loops.
    static let maxAliasExpansionDepth = 32

    // swiftlint:disable:next function_body_length
    /// Expand a typealias symbol to its underlying type, substituting type arguments.
    /// Handles generic aliases, cycle detection, and depth limiting.
    func expandTypeAlias(
        _ symbolID: SymbolID,
        typeArgs: [TypeArg],
        sema: SemaModule,
        visited: Set<SymbolID>,
        depth: Int,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID? {
        guard !visited.contains(symbolID) else {
            diagnostics?.error(
                "KSWIFTK-SEMA-ALIAS-CYCLE",
                "Cyclic typealias definition detected.",
                range: sema.symbols.symbol(symbolID)?.declSite
            )
            return nil
        }
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
        let expanded = substituteTypeAliasParamsForTypeCheck(
            underlying,
            aliasSymbol: symbolID,
            typeArgs: typeArgs,
            sema: sema,
            diagnostics: diagnostics
        )
        validateVarianceAfterExpansion(
            expanded, aliasSymbol: symbolID, typeArgs: typeArgs,
            sema: sema, diagnostics: diagnostics
        )
        if case let .classType(classType) = sema.types.kind(of: expanded),
           let targetSymbol = sema.symbols.symbol(classType.classSymbol),
           targetSymbol.kind == .typeAlias
        {
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
    func applyAliasSubstitution(
        _ typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeID {
        let types = sema.types
        switch types.kind(of: typeID) {
        case let .typeParam(typeParam):
            return substituteTypeParam(typeParam, typeID: typeID, argSubstitution: argSubstitution, types: types)
        case let .classType(classType):
            return substituteClassType(classType, typeID: typeID, argSubstitution: argSubstitution, sema: sema)
        case let .functionType(funcType):
            return substituteFuncType(funcType, typeID: typeID, argSubstitution: argSubstitution, sema: sema)
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

    /// Handle type parameter substitution in alias expansion.
    private func substituteTypeParam(
        _ typeParam: TypeParamType,
        typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        types: TypeSystem
    ) -> TypeID {
        guard let replacement = argSubstitution[typeParam.symbol] else {
            return typeID
        }
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

    /// Handle class type substitution in alias expansion.
    private func substituteClassType(
        _ classType: ClassType,
        typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeID {
        let newArgs = classType.args.map { arg -> TypeArg in
            substituteAliasArg(arg, argSubstitution: argSubstitution, sema: sema)
        }
        if newArgs == classType.args { return typeID }
        return sema.types.make(.classType(ClassType(
            classSymbol: classType.classSymbol, args: newArgs, nullability: classType.nullability
        )))
    }

    /// Handle function type substitution in alias expansion.
    private func substituteFuncType(
        _ funcType: FunctionType,
        typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeID {
        let newReceiver = funcType.receiver.map {
            applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
        }
        let newParams = funcType.params.map {
            applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
        }
        let newReturn = applyAliasSubstitution(
            funcType.returnType, argSubstitution: argSubstitution, sema: sema
        )
        if newReceiver == funcType.receiver, newParams == funcType.params, newReturn == funcType.returnType {
            return typeID
        }
        return sema.types.make(.functionType(FunctionType(
            receiver: newReceiver, params: newParams, returnType: newReturn,
            isSuspend: funcType.isSuspend, nullability: funcType.nullability
        )))
    }
}
