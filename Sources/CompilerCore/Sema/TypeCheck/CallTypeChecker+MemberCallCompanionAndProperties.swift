import Foundation

extension CallTypeChecker {
    func resolveClassNameMemberValue(
        ownerNominalSymbol: SymbolID,
        memberName: InternedString,
        sema: SemaModule
    ) -> (symbol: SymbolID, type: TypeID)? {
        guard let owner = sema.symbols.symbol(ownerNominalSymbol) else {
            return nil
        }
        let memberFQName = owner.fqName + [memberName]
        var candidates = sema.symbols.lookupAll(fqName: memberFQName).sorted(by: { $0.rawValue < $1.rawValue })
        if candidates.isEmpty {
            candidates = sema.symbols.lookupByShortName(memberName)
                .filter { candidate in
                    sema.symbols.parentSymbol(for: candidate) == ownerNominalSymbol
                }
                .sorted(by: { $0.rawValue < $1.rawValue })
        }
        for candidate in candidates {
            guard let candidateSymbol = sema.symbols.symbol(candidate) else {
                continue
            }
            switch candidateSymbol.kind {
            case .field:
                if let fieldType = sema.symbols.propertyType(for: candidate) {
                    return (candidate, fieldType)
                }
            case .object:
                let objectType = sema.types.make(.classType(ClassType(
                    classSymbol: candidate,
                    args: [],
                    nullability: .nonNull
                )))
                return (candidate, objectType)
            default:
                continue
            }
        }
        return nil
    }

    func resolveExtensionPropertyGetter(
        id: ExprID,
        calleeName: InternedString,
        range: SourceRange,
        receiverType: TypeID,
        expectedType: TypeID?,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let visible = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        var getterCandidates: [SymbolID] = []
        for candidate in visible {
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .property,
                  sema.symbols.extensionPropertyReceiverType(for: candidate) != nil,
                  let getterAccessor = sema.symbols.extensionPropertyGetterAccessor(for: candidate)
            else {
                continue
            }
            getterCandidates.append(getterAccessor)
        }
        guard !getterCandidates.isEmpty else {
            return nil
        }

        let resolved = ctx.resolver.resolveCall(
            candidates: getterCandidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: []
            ),
            expectedType: expectedType,
            implicitReceiverType: receiverType,
            ctx: ctx.semaCtx
        )
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            return nil
        }
        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map(\.value),
                parameterMapping: resolved.parameterMapping
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        if let ownerProperty = sema.symbols.accessorOwnerProperty(for: chosen) {
            sema.bindings.bindIdentifier(id, symbol: ownerProperty)
        }
        guard let signature = sema.symbols.functionSignature(for: chosen) else {
            return sema.types.anyType
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        return sema.types.substituteTypeParameters(
            in: signature.returnType,
            substitution: resolved.substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
    }
}
