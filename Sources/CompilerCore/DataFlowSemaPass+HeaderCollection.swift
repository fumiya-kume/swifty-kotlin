import Foundation

extension DataFlowSemaPassPhase {
    func collectHeader(
        declID: DeclID,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        let package = file.packageFQName
        let anyType = types.anyType
        let unitType = types.unitType

        let declaration: (kind: SymbolKind, name: InternedString, range: SourceRange?, visibility: Visibility, flags: SymbolFlags)?
        switch decl {
        case .classDecl(let classDecl):
            declaration = (
                kind: classSymbolKind(for: classDecl),
                name: classDecl.name,
                range: classDecl.range,
                visibility: visibility(from: classDecl.modifiers),
                flags: flags(from: classDecl.modifiers)
            )
        case .interfaceDecl(let interfaceDecl):
            declaration = (
                kind: .interface,
                name: interfaceDecl.name,
                range: interfaceDecl.range,
                visibility: visibility(from: interfaceDecl.modifiers),
                flags: flags(from: interfaceDecl.modifiers)
            )
        case .objectDecl(let objectDecl):
            declaration = (
                kind: .object,
                name: objectDecl.name,
                range: objectDecl.range,
                visibility: visibility(from: objectDecl.modifiers),
                flags: flags(from: objectDecl.modifiers)
            )
        case .funDecl(let funDecl):
            declaration = (
                kind: .function,
                name: funDecl.name,
                range: funDecl.range,
                visibility: visibility(from: funDecl.modifiers),
                flags: flags(from: funDecl.modifiers)
            )
        case .propertyDecl(let propertyDecl):
            var propertyFlags = flags(from: propertyDecl.modifiers)
            if propertyDecl.isVar {
                propertyFlags.insert(.mutable)
            }
            declaration = (
                kind: .property,
                name: propertyDecl.name,
                range: propertyDecl.range,
                visibility: visibility(from: propertyDecl.modifiers),
                flags: propertyFlags
            )
        case .typeAliasDecl(let typeAliasDecl):
            declaration = (
                kind: .typeAlias,
                name: typeAliasDecl.name,
                range: typeAliasDecl.range,
                visibility: visibility(from: typeAliasDecl.modifiers),
                flags: flags(from: typeAliasDecl.modifiers)
            )
        case .enumEntryDecl(let entry):
            declaration = (
                kind: .field,
                name: entry.name,
                range: entry.range,
                visibility: .public,
                flags: []
            )
        }

        guard let declaration else { return }
        let fqName = package + [declaration.name]
        let existingSymbols = symbols.lookupAll(fqName: fqName).compactMap { symbols.symbol($0) }
        if hasDeclarationConflict(newKind: declaration.kind, existing: existingSymbols) {
            diagnostics.error(
                "KSWIFTK-SEMA-0001",
                "Duplicate declaration in the same package scope.",
                range: declaration.range
            )
        }
        let symbol = symbols.define(
            kind: declaration.kind,
            name: declaration.name,
            fqName: fqName,
            declSite: declaration.range,
            visibility: declaration.visibility,
            flags: declaration.flags
        )
        scope.insert(symbol)
        bindings.bindDecl(declID, symbol: symbol)

        switch decl {
        case .classDecl(let classDecl):
            if !classDecl.typeParams.isEmpty {
                types.setNominalTypeParameterVariances(
                    classDecl.typeParams.map(\.variance),
                    for: symbol
                )
            }
            let classType = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            let classScope = ClassMemberScope(
                parent: scope,
                symbols: symbols,
                ownerSymbol: symbol,
                thisType: classType
            )
            collectNestedTypeAliases(
                classDecl.nestedTypeAliases,
                ownerFQName: fqName,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )

            let ctorName = interner.intern("<init>")
            let primaryCtorFQName = fqName + [ctorName]
            let primaryCtorSymbol = symbols.define(
                kind: .constructor,
                name: declaration.name,
                fqName: primaryCtorFQName,
                declSite: classDecl.range,
                visibility: declaration.visibility,
                flags: []
            )
            scope.insert(primaryCtorSymbol)
            symbols.setParentSymbol(symbol, for: primaryCtorSymbol)
            do {
                var paramTypes: [TypeID] = []
                var paramSymbols: [SymbolID] = []
                var paramHasDefaultValues: [Bool] = []
                var paramIsVararg: [Bool] = []
                let localNamespaceFQName = primaryCtorFQName + [interner.intern("$\(primaryCtorSymbol.rawValue)")]
                for valueParam in classDecl.primaryConstructorParams {
                    let paramFQName = localNamespaceFQName + [valueParam.name]
                    let paramSymbol = symbols.define(
                        kind: .valueParameter,
                        name: valueParam.name,
                        fqName: paramFQName,
                        declSite: classDecl.range,
                        visibility: .private,
                        flags: []
                    )
                    let resolvedType = resolveTypeRef(
                        valueParam.type,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        diagnostics: diagnostics
                    ) ?? anyType
                    paramTypes.append(resolvedType)
                    paramSymbols.append(paramSymbol)
                    paramHasDefaultValues.append(valueParam.hasDefaultValue)
                    paramIsVararg.append(valueParam.isVararg)
                }
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: classType,
                        parameterTypes: paramTypes,
                        returnType: classType,
                        valueParameterSymbols: paramSymbols,
                        valueParameterHasDefaultValues: paramHasDefaultValues,
                        valueParameterIsVararg: paramIsVararg
                    ),
                    for: primaryCtorSymbol
                )
            }

