import Foundation

extension DataFlowSemaPhase {
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
        case let .classDecl(classDecl):
            var classFlags = flags(from: classDecl.modifiers)
            if classDecl.modifiers.contains(.value) {
                classFlags.insert(.valueType)
            }
            declaration = (
                kind: classSymbolKind(for: classDecl),
                name: classDecl.name,
                range: classDecl.range,
                visibility: visibility(from: classDecl.modifiers),
                flags: classFlags
            )
        case let .interfaceDecl(interfaceDecl):
            declaration = (
                kind: .interface,
                name: interfaceDecl.name,
                range: interfaceDecl.range,
                visibility: visibility(from: interfaceDecl.modifiers),
                flags: flags(from: interfaceDecl.modifiers)
            )
        case let .objectDecl(objectDecl):
            declaration = (
                kind: .object,
                name: objectDecl.name,
                range: objectDecl.range,
                visibility: visibility(from: objectDecl.modifiers),
                flags: flags(from: objectDecl.modifiers)
            )
        case let .funDecl(funDecl):
            declaration = (
                kind: .function,
                name: funDecl.name,
                range: funDecl.range,
                visibility: visibility(from: funDecl.modifiers),
                flags: flags(from: funDecl.modifiers)
            )
        case let .propertyDecl(propertyDecl):
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
        case let .typeAliasDecl(typeAliasDecl):
            declaration = (
                kind: .typeAlias,
                name: typeAliasDecl.name,
                range: typeAliasDecl.range,
                visibility: visibility(from: typeAliasDecl.modifiers),
                flags: flags(from: typeAliasDecl.modifiers)
            )
        case let .enumEntryDecl(entry):
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
        checkAndReportDuplicateDeclaration(
            newKind: declaration.kind,
            fqName: fqName,
            range: declaration.range,
            symbols: symbols,
            diagnostics: diagnostics
        )
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
        case let .classDecl(classDecl):
            // Register class type parameters as symbols so member functions
            // can reference them (e.g. `fun get(): T` inside `class Box<T>`).
            let classTypeParamResult = registerNominalTypeParameters(
                classDecl.typeParams,
                ownerSymbol: symbol,
                fqName: fqName,
                namespacePrefix: "$class",
                declSite: classDecl.range,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics
            )
            let classTypeParamSymbols = classTypeParamResult.symbols
            let classLocalTypeParameters = classTypeParamResult.localMap

            // Create owner type with type parameter references as args
            let typeParamArgs: [TypeArg] = classTypeParamSymbols.map { tpSymbol in
                .invariant(types.make(.typeParam(TypeParamType(symbol: tpSymbol))))
            }
            let classType = types.make(.classType(ClassType(classSymbol: symbol, args: typeParamArgs, nullability: .nonNull)))
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

