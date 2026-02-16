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
                symbols: symbols,
                diagnostics: diagnostics
            )
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

        case .objectDecl(let objectDecl):
            _ = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            collectNestedTypeAliases(
                objectDecl.nestedTypeAliases,
                ownerFQName: fqName,
                symbols: symbols,
                diagnostics: diagnostics
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

        case .typeAliasDecl, .enumEntryDecl:
            break
        }
    }

    private func collectNestedTypeAliases(
        _ aliases: [TypeAliasDecl],
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
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
            _ = symbols.define(
                kind: .typeAlias,
                name: alias.name,
                fqName: aliasFQName,
                declSite: alias.range,
                visibility: visibility(from: alias.modifiers),
                flags: flags(from: alias.modifiers)
            )
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
}