            for (ctorIndex, secondaryCtor) in classDecl.secondaryConstructors.enumerated() {
                let secCtorSymbol = symbols.define(
                    kind: .constructor,
                    name: declaration.name,
                    fqName: primaryCtorFQName,
                    declSite: secondaryCtor.range,
                    visibility: visibility(from: secondaryCtor.modifiers),
                    flags: []
                )
                scope.insert(secCtorSymbol)
                symbols.setParentSymbol(symbol, for: secCtorSymbol)
                var paramTypes: [TypeID] = []
                var paramSymbols: [SymbolID] = []
                var paramHasDefaultValues: [Bool] = []
                var paramIsVararg: [Bool] = []
                let localNamespaceFQName = primaryCtorFQName + [interner.intern("$sec\(ctorIndex)_\(secCtorSymbol.rawValue)")]
                for valueParam in secondaryCtor.valueParams {
                    let paramFQName = localNamespaceFQName + [valueParam.name]
                    let paramSymbol = symbols.define(
                        kind: .valueParameter,
                        name: valueParam.name,
                        fqName: paramFQName,
                        declSite: secondaryCtor.range,
                        visibility: .private,
                        flags: []
                    )
                    let resolvedType = resolveTypeRef(
                        valueParam.type,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        diagnostics: diagnostics
                    ) ?? anyType
                    paramTypes.append(resolvedType)
                    paramSymbols.append(paramSymbol)
                    paramHasDefaultValues.append(valueParam.hasDefaultValue)
                    paramIsVararg.append(valueParam.isVararg)
                }
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: classType,
                        parameterTypes: paramTypes,
                        returnType: classType,
                        valueParameterSymbols: paramSymbols,
                        valueParameterHasDefaultValues: paramHasDefaultValues,
                        valueParameterIsVararg: paramIsVararg
                    ),
                    for: secCtorSymbol
                )

            }

            if declaration.kind == .enumClass {
                for entry in classDecl.enumEntries {
                    let entryFQName = fqName + [entry.name]
                    let existingEntrySymbols = symbols.lookupAll(fqName: entryFQName).compactMap { symbols.symbol($0) }
                    if hasDeclarationConflict(newKind: .field, existing: existingEntrySymbols) {
                        diagnostics.error(
                            "KSWIFTK-SEMA-0001",
                            "Duplicate declaration in the same package scope.",
                            range: entry.range
                        )
                    }
                    let entrySymbol = symbols.define(
                        kind: .field,
                        name: entry.name,
                        fqName: entryFQName,
                        declSite: entry.range,
                        visibility: .public,
                        flags: []
                    )
                    symbols.setPropertyType(classType, for: entrySymbol)
                    scope.insert(entrySymbol)
                }
            }
            collectMemberHeaders(
                memberFunctions: classDecl.memberFunctions,
                memberProperties: classDecl.memberProperties,
                nestedClasses: classDecl.nestedClasses,
                nestedObjects: classDecl.nestedObjects,
                ownerFQName: fqName,
                ownerSymbol: symbol,
                ownerType: classType,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: classScope,
                diagnostics: diagnostics,
                interner: interner
            )

        case .interfaceDecl(let interfaceDecl):
            if !interfaceDecl.typeParams.isEmpty {
                types.setNominalTypeParameterVariances(
                    interfaceDecl.typeParams.map(\.variance),
                    for: symbol
                )
            }
            let interfaceType = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            let interfaceScope = ClassMemberScope(
                parent: scope,
                symbols: symbols,
                ownerSymbol: symbol,
                thisType: interfaceType
            )
            collectNestedTypeAliases(
                interfaceDecl.nestedTypeAliases,
                ownerFQName: fqName,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
            collectMemberHeaders(
                memberFunctions: interfaceDecl.memberFunctions,
                memberProperties: interfaceDecl.memberProperties,
                nestedClasses: interfaceDecl.nestedClasses,
                nestedObjects: interfaceDecl.nestedObjects,
                ownerFQName: fqName,
                ownerSymbol: symbol,
                ownerType: interfaceType,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: interfaceScope,
                diagnostics: diagnostics,
                interner: interner
            )

        case .objectDecl(let objectDecl):
            let objectType = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            let objectScope = ClassMemberScope(
                parent: scope,
                symbols: symbols,
                ownerSymbol: symbol,
                thisType: objectType
            )
            collectNestedTypeAliases(
                objectDecl.nestedTypeAliases,
                ownerFQName: fqName,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
            collectMemberHeaders(
                memberFunctions: objectDecl.memberFunctions,
                memberProperties: objectDecl.memberProperties,
                nestedClasses: objectDecl.nestedClasses,
                nestedObjects: objectDecl.nestedObjects,
                ownerFQName: fqName,
                ownerSymbol: symbol,
                ownerType: objectType,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: objectScope,
                diagnostics: diagnostics,
                interner: interner
            )

        case .funDecl(let funDecl):
            var paramTypes: [TypeID] = []
            var paramSymbols: [SymbolID] = []
            var paramHasDefaultValues: [Bool] = []
            var paramIsVararg: [Bool] = []
            var typeParameterSymbols: [SymbolID] = []
            var localTypeParameters: [InternedString: SymbolID] = [:]
            var reifiedIndices: Set<Int> = []
            let localNamespaceFQName = fqName + [interner.intern("$\(symbol.rawValue)")]
            for (index, typeParam) in funDecl.typeParams.enumerated() {
                let typeParamFQName = localNamespaceFQName + [typeParam.name]
                let typeParamFlags: SymbolFlags = typeParam.isReified ? [.reifiedTypeParameter] : []
                let typeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: typeParam.name,
                    fqName: typeParamFQName,
                    declSite: funDecl.range,
                    visibility: .private,
                    flags: typeParamFlags
                )
                typeParameterSymbols.append(typeParamSymbol)
                localTypeParameters[typeParam.name] = typeParamSymbol
                if typeParam.isReified {
                    reifiedIndices.insert(index)
                }
            }
            for typeParam in funDecl.typeParams {
                if let boundRef = typeParam.upperBound,
                   let typeParamSym = localTypeParameters[typeParam.name] {
                    if let boundType = resolveTypeRef(
                        boundRef,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        localTypeParameters: localTypeParameters
                    ) {
                        symbols.setTypeParameterUpperBound(boundType, for: typeParamSym)
                    }
                }
            }
            if !reifiedIndices.isEmpty && !funDecl.isInline {
                diagnostics.error(
                    "KSWIFTK-SEMA-0020",
                    "Only type parameters of inline functions can be reified",
                    range: funDecl.range
                )
            }
            let receiverType = resolveTypeRef(
                funDecl.receiverType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters,
                diagnostics: diagnostics
            )
            for valueParam in funDecl.valueParams {
                let paramFQName = localNamespaceFQName + [valueParam.name]
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: valueParam.name,
                    fqName: paramFQName,
                    declSite: funDecl.range,
                    visibility: .private,
                    flags: []
                )
                let resolvedType = resolveTypeRef(
                    valueParam.type,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    diagnostics: diagnostics
                ) ?? anyType
                paramTypes.append(resolvedType)
                paramSymbols.append(paramSymbol)
                paramHasDefaultValues.append(valueParam.hasDefaultValue)
                paramIsVararg.append(valueParam.isVararg)
            }
            let returnType: TypeID
            if let explicit = resolveTypeRef(
                funDecl.returnType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters,
                diagnostics: diagnostics
            ) {
                returnType = explicit
            } else {
                switch funDecl.body {
                case .unit:
                    returnType = unitType
                case .block, .expr:
                    returnType = anyType
                }
            }
            let upperBounds: [TypeID?] = typeParameterSymbols.map { symbols.typeParameterUpperBound(for: $0) }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: paramTypes,
                    returnType: returnType,
                    isSuspend: funDecl.isSuspend,
                    valueParameterSymbols: paramSymbols,
                    valueParameterHasDefaultValues: paramHasDefaultValues,
                    valueParameterIsVararg: paramIsVararg,
                    typeParameterSymbols: typeParameterSymbols,
                    reifiedTypeParameterIndices: reifiedIndices,
                    typeParameterUpperBounds: upperBounds
                ),
                for: symbol
            )

        case .propertyDecl(let propertyDecl):
            let resolvedType = resolveTypeRef(
                propertyDecl.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics
            ) ?? types.nullableAnyType
            symbols.setPropertyType(resolvedType, for: symbol)

        case .typeAliasDecl(let typeAliasDecl):
            if let resolvedUnderlying = resolveTypeRef(
                typeAliasDecl.underlyingType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics
            ) {
                symbols.setTypeAliasUnderlyingType(resolvedUnderlying, for: symbol)
            }

        case .enumEntryDecl:
            break
        }
    }
}
