import Foundation

struct MemberDeclarations {
    let functions: [DeclID]
    let properties: [DeclID]
    let nestedClasses: [DeclID]
    let nestedObjects: [DeclID]
}

struct OwnerContext {
    let fqName: [InternedString]
    let symbol: SymbolID
    let type: TypeID
}

extension DataFlowSemaPhase {
    func collectMemberHeaders(
        members: MemberDeclarations,
        owner: OwnerContext,
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
        let ownerFQName = owner.fqName
        let ownerSymbol = owner.symbol
        let ownerType = owner.type
        let anyType = types.anyType
        let unitType = types.unitType

        for declID in members.functions {
            guard let decl = ast.arena.decl(declID),
                  case let .funDecl(funDecl) = decl
            else {
                continue
            }
            let memberFQName = ownerFQName + [funDecl.name]
            var memberFlags = flags(from: funDecl.modifiers)
            checkAndReportDuplicateDeclaration(
                newKind: .function,
                fqName: memberFQName,
                range: funDecl.range,
                symbols: symbols,
                diagnostics: diagnostics,
                newFlags: memberFlags
            )
            // Kotlin: interface functions without a body are implicitly abstract.
            if symbols.symbol(ownerSymbol)?.kind == .interface, funDecl.body == .unit {
                memberFlags.insert(.abstractType)
            }
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

            let returnType: TypeID = if let explicit = resolveTypeRef(
                funDecl.returnType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: mergedLocalTypeParameters,
                diagnostics: diagnostics
            ) {
                explicit
            } else {
                switch funDecl.body {
                case .unit:
                    unitType
                case .block, .expr:
                    anyType
                }
            }

            // Include class type parameter symbols so the overload resolver can
            // infer them from the receiver type arguments.
            let allTypeParameterSymbols = classTypeParameterSymbols + typeParamResult.typeParameterSymbols
            let classUpperBounds: [[TypeID]] = classTypeParameterSymbols.map {
                symbols.typeParameterUpperBounds(for: $0)
            }
            let memberUpperBounds: [[TypeID]] = classUpperBounds + typeParamResult.typeParameterSymbols.map {
                symbols.typeParameterUpperBounds(for: $0)
            }
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
                    typeParameterUpperBoundsList: memberUpperBounds,
                    classTypeParameterCount: classTPCount
                ),
                for: memberSymbol
            )
            checkAndReportJVMErasedCallableConflict(
                for: memberSymbol,
                fqName: memberFQName,
                range: funDecl.range,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics
            )
        }

        for declID in members.properties {
            guard let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            let memberFQName = ownerFQName + [propertyDecl.name]
            var propertyFlags = flags(from: propertyDecl.modifiers)
            checkAndReportDuplicateDeclaration(
                newKind: .property,
                fqName: memberFQName,
                range: propertyDecl.range,
                symbols: symbols,
                diagnostics: diagnostics,
                newFlags: propertyFlags
            )
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

            validateConstPropertyDeclaration(
                propertyDecl,
                propertySymbol: memberSymbol,
                resolvedType: resolvedType,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics
            )

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
            if needsBackingField, propertyDecl.delegateExpression == nil {
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

            // Create a delegate storage symbol for properties with `by` delegation.
            // This symbol tracks the delegate instance so that KIR lowering can
            // synthesise getValue/setValue accessor calls.
            if propertyDecl.delegateExpression != nil {
                let delegateStorageName = interner.intern("$delegate_\(interner.resolve(propertyDecl.name))")
                let delegateStorageFQName = ownerFQName + [delegateStorageName]
                let delegateStorageSymbol = symbols.define(
                    kind: .field,
                    name: delegateStorageName,
                    fqName: delegateStorageFQName,
                    declSite: propertyDecl.range,
                    visibility: .private,
                    flags: []
                )
                symbols.setParentSymbol(ownerSymbol, for: delegateStorageSymbol)
                symbols.setDelegateStorageSymbol(delegateStorageSymbol, for: memberSymbol)
            }
        }

        for declID in members.nestedClasses {
            collectNestedClassOrInterfaceHeader(
                declID: declID,
                ownerFQName: ownerFQName,
                ownerSymbol: ownerSymbol,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: scope,
                diagnostics: diagnostics,
                interner: interner
            )
        }

        for declID in members.nestedObjects {
            collectNestedObjectHeader(
                declID: declID,
                ownerFQName: ownerFQName,
                ownerSymbol: ownerSymbol,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: scope,
                diagnostics: diagnostics,
                interner: interner
            )
        }
    }

    private func collectNestedClassOrInterfaceHeader(
        declID: DeclID,
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
        guard let decl = ast.arena.decl(declID) else {
            return
        }
        let anyType = types.anyType
        switch decl {
        case let .classDecl(nestedClass):
            let nestedFQName = ownerFQName + [nestedClass.name]
            let nestedClassKind = classSymbolKind(for: nestedClass)
            checkAndReportDuplicateDeclaration(
                newKind: nestedClassKind,
                fqName: nestedFQName,
                range: nestedClass.range,
                symbols: symbols,
                diagnostics: diagnostics,
                newFlags: flags(from: nestedClass.modifiers)
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
            let ctorName = interner.intern("<init>")
            let nestedCtorFQName = nestedFQName + [ctorName]
            let nestedHasPrimaryCtorSyntax = nestedClass.hasPrimaryConstructorSyntax
            let nestedHasSecondaryCtors = !nestedClass.secondaryConstructors.isEmpty
            if nestedHasPrimaryCtorSyntax || !nestedHasSecondaryCtors {
                let nestedPrimaryCtorVisibility = primaryConstructorVisibility(
                    for: nestedClass,
                    classKind: nestedClassKind,
                    declarationVisibility: visibility(from: nestedClass.modifiers)
                )
                let nestedPrimaryCtorSymbol = symbols.define(
                    kind: .constructor,
                    name: nestedClass.name,
                    fqName: nestedCtorFQName,
                    declSite: nestedClass.range,
                    visibility: nestedPrimaryCtorVisibility,
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
                    symbols.setParentSymbol(nestedSymbol, for: entrySymbol)
                    symbols.setPropertyType(nestedType, for: entrySymbol)
                }
            }
            if nestedClass.modifiers.contains(.data) {
                collectSyntheticDataClassCopy(
                    classDecl: nestedClass,
                    ast: ast,
                    ownerSymbol: nestedSymbol,
                    ownerFQName: nestedFQName,
                    ownerType: nestedType,
                    symbols: symbols,
                    types: types,
                    scope: nestedScope,
                    interner: interner,
                    diagnostics: diagnostics
                )
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
                members: MemberDeclarations(
                    functions: nestedClass.memberFunctions,
                    properties: nestedClass.memberProperties,
                    nestedClasses: nestedClass.nestedClasses,
                    nestedObjects: nestedClass.nestedObjects
                ),
                owner: OwnerContext(fqName: nestedFQName, symbol: nestedSymbol, type: nestedType),
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
        case let .interfaceDecl(nestedInterface):
            let nestedFQName = ownerFQName + [nestedInterface.name]
            checkAndReportDuplicateDeclaration(
                newKind: .interface,
                fqName: nestedFQName,
                range: nestedInterface.range,
                symbols: symbols,
                diagnostics: diagnostics,
                newFlags: flags(from: nestedInterface.modifiers)
            )
            var nestedFlags = flags(from: nestedInterface.modifiers)
            if nestedInterface.isFunInterface {
                nestedFlags.insert(.funInterface)
            }
            let nestedSymbol = symbols.define(
                kind: .interface,
                name: nestedInterface.name,
                fqName: nestedFQName,
                declSite: nestedInterface.range,
                visibility: visibility(from: nestedInterface.modifiers),
                flags: nestedFlags
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
                members: MemberDeclarations(
                    functions: nestedInterface.memberFunctions,
                    properties: nestedInterface.memberProperties,
                    nestedClasses: nestedInterface.nestedClasses,
                    nestedObjects: nestedInterface.nestedObjects
                ),
                owner: OwnerContext(fqName: nestedFQName, symbol: nestedSymbol, type: nestedType),
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
            break
        }
    }

    private func collectNestedObjectHeader(
        declID: DeclID,
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
        guard let decl = ast.arena.decl(declID),
              case let .objectDecl(nestedObject) = decl
        else {
            return
        }
        let nestedFQName = ownerFQName + [nestedObject.name]
        checkAndReportDuplicateDeclaration(
            newKind: .object,
            fqName: nestedFQName,
            range: nestedObject.range,
            symbols: symbols,
            diagnostics: diagnostics,
            newFlags: flags(from: nestedObject.modifiers)
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
            members: MemberDeclarations(
                functions: nestedObject.memberFunctions,
                properties: nestedObject.memberProperties,
                nestedClasses: nestedObject.nestedClasses,
                nestedObjects: nestedObject.nestedObjects
            ),
            owner: OwnerContext(fqName: nestedFQName, symbol: nestedSymbol, type: nestedType),
            ast: ast,
            symbols: symbols,
            types: types,
            bindings: bindings,
            scope: nestedScope,
            diagnostics: diagnostics,
            interner: interner
        )
        if nestedObject.modifiers.contains(.data) {
            collectSyntheticDataObjectToString(
                ownerSymbol: nestedSymbol,
                ownerFQName: nestedFQName,
                objectType: nestedType,
                symbols: symbols,
                types: types,
                scope: nestedScope,
                interner: interner
            )
            collectSyntheticDataObjectEquals(
                ownerSymbol: nestedSymbol,
                ownerFQName: nestedFQName,
                objectType: nestedType,
                symbols: symbols,
                types: types,
                scope: nestedScope,
                interner: interner
            )
        }
    }

    // Collects companion object header: creates the companion symbol, links it to the owner class,
    // and registers companion members under the companion's fully qualified name. Resolution of
    // `ClassName.memberName` to companion members is handled separately by the call/type checker.
}
