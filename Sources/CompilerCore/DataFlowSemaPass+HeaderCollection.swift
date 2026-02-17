import Foundation

extension DataFlowSemaPassPhase {
    func definePackageSymbol(for file: ASTFile, symbols: SymbolTable, interner: StringInterner) -> SymbolID {
        let package = file.packageFQName.isEmpty ? [interner.intern("_root_")] : file.packageFQName
        let name = package.last ?? interner.intern("_root_")
        if let existing = symbols.lookup(fqName: package) {
            return existing
        }
        return symbols.define(
            kind: .package,
            name: name,
            fqName: package,
            declSite: nil,
            visibility: .public
        )
    }

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
                        interner: interner
                    ) ?? anyType
                    paramTypes.append(resolvedType)
                    paramSymbols.append(paramSymbol)
                    paramHasDefaultValues.append(valueParam.hasDefaultValue)
                    paramIsVararg.append(valueParam.isVararg)
                }
                symbols.setFunctionSignature(
                    FunctionSignature(
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
                        interner: interner
                    ) ?? anyType
                    paramTypes.append(resolvedType)
                    paramSymbols.append(paramSymbol)
                    paramHasDefaultValues.append(valueParam.hasDefaultValue)
                    paramIsVararg.append(valueParam.isVararg)
                }
                symbols.setFunctionSignature(
                    FunctionSignature(
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
                scope: scope,
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
            _ = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            collectNestedTypeAliases(
                interfaceDecl.nestedTypeAliases,
                ownerFQName: fqName,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )

        case .objectDecl(let objectDecl):
            let objectType = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
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
                scope: scope,
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
                localTypeParameters: localTypeParameters
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
                    localTypeParameters: localTypeParameters
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
                localTypeParameters: localTypeParameters
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
                    reifiedTypeParameterIndices: reifiedIndices
                ),
                for: symbol
            )

        case .propertyDecl(let propertyDecl):
            let resolvedType = resolveTypeRef(
                propertyDecl.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) ?? types.nullableAnyType
            symbols.setPropertyType(resolvedType, for: symbol)

        case .typeAliasDecl(let typeAliasDecl):
            if let resolvedUnderlying = resolveTypeRef(
                typeAliasDecl.underlyingType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) {
                symbols.setTypeAliasUnderlyingType(resolvedUnderlying, for: symbol)
            }

        case .enumEntryDecl:
            break
        }
    }

    private func collectMemberHeaders(
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
                    localTypeParameters: localTypeParameters
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
                localTypeParameters: localTypeParameters
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
                    reifiedTypeParameterIndices: reifiedIndices
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

            let resolvedType = resolveTypeRef(
                propertyDecl.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) ?? types.nullableAnyType
            symbols.setPropertyType(resolvedType, for: memberSymbol)
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

                let nestedType = types.make(.classType(ClassType(classSymbol: nestedSymbol, args: [], nullability: .nonNull)))
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
                    scope: scope,
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

                _ = types.make(.classType(ClassType(classSymbol: nestedSymbol, args: [], nullability: .nonNull)))
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

            let nestedType = types.make(.classType(ClassType(classSymbol: nestedSymbol, args: [], nullability: .nonNull)))
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
                scope: scope,
                diagnostics: diagnostics,
                interner: interner
            )
        }
    }

    private func collectNestedTypeAliases(
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
            if let resolvedUnderlying = resolveTypeRef(
                alias.underlyingType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) {
                symbols.setTypeAliasUnderlyingType(resolvedUnderlying, for: aliasSymbol)
            }
        }
    }

    private func classSymbolKind(for classDecl: ClassDecl) -> SymbolKind {
        if classDecl.modifiers.contains(.annotationClass) {
            return .annotationClass
        }
        if classDecl.modifiers.contains(.enumModifier) {
            return .enumClass
        }
        return .class
    }

    private func visibility(from modifiers: Modifiers) -> Visibility {
        if modifiers.contains(.private) {
            return .private
        }
        if modifiers.contains(.internal) {
            return .internal
        }
        if modifiers.contains(.protected) {
            return .protected
        }
        return .public
    }

    private func flags(from modifiers: Modifiers) -> SymbolFlags {
        var value: SymbolFlags = []
        if modifiers.contains(.suspend) {
            value.insert(.suspendFunction)
        }
        if modifiers.contains(.inline) {
            value.insert(.inlineFunction)
        }
        if modifiers.contains(.sealed) {
            value.insert(.sealedType)
        }
        if modifiers.contains(.data) {
            value.insert(.dataType)
        }
        return value
    }

    private func hasDeclarationConflict(newKind: SymbolKind, existing: [SemanticSymbol]) -> Bool {
        guard !existing.isEmpty else {
            return false
        }
        if isOverloadableSymbol(newKind) {
            return existing.contains(where: { !isOverloadableSymbol($0.kind) })
        }
        return true
    }

    private func isOverloadableSymbol(_ kind: SymbolKind) -> Bool {
        kind == .function || kind == .constructor
    }

    func validateConstructorDelegation(
        ast: ASTModule,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case .classDecl(let classDecl) = decl,
                      let classSymbol = symbols.allSymbols().first(where: { $0.declSite == classDecl.range && ($0.kind == .class || $0.kind == .enumClass || $0.kind == .annotationClass) })?.id else {
                    continue
                }
                for secondaryCtor in classDecl.secondaryConstructors {
                    guard let delegation = secondaryCtor.delegationCall,
                          delegation.kind == .super_ else {
                        continue
                    }
                    let superTypes = symbols.directSupertypes(for: classSymbol)
                    let classSupertypes = superTypes.filter {
                        let kind = symbols.symbol($0)?.kind
                        return kind == .class || kind == .enumClass
                    }
                    if classSupertypes.isEmpty {
                        diagnostics.error(
                            "KSWIFTK-SEMA-0021",
                            "Cannot delegate to super: class has no superclass.",
                            range: delegation.range
                        )
                    }
                }
            }
        }
    }
}
