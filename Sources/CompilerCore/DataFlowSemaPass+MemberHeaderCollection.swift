import Foundation

extension DataFlowSemaPassPhase {
    func collectMemberHeaders(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let anyType = types.anyType
        let unitType = types.unitType

        for declID in memberFunctions {
            guard let decl = ast.arena.decl(declID),
                  case .funDecl(let funDecl) = decl else {
                continue
            }
            let memberFQName = ownerFQName + [funDecl.name]
            let existingFunSymbols = symbols.lookupAll(fqName: memberFQName).compactMap { symbols.symbol($0) }
            if hasDeclarationConflict(newKind: .function, existing: existingFunSymbols) {
                diagnostics.error(
                    "KSWIFTK-SEMA-0001",
                    "Duplicate declaration in the same package scope.",
                    range: funDecl.range
                )
            }
            let memberFlags = flags(from: funDecl.modifiers)
            let memberSymbol = symbols.define(
                kind: .function,
                name: funDecl.name,
                fqName: memberFQName,
                declSite: funDecl.range,
                visibility: visibility(from: funDecl.modifiers),
                flags: memberFlags
            )
            bindings.bindDecl(declID, symbol: memberSymbol)
            symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
            scope.insert(memberSymbol)

            let localNamespaceFQName = memberFQName + [interner.intern("$\(memberSymbol.rawValue)")]
            var paramTypes: [TypeID] = []
            var paramSymbols: [SymbolID] = []
            var paramHasDefaultValues: [Bool] = []
            var paramIsVararg: [Bool] = []
            var typeParameterSymbols: [SymbolID] = []
            var localTypeParameters: [InternedString: SymbolID] = [:]
            var reifiedIndices: Set<Int> = []

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

            let memberUpperBounds: [TypeID?] = typeParameterSymbols.map { symbols.typeParameterUpperBound(for: $0) }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: ownerType,
                    parameterTypes: paramTypes,
                    returnType: returnType,
                    isSuspend: funDecl.isSuspend,
                    valueParameterSymbols: paramSymbols,
                    valueParameterHasDefaultValues: paramHasDefaultValues,
                    valueParameterIsVararg: paramIsVararg,
                    typeParameterSymbols: typeParameterSymbols,
                    reifiedTypeParameterIndices: reifiedIndices,
                    typeParameterUpperBounds: memberUpperBounds
                ),
                for: memberSymbol
            )
        }

        for declID in memberProperties {
            guard let decl = ast.arena.decl(declID),
                  case .propertyDecl(let propertyDecl) = decl else {
                continue
            }
            let memberFQName = ownerFQName + [propertyDecl.name]
            let existingPropSymbols = symbols.lookupAll(fqName: memberFQName).compactMap { symbols.symbol($0) }
            if hasDeclarationConflict(newKind: .property, existing: existingPropSymbols) {
                diagnostics.error(
                    "KSWIFTK-SEMA-0001",
                    "Duplicate declaration in the same package scope.",
                    range: propertyDecl.range
                )
            }
            var propertyFlags = flags(from: propertyDecl.modifiers)
            if propertyDecl.isVar {
                propertyFlags.insert(.mutable)
            }
            let memberSymbol = symbols.define(
                kind: .property,
                name: propertyDecl.name,
                fqName: memberFQName,
                declSite: propertyDecl.range,
                visibility: visibility(from: propertyDecl.modifiers),
                flags: propertyFlags
            )
            bindings.bindDecl(declID, symbol: memberSymbol)
            symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
            scope.insert(memberSymbol)

            let resolvedType = resolveTypeRef(
                propertyDecl.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics
            ) ?? types.nullableAnyType
            symbols.setPropertyType(resolvedType, for: memberSymbol)

            // Materialize a backing field symbol for properties with custom accessors
            // (Kotlin `field` identifier in getter/setter bodies).
            // Simple properties with only an initializer don't need a separate
            // backing field — the property symbol IS the storage.
            let needsBackingField = propertyDecl.getter != nil
                || propertyDecl.setter != nil
            if needsBackingField && propertyDecl.delegateExpression == nil {
                let fieldName = interner.intern("$backing_\(interner.resolve(propertyDecl.name))")
                let fieldFQName = ownerFQName + [fieldName]
                let backingFieldSymbol = symbols.define(
                    kind: .backingField,
                    name: fieldName,
                    fqName: fieldFQName,
                    declSite: propertyDecl.range,
                    visibility: .private,
                    flags: propertyDecl.isVar ? [.mutable] : []
                )
                symbols.setParentSymbol(ownerSymbol, for: backingFieldSymbol)
                symbols.setPropertyType(resolvedType, for: backingFieldSymbol)
                symbols.setBackingFieldSymbol(backingFieldSymbol, for: memberSymbol)
            }
        }

        for declID in nestedClasses {
            guard let decl = ast.arena.decl(declID) else {
                continue
            }
            switch decl {
            case .classDecl(let nestedClass):
                let nestedFQName = ownerFQName + [nestedClass.name]
                let nestedClassKind = classSymbolKind(for: nestedClass)
                let existingClassSymbols = symbols.lookupAll(fqName: nestedFQName).compactMap { symbols.symbol($0) }
                if hasDeclarationConflict(newKind: nestedClassKind, existing: existingClassSymbols) {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0001",
                        "Duplicate declaration in the same package scope.",
                        range: nestedClass.range
                    )
                }
                let nestedSymbol = symbols.define(
                    kind: nestedClassKind,
                    name: nestedClass.name,
                    fqName: nestedFQName,
                    declSite: nestedClass.range,
                    visibility: visibility(from: nestedClass.modifiers),
                    flags: flags(from: nestedClass.modifiers)
                )
                bindings.bindDecl(declID, symbol: nestedSymbol)
                symbols.setParentSymbol(ownerSymbol, for: nestedSymbol)
                scope.insert(nestedSymbol)

                let nestedType = types.make(.classType(ClassType(classSymbol: nestedSymbol, args: [], nullability: .nonNull)))
                let nestedScope = ClassMemberScope(
                    parent: scope,
                    symbols: symbols,
                    ownerSymbol: nestedSymbol,
                    thisType: nestedType
                )
                if !nestedClass.typeParams.isEmpty {
                    types.setNominalTypeParameterVariances(
                        nestedClass.typeParams.map(\.variance),
                        for: nestedSymbol
                    )
                }
                if classSymbolKind(for: nestedClass) == .enumClass {
                    for entry in nestedClass.enumEntries {
                        let entryFQName = nestedFQName + [entry.name]
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
                        symbols.setPropertyType(nestedType, for: entrySymbol)
                    }
                }
                collectNestedTypeAliases(
                    nestedClass.nestedTypeAliases,
                    ownerFQName: nestedFQName,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner
                )
                collectMemberHeaders(
                    memberFunctions: nestedClass.memberFunctions,
                    memberProperties: nestedClass.memberProperties,
                    nestedClasses: nestedClass.nestedClasses,
                    nestedObjects: nestedClass.nestedObjects,
                    ownerFQName: nestedFQName,
                    ownerSymbol: nestedSymbol,
                    ownerType: nestedType,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: nestedScope,
                    diagnostics: diagnostics,
                    interner: interner
                )
            case .interfaceDecl(let nestedInterface):
                let nestedFQName = ownerFQName + [nestedInterface.name]
                let existingInterfaceSymbols = symbols.lookupAll(fqName: nestedFQName).compactMap { symbols.symbol($0) }
                if hasDeclarationConflict(newKind: .interface, existing: existingInterfaceSymbols) {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0001",
                        "Duplicate declaration in the same package scope.",
                        range: nestedInterface.range
                    )
                }
                let nestedSymbol = symbols.define(
                    kind: .interface,
                    name: nestedInterface.name,
                    fqName: nestedFQName,
                    declSite: nestedInterface.range,
                    visibility: visibility(from: nestedInterface.modifiers),
                    flags: flags(from: nestedInterface.modifiers)
                )
                bindings.bindDecl(declID, symbol: nestedSymbol)
                symbols.setParentSymbol(ownerSymbol, for: nestedSymbol)
                scope.insert(nestedSymbol)

                let nestedType = types.make(.classType(ClassType(classSymbol: nestedSymbol, args: [], nullability: .nonNull)))
                let nestedScope = ClassMemberScope(
                    parent: scope,
                    symbols: symbols,
                    ownerSymbol: nestedSymbol,
                    thisType: nestedType
                )
                if !nestedInterface.typeParams.isEmpty {
                    types.setNominalTypeParameterVariances(
                        nestedInterface.typeParams.map(\.variance),
                        for: nestedSymbol
                    )
                }
                collectNestedTypeAliases(
                    nestedInterface.nestedTypeAliases,
                    ownerFQName: nestedFQName,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner
                )
                collectMemberHeaders(
                    memberFunctions: nestedInterface.memberFunctions,
                    memberProperties: nestedInterface.memberProperties,
                    nestedClasses: nestedInterface.nestedClasses,
                    nestedObjects: nestedInterface.nestedObjects,
                    ownerFQName: nestedFQName,
                    ownerSymbol: nestedSymbol,
                    ownerType: nestedType,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: nestedScope,
                    diagnostics: diagnostics,
                    interner: interner
                )
            default:
                continue
            }
        }

        for declID in nestedObjects {
            guard let decl = ast.arena.decl(declID),
                  case .objectDecl(let nestedObject) = decl else {
                continue
            }
            let nestedFQName = ownerFQName + [nestedObject.name]
            let existingObjSymbols = symbols.lookupAll(fqName: nestedFQName).compactMap { symbols.symbol($0) }
            if hasDeclarationConflict(newKind: .object, existing: existingObjSymbols) {
                diagnostics.error(
                    "KSWIFTK-SEMA-0001",
                    "Duplicate declaration in the same package scope.",
                    range: nestedObject.range
                )
            }
            let nestedSymbol = symbols.define(
                kind: .object,
                name: nestedObject.name,
                fqName: nestedFQName,
                declSite: nestedObject.range,
                visibility: visibility(from: nestedObject.modifiers),
                flags: flags(from: nestedObject.modifiers)
            )
            bindings.bindDecl(declID, symbol: nestedSymbol)
            symbols.setParentSymbol(ownerSymbol, for: nestedSymbol)
            scope.insert(nestedSymbol)

            let nestedType = types.make(.classType(ClassType(classSymbol: nestedSymbol, args: [], nullability: .nonNull)))
            let nestedScope = ClassMemberScope(
                parent: scope,
                symbols: symbols,
                ownerSymbol: nestedSymbol,
                thisType: nestedType
            )
            collectNestedTypeAliases(
                nestedObject.nestedTypeAliases,
                ownerFQName: nestedFQName,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
            collectMemberHeaders(
                memberFunctions: nestedObject.memberFunctions,
                memberProperties: nestedObject.memberProperties,
                nestedClasses: nestedObject.nestedClasses,
                nestedObjects: nestedObject.nestedObjects,
                ownerFQName: nestedFQName,
                ownerSymbol: nestedSymbol,
                ownerType: nestedType,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: nestedScope,
                diagnostics: diagnostics,
                interner: interner
            )
        }
    }

    func collectNestedTypeAliases(
        _ aliases: [TypeAliasDecl],
        ownerFQName: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for alias in aliases {
            let aliasFQName = ownerFQName + [alias.name]
            let existingSymbols = symbols.lookupAll(fqName: aliasFQName).compactMap { symbols.symbol($0) }
            if hasDeclarationConflict(newKind: .typeAlias, existing: existingSymbols) {
                diagnostics.error(
                    "KSWIFTK-SEMA-0001",
                    "Duplicate declaration in the same package scope.",
                    range: alias.range
                )
            }
            let aliasSymbol = symbols.define(
                kind: .typeAlias,
                name: alias.name,
                fqName: aliasFQName,
                declSite: alias.range,
                visibility: visibility(from: alias.modifiers),
                flags: flags(from: alias.modifiers)
            )
            let localTypeParameters = registerTypeAliasTypeParameters(
                alias.typeParams,
                aliasSymbol: aliasSymbol,
                parentFQName: aliasFQName,
                declSite: alias.range,
                symbols: symbols,
                interner: interner
            )
            if alias.underlyingType == nil {
                diagnostics.error(
                    "KSWIFTK-SEMA-0061",
                    "Type alias '\(interner.resolve(alias.name))' must have a right-hand side type.",
                    range: alias.range
                )
            } else if let resolvedUnderlying = resolveTypeRef(
                alias.underlyingType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters,
                diagnostics: diagnostics
            ) {
                symbols.setTypeAliasUnderlyingType(resolvedUnderlying, for: aliasSymbol)
            }
        }
    }
}
