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
        interner: StringInterner,
        classTypeParameterSymbols: [SymbolID] = [],
        classLocalTypeParameters: [InternedString: SymbolID] = [:]
    ) {
        let anyType = types.anyType
        let unitType = types.unitType

        for declID in memberFunctions {
            guard let decl = ast.arena.decl(declID),
                  case .funDecl(let funDecl) = decl else {
                continue
            }
            let memberFQName = ownerFQName + [funDecl.name]
            checkAndReportDuplicateDeclaration(
                newKind: .function,
                fqName: memberFQName,
                range: funDecl.range,
                symbols: symbols,
                diagnostics: diagnostics
            )
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
            let typeParamResult = collectFunctionTypeParameters(
                funDecl.typeParams,
                localNamespaceFQName: localNamespaceFQName,
                declSite: funDecl.range,
                ast: ast, symbols: symbols, types: types,
                interner: interner, isInline: funDecl.isInline,
                diagnostics: diagnostics
            )

            // Merge class type parameters with function's own type parameters.
            // Function params shadow class params if names collide.
            var mergedLocalTypeParameters = classLocalTypeParameters
            for (key, value) in typeParamResult.localTypeParameters {
                mergedLocalTypeParameters[key] = value
            }

            let params = collectValueParameters(
                funDecl.valueParams,
                localNamespaceFQName: localNamespaceFQName,
                declSite: funDecl.range,
                ast: ast, symbols: symbols, types: types,
                interner: interner,
                localTypeParameters: mergedLocalTypeParameters,
                diagnostics: diagnostics,
                fallbackType: anyType
            )

            let returnType: TypeID
            if let explicit = resolveTypeRef(
                funDecl.returnType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: mergedLocalTypeParameters,
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

            // Include class type parameter symbols so the overload resolver can
            // infer them from the receiver type arguments.
            let allTypeParameterSymbols = classTypeParameterSymbols + typeParamResult.typeParameterSymbols
            let classUpperBounds: [TypeID?] = classTypeParameterSymbols.map { symbols.typeParameterUpperBound(for: $0) }
            let memberUpperBounds: [TypeID?] = classUpperBounds + typeParamResult.typeParameterSymbols.map { symbols.typeParameterUpperBound(for: $0) }
            // Offset reified indices by the number of prepended class type params
            // so they still point at the correct function-own type parameters.
            let classTPCount = classTypeParameterSymbols.count
            let offsetReifiedIndices: Set<Int> = classTPCount == 0
                ? typeParamResult.reifiedIndices
                : Set(typeParamResult.reifiedIndices.map { $0 + classTPCount })
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: ownerType,
                    parameterTypes: params.paramTypes,
                    returnType: returnType,
                    isSuspend: funDecl.isSuspend,
                    valueParameterSymbols: params.paramSymbols,
                    valueParameterHasDefaultValues: params.paramHasDefaultValues,
                    valueParameterIsVararg: params.paramIsVararg,
                    typeParameterSymbols: allTypeParameterSymbols,
                    reifiedTypeParameterIndices: offsetReifiedIndices,
                    typeParameterUpperBounds: memberUpperBounds,
                    classTypeParameterCount: classTPCount
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
            checkAndReportDuplicateDeclaration(
                newKind: .property,
                fqName: memberFQName,
                range: propertyDecl.range,
                symbols: symbols,
                diagnostics: diagnostics
            )
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

            // Use class type parameters for resolving member property types
            let resolvedType = resolveTypeRef(
                propertyDecl.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: classLocalTypeParameters,
                diagnostics: diagnostics
            ) ?? types.nullableAnyType
            symbols.setPropertyType(resolvedType, for: memberSymbol)

            // Materialize a backing field symbol for properties with custom accessors
            // (Kotlin `field` identifier in getter/setter bodies).
            // Simple properties with only an initializer don't need a separate
            // backing field — the property symbol IS the storage.
            // Getter-only computed properties (`val x: Int get() = expr`) never
            // need a backing field because they have no storage — the getter
            // body is evaluated on every access.
            let isGetterOnlyComputed = propertyDecl.getter != nil
                && propertyDecl.setter == nil
                && propertyDecl.initializer == nil
            let needsBackingField = !isGetterOnlyComputed
                && (propertyDecl.getter != nil || propertyDecl.setter != nil)
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
                checkAndReportDuplicateDeclaration(
                    newKind: nestedClassKind,
                    fqName: nestedFQName,
                    range: nestedClass.range,
                    symbols: symbols,
                    diagnostics: diagnostics
                )
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
                // Create constructor symbols for nested class (primary + secondary).
                // Kotlin rule: only define a primary constructor symbol when either
                // (a) the class header has explicit constructor parentheses, or
                // (b) there are no secondary constructors (implicit default ctor).
                let ctorName = interner.intern("<init>")
                let nestedCtorFQName = nestedFQName + [ctorName]
                let nestedHasPrimaryCtorSyntax = nestedClass.hasPrimaryConstructorSyntax
                let nestedHasSecondaryCtors = !nestedClass.secondaryConstructors.isEmpty
                if nestedHasPrimaryCtorSyntax || !nestedHasSecondaryCtors {
                    let nestedPrimaryCtorSymbol = symbols.define(
                        kind: .constructor,
                        name: nestedClass.name,
                        fqName: nestedCtorFQName,
                        declSite: nestedClass.range,
                        visibility: visibility(from: nestedClass.modifiers),
                        flags: []
                    )
                    nestedScope.insert(nestedPrimaryCtorSymbol)
                    symbols.setParentSymbol(nestedSymbol, for: nestedPrimaryCtorSymbol)
                    do {
                        let localNamespaceFQName = nestedCtorFQName + [interner.intern("$\(nestedPrimaryCtorSymbol.rawValue)")]
                        let params = collectValueParameters(
                            nestedClass.primaryConstructorParams,
                            localNamespaceFQName: localNamespaceFQName,
                            declSite: nestedClass.range,
                            ast: ast, symbols: symbols, types: types,
                            interner: interner, diagnostics: diagnostics,
                            fallbackType: anyType
                        )
                        symbols.setFunctionSignature(
                            FunctionSignature(
                                receiverType: nestedType,
                                parameterTypes: params.paramTypes,
                                returnType: nestedType,
                                valueParameterSymbols: params.paramSymbols,
                                valueParameterHasDefaultValues: params.paramHasDefaultValues,
                                valueParameterIsVararg: params.paramIsVararg
                            ),
                            for: nestedPrimaryCtorSymbol
                        )
                    }
                }
                for (ctorIndex, secondaryCtor) in nestedClass.secondaryConstructors.enumerated() {
                    let secCtorSymbol = symbols.define(
                        kind: .constructor,
                        name: nestedClass.name,
                        fqName: nestedCtorFQName,
                        declSite: secondaryCtor.range,
                        visibility: visibility(from: secondaryCtor.modifiers),
                        flags: []
                    )
                    nestedScope.insert(secCtorSymbol)
                    symbols.setParentSymbol(nestedSymbol, for: secCtorSymbol)
                    let localNamespaceFQName = nestedCtorFQName + [interner.intern("$sec\(ctorIndex)_\(secCtorSymbol.rawValue)")]
                    let params = collectValueParameters(
                        secondaryCtor.valueParams,
                        localNamespaceFQName: localNamespaceFQName,
                        declSite: secondaryCtor.range,
                        ast: ast, symbols: symbols, types: types,
                        interner: interner, diagnostics: diagnostics,
                        fallbackType: anyType
                    )
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: nestedType,
                            parameterTypes: params.paramTypes,
                            returnType: nestedType,
                            valueParameterSymbols: params.paramSymbols,
                            valueParameterHasDefaultValues: params.paramHasDefaultValues,
                            valueParameterIsVararg: params.paramIsVararg
                        ),
                        for: secCtorSymbol
                    )
                }

                if classSymbolKind(for: nestedClass) == .enumClass {
                    for entry in nestedClass.enumEntries {
                        let entryFQName = nestedFQName + [entry.name]
                        checkAndReportDuplicateDeclaration(
                            newKind: .field,
                            fqName: entryFQName,
                            range: entry.range,
                            symbols: symbols,
                            diagnostics: diagnostics
                        )
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
                if let companionDeclID = nestedClass.companionObject {
                    collectCompanionObjectHeader(
                        companionDeclID: companionDeclID,
                        ownerFQName: nestedFQName,
                        ownerSymbol: nestedSymbol,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        bindings: bindings,
                        scope: nestedScope,
                        diagnostics: diagnostics,
                        interner: interner
                    )
                }
            case .interfaceDecl(let nestedInterface):
                let nestedFQName = ownerFQName + [nestedInterface.name]
                checkAndReportDuplicateDeclaration(
                    newKind: .interface,
                    fqName: nestedFQName,
                    range: nestedInterface.range,
                    symbols: symbols,
                    diagnostics: diagnostics
                )
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
                if let companionDeclID = nestedInterface.companionObject {
                    collectCompanionObjectHeader(
                        companionDeclID: companionDeclID,
                        ownerFQName: nestedFQName,
                        ownerSymbol: nestedSymbol,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        bindings: bindings,
                        scope: nestedScope,
                        diagnostics: diagnostics,
                        interner: interner
                    )
                }
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
            checkAndReportDuplicateDeclaration(
                newKind: .object,
                fqName: nestedFQName,
                range: nestedObject.range,
                symbols: symbols,
                diagnostics: diagnostics
            )
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

    /// Collects companion object header: creates the companion symbol, links it to the owner class,
    /// and registers companion members under the companion's fully qualified name. Resolution of
    /// `ClassName.memberName` to companion members is handled separately by the call/type checker.
    func collectCompanionObjectHeader(
        companionDeclID: DeclID,
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let decl = ast.arena.decl(companionDeclID),
              case .objectDecl(let companionObject) = decl else {
            return
        }

        // Companion objects default to name "Companion" if the parsed name is empty or just "Companion"
        let companionName: InternedString
        let parsedName = interner.resolve(companionObject.name)
        if parsedName.isEmpty {
            companionName = interner.intern("Companion")
        } else {
            companionName = companionObject.name
        }

        let companionFQName = ownerFQName + [companionName]
        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: companionFQName,
            declSite: companionObject.range,
            visibility: visibility(from: companionObject.modifiers),
            flags: flags(from: companionObject.modifiers)
        )
        bindings.bindDecl(companionDeclID, symbol: companionSymbol)
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)
        scope.insert(companionSymbol)

        let companionType = types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
        let companionScope = ClassMemberScope(
            parent: scope,
            symbols: symbols,
            ownerSymbol: companionSymbol,
            thisType: companionType
        )
        collectNestedTypeAliases(
            companionObject.nestedTypeAliases,
            ownerFQName: companionFQName,
            ast: ast,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner
        )
        collectMemberHeaders(
            memberFunctions: companionObject.memberFunctions,
            memberProperties: companionObject.memberProperties,
            nestedClasses: companionObject.nestedClasses,
            nestedObjects: companionObject.nestedObjects,
            ownerFQName: companionFQName,
            ownerSymbol: companionSymbol,
            ownerType: companionType,
            ast: ast,
            symbols: symbols,
            types: types,
            bindings: bindings,
            scope: companionScope,
            diagnostics: diagnostics,
            interner: interner
        )
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
            checkAndReportDuplicateDeclaration(
                newKind: .typeAlias,
                fqName: aliasFQName,
                range: alias.range,
                symbols: symbols,
                diagnostics: diagnostics
            )
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
