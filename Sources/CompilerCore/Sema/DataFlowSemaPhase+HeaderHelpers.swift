import Foundation

extension DataFlowSemaPhase {
    /// Base value for synthetic type parameter symbol IDs used in metadata encoding.
    /// Shared between MetadataTypeSignatureParser (encoding) and collectSyntheticTypeParameters (decoding).
    static var syntheticTypeParameterBase: Int32 {
        -1_000_000
    }

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

    func classSymbolKind(for classDecl: ClassDecl) -> SymbolKind {
        if classDecl.modifiers.contains(.annotationClass) {
            return .annotationClass
        }
        if classDecl.modifiers.contains(.enumModifier) {
            return .enumClass
        }
        return .class
    }

    func visibility(from modifiers: Modifiers) -> Visibility {
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

    func flags(from modifiers: Modifiers) -> SymbolFlags {
        var value: SymbolFlags = []
        insertFunctionFlags(modifiers, into: &value)
        insertTypeFlags(modifiers, into: &value)
        insertMemberFlags(modifiers, into: &value)
        return value
    }

    private func insertFunctionFlags(
        _ modifiers: Modifiers,
        into value: inout SymbolFlags
    ) {
        if modifiers.contains(.suspend) { value.insert(.suspendFunction) }
        if modifiers.contains(.inline) { value.insert(.inlineFunction) }
        if modifiers.contains(.operator) { value.insert(.operatorFunction) }
    }

    private func insertTypeFlags(
        _ modifiers: Modifiers,
        into value: inout SymbolFlags
    ) {
        if modifiers.contains(.sealed) { value.insert(.sealedType) }
        if modifiers.contains(.data) { value.insert(.dataType) }
        if modifiers.contains(.inner) { value.insert(.innerClass) }
        if modifiers.contains(.abstract) { value.insert(.abstractType) }
        if modifiers.contains(.open) { value.insert(.openType) }
    }

    private func insertMemberFlags(
        _ modifiers: Modifiers,
        into value: inout SymbolFlags
    ) {
        if modifiers.contains(.const) { value.insert(.constValue) }
        if modifiers.contains(.override) { value.insert(.overrideMember) }
        if modifiers.contains(.final) { value.insert(.finalMember) }
        if modifiers.contains(.expect) { value.insert(.expectDeclaration) }
        if modifiers.contains(.actual) { value.insert(.actualDeclaration) }
    }

    func hasDeclarationConflict(newKind: SymbolKind, existing: [SemanticSymbol]) -> Bool {
        guard !existing.isEmpty else {
            return false
        }
        if isOverloadableSymbol(newKind) {
            return existing.contains(where: { !isOverloadableSymbol($0.kind) })
        }
        return true
    }

    func isOverloadableSymbol(_ kind: SymbolKind) -> Bool {
        kind == .function || kind == .constructor
    }

    /// Checks for a duplicate declaration conflict at the given fully-qualified name and
    /// emits the standard KSWIFTK-SEMA-0001 diagnostic when a conflict is detected.
    /// An `expect` and `actual` pair sharing the same FQ name is NOT a conflict.
    func checkAndReportDuplicateDeclaration(
        newKind: SymbolKind,
        fqName: [InternedString],
        range: SourceRange?,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        newFlags: SymbolFlags = []
    ) {
        let existing = symbols.lookupAll(fqName: fqName).compactMap { symbols.symbol($0) }
        // Allow expect/actual pair: an expect and an actual with the same FQ name coexist,
        // but only when exactly one opposite-flag symbol of the same kind exists and no
        // same-flag duplicate is already present.
        if newFlags.contains(.expectDeclaration) || newFlags.contains(.actualDeclaration) {
            let isNewExpect = newFlags.contains(.expectDeclaration)
            let oppositeFlag: SymbolFlags = isNewExpect ? .actualDeclaration : .expectDeclaration
            let sameFlag: SymbolFlags = isNewExpect ? .expectDeclaration : .actualDeclaration
            let sameKindExisting = existing.filter { $0.kind == newKind }
            let hasSameFlagDuplicate = sameKindExisting.contains { $0.flags.contains(sameFlag) }
            let hasOppositeCounterpart = sameKindExisting.contains { $0.flags.contains(oppositeFlag) }
            if hasOppositeCounterpart, !hasSameFlagDuplicate {
                return
            }
        }
        if hasDeclarationConflict(newKind: newKind, existing: existing) {
            diagnostics.error(
                "KSWIFTK-SEMA-0001",
                "Duplicate declaration in the same package scope.",
                range: range
            )
        }
    }

    /// Collects value parameters into parallel arrays of types, symbols, default-value flags,
    /// and vararg flags.  Shared by constructor and function header collection.
    func collectValueParameters(
        _ valueParams: [ValueParamDecl],
        localNamespaceFQName: [InternedString],
        declSite: SourceRange?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        localTypeParameters: [InternedString: SymbolID] = [:],
        diagnostics: DiagnosticEngine? = nil,
        fallbackType: TypeID
    ) -> (paramTypes: [TypeID], paramSymbols: [SymbolID], paramHasDefaultValues: [Bool], paramIsVararg: [Bool]) {
        var paramTypes: [TypeID] = []
        var paramSymbols: [SymbolID] = []
        var paramHasDefaultValues: [Bool] = []
        var paramIsVararg: [Bool] = []
        for valueParam in valueParams {
            let paramFQName = localNamespaceFQName + [valueParam.name]
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: valueParam.name,
                fqName: paramFQName,
                declSite: declSite,
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
            ) ?? fallbackType
            paramTypes.append(resolvedType)
            paramSymbols.append(paramSymbol)
            paramHasDefaultValues.append(valueParam.hasDefaultValue)
            paramIsVararg.append(valueParam.isVararg)
        }
        return (paramTypes, paramSymbols, paramHasDefaultValues, paramIsVararg)
    }

