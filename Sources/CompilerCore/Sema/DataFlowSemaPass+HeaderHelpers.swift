import Foundation

extension DataFlowSemaPassPhase {
    /// Base value for synthetic type parameter symbol IDs used in metadata encoding.
    /// Shared between MetadataTypeSignatureParser (encoding) and collectSyntheticTypeParameters (decoding).
    static var syntheticTypeParameterBase: Int32 { -1_000_000 }

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
        if modifiers.contains(.inner) {
            value.insert(.innerClass)
        }
        if modifiers.contains(.operator) {
            value.insert(.operatorFunction)
        }
        return value
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
    func checkAndReportDuplicateDeclaration(
        newKind: SymbolKind,
        fqName: [InternedString],
        range: SourceRange?,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        let existing = symbols.lookupAll(fqName: fqName).compactMap { symbols.symbol($0) }
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
        if !reifiedIndices.isEmpty && !isInline {
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
    /// These are minimal stubs: just enough for name resolution and type checking to succeed.
    func registerSyntheticDelegateStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let anyType = types.anyType

        // Ensure the "kotlin" package exists.
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Register `lazy` as a top-level function in the kotlin package.
        // Kotlin signature: fun <T> lazy(initializer: () -> T): Lazy<T>
        let lazyName = interner.intern("lazy")
        let lazyFQName = kotlinPkg + [lazyName]
        if symbols.lookup(fqName: lazyFQName) == nil {
            let lazySymbol = symbols.define(
                kind: .function,
                name: lazyName,
                fqName: lazyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            // One parameter: the initializer lambda () -> T, returns Any (Lazy<T>)
            let initializerType = types.make(.functionType(FunctionType(
                params: [],
                returnType: anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [initializerType],
                    returnType: anyType
                ),
                for: lazySymbol
            )
        }

        // Ensure the "kotlin.properties" package exists.
        let kotlinPropertiesPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("properties")]
        if symbols.lookup(fqName: kotlinPropertiesPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("properties"),
                fqName: kotlinPropertiesPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Register `Delegates` as an object in kotlin.properties.
        let delegatesName = interner.intern("Delegates")
        let delegatesFQName = kotlinPropertiesPkg + [delegatesName]
        let delegatesSymbol: SymbolID
        if let existing = symbols.lookup(fqName: delegatesFQName) {
            delegatesSymbol = existing
        } else {
            delegatesSymbol = symbols.define(
                kind: .object,
                name: delegatesName,
                fqName: delegatesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let delegatesType = types.make(.classType(ClassType(classSymbol: delegatesSymbol, args: [], nullability: .nonNull)))
        // Set property type so inferNameRefExpr resolves `Delegates` to classType
        // (object symbols need an explicit property type for name-ref resolution).
        symbols.setPropertyType(delegatesType, for: delegatesSymbol)

        // Register `observable` as a member function of Delegates.
        // Kotlin signature: fun <T> observable(initialValue: T, onChange: ...): ReadWriteProperty<Any?, T>
        // NOTE: The callback lambda is parsed as a separate block by
        // propertyHeadTokens and is NOT included in the call arguments.
        // The sema stub therefore takes only 1 parameter (initialValue).
        let observableName = interner.intern("observable")
        let observableFQName = delegatesFQName + [observableName]
        if symbols.lookup(fqName: observableFQName) == nil {
            let observableSymbol = symbols.define(
                kind: .function,
                name: observableName,
                fqName: observableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(delegatesSymbol, for: observableSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: delegatesType,
                    parameterTypes: [anyType],
                    returnType: anyType
                ),
                for: observableSymbol
            )
        }

        // Register `vetoable` as a member function of Delegates.
        // Kotlin signature: fun <T> vetoable(initialValue: T, onChange: ...): ReadWriteProperty<Any?, T>
        // NOTE: Same as observable — callback lambda is a separate block.
        let vetoableName = interner.intern("vetoable")
        let vetoableFQName = delegatesFQName + [vetoableName]
        if symbols.lookup(fqName: vetoableFQName) == nil {
            let vetoableSymbol = symbols.define(
                kind: .function,
                name: vetoableName,
                fqName: vetoableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(delegatesSymbol, for: vetoableSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: delegatesType,
                    parameterTypes: [anyType],
                    returnType: anyType
                ),
                for: vetoableSymbol
            )
        }
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
                      let classSymbol = symbols.symbols(atDeclSite: classDecl.range).first(where: { id in
                          guard let sym = symbols.symbol(id) else { return false }
                          return sym.kind == .class || sym.kind == .enumClass || sym.kind == .annotationClass
                      }) else {
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