            // Kotlin rule: only define a primary constructor symbol when either
            // (a) the class header has explicit constructor parentheses
            //     (`class Foo()` or `class Foo(x: Int)`), or
            // (b) there are no secondary constructors (implicit default ctor).
            // A class like `class Foo { constructor(x: Int) : ... }` has NO
            // primary constructor and should not get a synthetic no-arg ctor.
            let hasPrimaryCtorSyntax = classDecl.hasPrimaryConstructorSyntax
            let hasSecondaryCtors = !classDecl.secondaryConstructors.isEmpty
            if hasPrimaryCtorSyntax || !hasSecondaryCtors {
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
                    let localNamespaceFQName = primaryCtorFQName + [interner.intern("$\(primaryCtorSymbol.rawValue)")]
                    let params = collectValueParameters(
                        classDecl.primaryConstructorParams,
                        localNamespaceFQName: localNamespaceFQName,
                        declSite: classDecl.range,
                        ast: ast, symbols: symbols, types: types,
                        interner: interner,
                        localTypeParameters: classLocalTypeParameters,
                        diagnostics: diagnostics,
                        fallbackType: anyType
                    )
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: classType,
                            parameterTypes: params.paramTypes,
                            returnType: classType,
                            valueParameterSymbols: params.paramSymbols,
                            valueParameterHasDefaultValues: params.paramHasDefaultValues,
                            valueParameterIsVararg: params.paramIsVararg,
                            typeParameterSymbols: classTypeParamSymbols
                        ),
                        for: primaryCtorSymbol
                    )
                }
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
                let localNamespaceFQName = primaryCtorFQName + [interner.intern("$sec\(ctorIndex)_\(secCtorSymbol.rawValue)")]
                let params = collectValueParameters(
                    secondaryCtor.valueParams,
                    localNamespaceFQName: localNamespaceFQName,
                    declSite: secondaryCtor.range,
                    ast: ast, symbols: symbols, types: types,
                    interner: interner,
                    localTypeParameters: classLocalTypeParameters,
                    diagnostics: diagnostics,
                    fallbackType: anyType
                )
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: classType,
                        parameterTypes: params.paramTypes,
                        returnType: classType,
                        valueParameterSymbols: params.paramSymbols,
                        valueParameterHasDefaultValues: params.paramHasDefaultValues,
                        valueParameterIsVararg: params.paramIsVararg,
                        typeParameterSymbols: classTypeParamSymbols
                    ),
                    for: secCtorSymbol
                )
            }

            // Value class validation: must have exactly one primary constructor parameter
            if classDecl.modifiers.contains(.value) {
                let valParams = classDecl.primaryConstructorParams
                if valParams.count != 1 {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0070",
                        "Value class must have exactly one primary constructor parameter.",
                        range: classDecl.range
                    )
                } else {
                    // Record the underlying type of the value class
                    let singleParam = valParams[0]
                    let underlyingType = resolveTypeRef(
                        singleParam.type,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        localTypeParameters: classLocalTypeParameters,
                        diagnostics: diagnostics
                    ) ?? anyType
                    symbols.setValueClassUnderlyingType(underlyingType, for: symbol)
                }
                if !classDecl.secondaryConstructors.isEmpty {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0071",
                        "Value class cannot have secondary constructors.",
                        range: classDecl.range
                    )
                }
            }

            if declaration.kind == .enumClass {
                for entry in classDecl.enumEntries {
                    let entryFQName = fqName + [entry.name]
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
                interner: interner,
                classTypeParameterSymbols: classTypeParamSymbols,
                classLocalTypeParameters: classLocalTypeParameters
            )
            // Process companion object: register as nested object and link to owner class
            if let companionDeclID = classDecl.companionObject {
                collectCompanionObjectHeader(
                    companionDeclID: companionDeclID,
                    ownerFQName: fqName,
                    ownerSymbol: symbol,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: classScope,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }

        case let .interfaceDecl(interfaceDecl):
            // Register interface type parameters as symbols
            let ifaceTypeParamResult = registerNominalTypeParameters(
                interfaceDecl.typeParams,
                ownerSymbol: symbol,
                fqName: fqName,
                namespacePrefix: "$iface",
                declSite: interfaceDecl.range,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics
            )
            let ifaceTypeParamSymbols = ifaceTypeParamResult.symbols
            let ifaceLocalTypeParameters = ifaceTypeParamResult.localMap

            let ifaceTypeParamArgs: [TypeArg] = ifaceTypeParamSymbols.map { tpSymbol in
                .invariant(types.make(.typeParam(TypeParamType(symbol: tpSymbol))))
            }
            let interfaceType = types.make(.classType(ClassType(classSymbol: symbol, args: ifaceTypeParamArgs, nullability: .nonNull)))
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
                interner: interner,
                classTypeParameterSymbols: ifaceTypeParamSymbols,
                classLocalTypeParameters: ifaceLocalTypeParameters
            )
            // Process companion object for interface
            if let companionDeclID = interfaceDecl.companionObject {
                collectCompanionObjectHeader(
                    companionDeclID: companionDeclID,
                    ownerFQName: fqName,
                    ownerSymbol: symbol,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: interfaceScope,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }

        case let .objectDecl(objectDecl):
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

        case let .funDecl(funDecl):
            let localNamespaceFQName = fqName + [interner.intern("$\(symbol.rawValue)")]
            let typeParamResult = collectFunctionTypeParameters(
                funDecl.typeParams,
                localNamespaceFQName: localNamespaceFQName,
                declSite: funDecl.range,
                ast: ast, symbols: symbols, types: types,
                interner: interner, isInline: funDecl.isInline,
                diagnostics: diagnostics
            )
            let receiverType = resolveTypeRef(
                funDecl.receiverType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: typeParamResult.localTypeParameters,
                diagnostics: diagnostics
            )
            let params = collectValueParameters(
                funDecl.valueParams,
                localNamespaceFQName: localNamespaceFQName,
                declSite: funDecl.range,
                ast: ast, symbols: symbols, types: types,
                interner: interner,
                localTypeParameters: typeParamResult.localTypeParameters,
                diagnostics: diagnostics,
                fallbackType: anyType
            )
            let returnType: TypeID = if let explicit = resolveTypeRef(
                funDecl.returnType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: typeParamResult.localTypeParameters,
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
            let upperBounds: [TypeID?] = typeParamResult.typeParameterSymbols.map { symbols.typeParameterUpperBound(for: $0) }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: params.paramTypes,
                    returnType: returnType,
                    isSuspend: funDecl.isSuspend,
                    valueParameterSymbols: params.paramSymbols,
                    valueParameterHasDefaultValues: params.paramHasDefaultValues,
                    valueParameterIsVararg: params.paramIsVararg,
                    typeParameterSymbols: typeParamResult.typeParameterSymbols,
                    reifiedTypeParameterIndices: typeParamResult.reifiedIndices,
                    typeParameterUpperBounds: upperBounds
                ),
                for: symbol
            )

        case let .propertyDecl(propertyDecl):
            let resolvedType = resolveTypeRef(
                propertyDecl.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics
            ) ?? types.nullableAnyType
            symbols.setPropertyType(resolvedType, for: symbol)

            if let receiverType = resolveTypeRef(
                propertyDecl.receiverType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics
            ) {
                symbols.setExtensionPropertyReceiverType(receiverType, for: symbol)

                let getterSymbol = symbols.define(
                    kind: .function,
                    name: interner.intern("get"),
                    fqName: fqName + [interner.intern("$get")],
                    declSite: propertyDecl.range,
                    visibility: visibility(from: propertyDecl.modifiers),
                    flags: [.synthetic]
                )
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: resolvedType
                    ),
                    for: getterSymbol
                )
                symbols.setParentSymbol(symbol, for: getterSymbol)
                symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: symbol)

                if propertyDecl.isVar {
                    let setterSymbol = symbols.define(
                        kind: .function,
                        name: interner.intern("set"),
                        fqName: fqName + [interner.intern("$set")],
                        declSite: propertyDecl.range,
                        visibility: visibility(from: propertyDecl.modifiers),
                        flags: [.synthetic]
                    )
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: receiverType,
                            parameterTypes: [resolvedType],
                            returnType: unitType
                        ),
                        for: setterSymbol
                    )
                    symbols.setParentSymbol(symbol, for: setterSymbol)
                    symbols.setExtensionPropertySetterAccessor(setterSymbol, for: symbol)
                }
            }

            validateConstPropertyDeclaration(
                propertyDecl,
                propertySymbol: symbol,
                resolvedType: resolvedType,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics
            )

        case let .typeAliasDecl(typeAliasDecl):
            let localTypeParameters = registerTypeAliasTypeParameters(
                typeAliasDecl.typeParams,
                aliasSymbol: symbol,
                parentFQName: fqName,
                declSite: typeAliasDecl.range,
                symbols: symbols,
                interner: interner
            )
            if typeAliasDecl.underlyingType == nil {
                diagnostics.error(
                    "KSWIFTK-SEMA-0061",
                    "Type alias '\(interner.resolve(typeAliasDecl.name))' must have a right-hand side type.",
                    range: typeAliasDecl.range
                )
            } else if let resolvedUnderlying = resolveTypeRef(
                typeAliasDecl.underlyingType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters,
                diagnostics: diagnostics
            ) {
                symbols.setTypeAliasUnderlyingType(resolvedUnderlying, for: symbol)
            }

        case .enumEntryDecl:
            break
        }
    }

    /// Registers type parameters for a nominal type (class or interface) as symbols,
    /// sets their variances and upper bounds, and returns the symbol list and local map.
    private func registerNominalTypeParameters(
        _ typeParams: [TypeParamDecl],
        ownerSymbol: SymbolID,
        fqName: [InternedString],
        namespacePrefix: String,
        declSite: SourceRange,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine
    ) -> (symbols: [SymbolID], localMap: [InternedString: SymbolID]) {
        var typeParamSymbols: [SymbolID] = []
        var localTypeParameters: [InternedString: SymbolID] = [:]

        guard !typeParams.isEmpty else {
            return (symbols: typeParamSymbols, localMap: localTypeParameters)
        }

        types.setNominalTypeParameterVariances(
            typeParams.map(\.variance),
            for: ownerSymbol
        )
        let typeParamNamespace = fqName + [interner.intern("\(namespacePrefix)\(ownerSymbol.rawValue)")]
        for typeParam in typeParams {
            let typeParamFQName = typeParamNamespace + [typeParam.name]
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParam.name,
                fqName: typeParamFQName,
                declSite: declSite,
                visibility: .private,
                flags: []
            )
            typeParamSymbols.append(typeParamSymbol)
            localTypeParameters[typeParam.name] = typeParamSymbol
        }
        types.setNominalTypeParameterSymbols(
            typeParamSymbols,
            for: ownerSymbol
        )
        for typeParam in typeParams {
            if let boundRef = typeParam.upperBound,
               let typeParamSym = localTypeParameters[typeParam.name] {
                if let boundType = resolveTypeRef(
                    boundRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters,
                    diagnostics: diagnostics
                ) {
                    symbols.setTypeParameterUpperBound(boundType, for: typeParamSym)
                }
            }
        }

        return (symbols: typeParamSymbols, localMap: localTypeParameters)
    }
}