    /// Collects type parameters from a function declaration, defining symbols and resolving
    /// upper bounds.  Returns the parallel arrays and maps needed by callers.
    func collectFunctionTypeParameters(
        _ typeParams: [TypeParamDecl],
        localNamespaceFQName: [InternedString],
        declSite: SourceRange?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        isInline: Bool,
        diagnostics: DiagnosticEngine
    ) -> (typeParameterSymbols: [SymbolID], localTypeParameters: [InternedString: SymbolID], reifiedIndices: Set<Int>) {
        var typeParameterSymbols: [SymbolID] = []
        var localTypeParameters: [InternedString: SymbolID] = [:]
        var reifiedIndices: Set<Int> = []
        for (index, typeParam) in typeParams.enumerated() {
            let typeParamFQName = localNamespaceFQName + [typeParam.name]
            let typeParamFlags: SymbolFlags = typeParam.isReified ? [.reifiedTypeParameter] : []
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParam.name,
                fqName: typeParamFQName,
                declSite: declSite,
                visibility: .private,
                flags: typeParamFlags
            )
            typeParameterSymbols.append(typeParamSymbol)
            localTypeParameters[typeParam.name] = typeParamSymbol
            if typeParam.isReified {
                reifiedIndices.insert(index)
            }
        }
        for typeParam in typeParams {
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
        if !reifiedIndices.isEmpty, !isInline {
            diagnostics.error(
                "KSWIFTK-SEMA-0020",
                "Only type parameters of inline functions can be reified",
                range: declSite
            )
        }
        return (typeParameterSymbols, localTypeParameters, reifiedIndices)
    }

    func registerTypeAliasTypeParameters(
        _ typeParams: [TypeParamDecl],
        aliasSymbol: SymbolID,
        parentFQName: [InternedString],
        declSite: SourceRange?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString: SymbolID] {
        var localTypeParameters: [InternedString: SymbolID] = [:]
        var typeParameterSymbols: [SymbolID] = []
        let localNamespaceFQName = parentFQName + [interner.intern("$\(aliasSymbol.rawValue)")]
        for typeParam in typeParams {
            let typeParamFQName = localNamespaceFQName + [typeParam.name]
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParam.name,
                fqName: typeParamFQName,
                declSite: declSite,
                visibility: .private,
                flags: []
            )
            typeParameterSymbols.append(typeParamSymbol)
            localTypeParameters[typeParam.name] = typeParamSymbol
        }
        if !typeParameterSymbols.isEmpty {
            symbols.setTypeAliasTypeParameters(typeParameterSymbols, for: aliasSymbol)
        }
        return localTypeParameters
    }

    /// Register synthetic stdlib symbols for property delegate functions so that
    /// sema can resolve `lazy { }`, `Delegates.observable(...)`, and `Delegates.vetoable(...)`.
    /// Also registers `kotlin.properties.Lazy<T>` and `kotlin.properties.ReadWriteProperty<T, V>`
    /// as interface stubs so that return types are structurally correct.
    /// These are minimal stubs: just enough for name resolution and type checking to succeed.
    func registerSyntheticDelegateStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensureKotlinPackage(symbols: symbols, interner: interner)
        let kotlinPropertiesPkg = ensureKotlinPropertiesPackage(symbols: symbols, interner: interner)
        registerSyntheticPropertyInterfaceStubs(
            symbols: symbols, types: types, interner: interner,
            kotlinPkg: kotlinPkg, kotlinPropertiesPkg: kotlinPropertiesPkg
        )
        registerSyntheticCollectionStubs(symbols: symbols, types: types, interner: interner)
    }

    /// Look up or define a synthetic interface symbol in the given package.
    func ensureInterfaceSymbol(
        named name: String,
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .interface, name: internedName, fqName: fqName,
            declSite: nil, visibility: .public, flags: [.synthetic]
        )
    }

    private func ensureKotlinPackage(symbols: SymbolTable, interner: StringInterner) -> [InternedString] {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package, name: interner.intern("kotlin"), fqName: kotlinPkg,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        return kotlinPkg
    }

    private func ensureKotlinPropertiesPackage(symbols: SymbolTable, interner: StringInterner) -> [InternedString] {
        let kotlinPropertiesPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("properties")]
        if symbols.lookup(fqName: kotlinPropertiesPkg) == nil {
            _ = symbols.define(
                kind: .package, name: interner.intern("properties"), fqName: kotlinPropertiesPkg,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        return kotlinPropertiesPkg
    }
}
