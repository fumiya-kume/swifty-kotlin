import Foundation

extension DataFlowSemaPhase {
    func declarationAnnotations(for decl: Decl) -> [AnnotationNode] {
        switch decl {
        case let .classDecl(classDecl):
            classDecl.annotations
        case let .interfaceDecl(interfaceDecl):
            interfaceDecl.annotations
        case let .objectDecl(objectDecl):
            objectDecl.annotations
        case let .funDecl(funDecl):
            funDecl.annotations
        case let .propertyDecl(propertyDecl):
            propertyDecl.annotations
        case let .typeAliasDecl(typeAliasDecl):
            typeAliasDecl.annotations
        default:
            []
        }
    }

    func registerAnnotations(
        for decl: Decl,
        symbol: SymbolID,
        declRange: SourceRange?,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        registerAnnotations(
            declarationAnnotations(for: decl),
            symbol: symbol,
            declRange: declRange,
            symbols: symbols,
            diagnostics: diagnostics
        )

        guard let declRange else {
            return
        }
        guard let suppressionRange = suppressionRange(for: decl, declRange: declRange) else {
            return
        }
        for ann in declarationAnnotations(for: decl) where KnownCompilerAnnotation.suppress.matches(ann.name) {
            for arg in ann.arguments {
                let code = arg.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !code.isEmpty {
                    diagnostics.addSuppression(code: code, range: suppressionRange)
                }
            }
        }
    }

    func registerAnnotations(
        _ astAnnotations: [AnnotationNode],
        symbol: SymbolID,
        declRange: SourceRange?,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        guard !astAnnotations.isEmpty else {
            return
        }

        let records = astAnnotations.map { ann in
            MetadataAnnotationRecord(
                annotationFQName: ann.name,
                arguments: ann.arguments,
                useSiteTarget: ann.useSiteTarget
            )
        }
        symbols.setAnnotations(records, for: symbol)

        // Register @Suppress ranges so matching diagnostics are filtered.
        guard let declRange else {
            return
        }
        for ann in astAnnotations where KnownCompilerAnnotation.suppress.matches(ann.name) {
            for arg in ann.arguments {
                let code = arg.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !code.isEmpty {
                    diagnostics.addSuppression(code: code, range: declRange)
                }
            }
        }
    }

    private func suppressionRange(for decl: Decl, declRange: SourceRange?) -> SourceRange? {
        guard let declRange else {
            return nil
        }

        let bodyRange: SourceRange? = switch decl {
        case let .funDecl(funDecl):
            switch funDecl.body {
            case let .block(_, range), let .expr(_, range):
                range
            case .unit:
                nil
            }
        case let .propertyDecl(propertyDecl):
            switch (propertyDecl.getter?.body, propertyDecl.setter?.body) {
            case (let getterBody?, _):
                switch getterBody {
                case let .block(_, range), let .expr(_, range):
                    range
                case .unit:
                    nil
                }
            case (_, let setterBody?):
                switch setterBody {
                case let .block(_, range), let .expr(_, range):
                    range
                case .unit:
                    nil
                }
            default:
                nil
            }
        case let .classDecl(classDecl):
            classDecl.range
        case let .interfaceDecl(interfaceDecl):
            interfaceDecl.range
        case let .objectDecl(objectDecl):
            objectDecl.range
        case let .typeAliasDecl(typeAliasDecl):
            typeAliasDecl.range
        case let .enumEntryDecl(enumEntryDecl):
            enumEntryDecl.range
        }

        guard let bodyRange else {
            return declRange
        }
        return SourceRange(start: declRange.start, end: bodyRange.end)
    }

    func attachCompilerMetadataAnnotations(
        symbols: SymbolTable,
        types: TypeSystem,
        moduleName: String,
        interner: StringInterner
    ) {
        let encoder = MetadataEncoder()
        let targets = symbols.allSymbols().filter { symbol in
            guard Self.compilerMetadataAnnotatedKinds.contains(symbol.kind),
                  !symbol.flags.contains(.synthetic)
            else {
                return false
            }
            return !symbols.annotations(for: symbol.id).contains {
                KnownCompilerAnnotation.metadata.matches($0.annotationFQName)
            }
        }

        let recordsBySymbol = targets.reduce(into: [SymbolID: MetadataRecord]()) { partial, symbol in
            partial[symbol.id] = encoder.buildRecord(
                for: symbol,
                symbols: symbols,
                types: types,
                moduleName: moduleName,
                interner: interner
            )
        }

        for symbol in targets {
            guard let record = recordsBySymbol[symbol.id] else {
                continue
            }
            // Strip any existing kotlin.Metadata annotation before appending the new one
            // to prevent infinite nesting when the symbol is re-processed.
            var annotations = symbols.annotations(for: symbol.id).filter {
                !KnownCompilerAnnotation.metadata.matches($0.annotationFQName)
            }
            annotations.append(encoder.metadataAnnotationRecord(for: record))
            symbols.setAnnotations(annotations, for: symbol.id)
        }
    }

    private static let compilerMetadataAnnotatedKinds: Set<SymbolKind> = [
        .class,
        .interface,
        .object,
        .enumClass,
        .annotationClass,
    ]


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

    func restrictedVisibility(_ lhs: Visibility, _ rhs: Visibility) -> Visibility {
        switch (lhs, rhs) {
        case (.private, _), (_, .private):
            .private
        case (.protected, _), (_, .protected):
            .protected
        case (.internal, _), (_, .internal):
            .internal
        default:
            .public
        }
    }

    func primaryConstructorVisibility(
        for classDecl: ClassDecl,
        classKind: SymbolKind,
        declarationVisibility: Visibility
    ) -> Visibility {
        let explicitVisibilityModifiers: Modifiers = [.private, .internal, .protected, .public]
        let explicitVisibility = visibility(from: classDecl.primaryConstructorModifiers)
        if !classDecl.primaryConstructorModifiers.isDisjoint(with: explicitVisibilityModifiers) {
            return explicitVisibility
        }
        if classKind == .class,
           classDecl.modifiers.contains(.sealed)
        {
            return .protected
        }
        return declarationVisibility
    }

    func primaryConstructorVisibility(
        for classDecl: ClassDecl,
        classSymbol: SemanticSymbol?
    ) -> Visibility {
        primaryConstructorVisibility(
            for: classDecl,
            classKind: classSymbol?.kind ?? classSymbolKind(for: classDecl),
            declarationVisibility: classSymbol?.visibility ?? visibility(from: classDecl.modifiers)
        )
    }

    func hasCompilerAnnotation(
        _ annotation: KnownCompilerAnnotation,
        on annotations: [AnnotationNode]
    ) -> Bool {
        annotations.contains { annotation.matches($0.name) }
    }

    func dataClassUsesConsistentCopyVisibility(_ classDecl: ClassDecl) -> Bool {
        hasCompilerAnnotation(.consistentCopyVisibility, on: classDecl.annotations)
    }

    func dataClassUsesExposedCopyVisibility(_ classDecl: ClassDecl) -> Bool {
        hasCompilerAnnotation(.exposedCopyVisibility, on: classDecl.annotations)
    }

    func dataClassCopyVisibility(
        for classDecl: ClassDecl,
        classSymbol: SemanticSymbol?
    ) -> Visibility {
        guard dataClassUsesConsistentCopyVisibility(classDecl) else {
            return .public
        }
        return primaryConstructorVisibility(for: classDecl, classSymbol: classSymbol)
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
        // Note: .valueType is intentionally NOT set here. The `.value`
        // modifier should only produce the `.valueType` flag for class
        // declarations, which is handled explicitly in
        // HeaderCollection.collectHeader (classDecl branch). Setting it
        // here would incorrectly flag non-class declarations (functions,
        // interfaces, etc.) if the parser ever attaches a `.value`
        // modifier to them.
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
        if modifiers.contains(.lateinit) { value.insert(.lateinitProperty) }
    }

    func hasDeclarationConflict(newKind: SymbolKind, existing: [SemanticSymbol]) -> Bool {
        guard !existing.isEmpty else {
            return false
        }
        func isCallableLike(_ kind: SymbolKind) -> Bool {
            switch kind {
            case .function, .constructor:
                true
            default:
                false
            }
        }
        if newKind == .property {
            return existing.contains { !isCallableLike($0.kind) }
        }
        if isCallableLike(newKind) {
            return existing.contains { !isCallableLike($0.kind) && $0.kind != .property }
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
    /// This includes the `expect annotation class` + `actual typealias` shape used
    /// by `kotlin.concurrent.Volatile`.
    func checkAndReportDuplicateDeclaration(
        newKind: SymbolKind,
        fqName: [InternedString],
        range: SourceRange?,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        newFlags: SymbolFlags = [],
        additionalExisting: [SemanticSymbol] = []
    ) {
        var existingByID: [SymbolID: SemanticSymbol] = [:]
        for symbol in symbols.lookupAll(fqName: fqName).compactMap({ symbols.symbol($0) }) {
            existingByID[symbol.id] = symbol
        }
        for symbol in additionalExisting where symbol.fqName == fqName {
            existingByID[symbol.id] = symbol
        }
        let existing = Array(existingByID.values)
        if newFlags.contains(.expectDeclaration) || newFlags.contains(.actualDeclaration) {
            let existingNonPackage = existing.filter { $0.kind != .package }
            if existingNonPackage.count == 1,
               let existingSymbol = existingNonPackage.first,
               isCompatibleExpectActualPair(newKind: newKind, newFlags: newFlags, existing: existingSymbol)
            {
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

    /// Registers synthetic `toString(): String` for data object so member resolution finds it.
    func collectSyntheticDataObjectToString(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        objectType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        let toStringName = interner.intern("toString")
        let toStringFQName = ownerFQName + [toStringName]
        let stringType = types.make(.primitive(.string, .nonNull))
        let hasUserDeclaredToString = symbols.lookupAll(fqName: toStringFQName).contains { id in
            guard let symbol = symbols.symbol(id),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let signature = symbols.functionSignature(for: id)
            else {
                return false
            }
            return signature.receiverType == objectType
                && signature.parameterTypes.isEmpty
                && signature.returnType == stringType
        }
        guard !hasUserDeclaredToString else {
            return
        }
        let funcSymbol = symbols.define(
            kind: .function,
            name: toStringName,
            fqName: toStringFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: objectType,
                parameterTypes: [],
                returnType: stringType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: []
            ),
            for: funcSymbol
        )
        scope.insert(funcSymbol)
    }

    /// Registers synthetic `equals(other: Any?): Boolean` for data object (identity comparison).
    func collectSyntheticDataObjectEquals(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        objectType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        let equalsName = interner.intern("equals")
        let equalsFQName = ownerFQName + [equalsName]
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = types.nullableAnyType
        let hasUserDeclaredEquals = symbols.lookupAll(fqName: equalsFQName).contains { id in
            guard let symbol = symbols.symbol(id),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let signature = symbols.functionSignature(for: id)
            else {
                return false
            }
            return signature.receiverType == objectType
                && signature.parameterTypes == [nullableAnyType]
                && signature.returnType == boolType
        }
        guard !hasUserDeclaredEquals else {
            return
        }
        let funcSymbol = symbols.define(
            kind: .function,
            name: equalsName,
            fqName: equalsFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSymbol)
        let otherParamName = interner.intern("other")
        let otherParamSymbol = symbols.define(
            kind: .valueParameter,
            name: otherParamName,
            fqName: equalsFQName + [otherParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: objectType,
                parameterTypes: [nullableAnyType],
                returnType: boolType,
                isSuspend: false,
                valueParameterSymbols: [otherParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: []
            ),
            for: funcSymbol
        )
        scope.insert(funcSymbol)
    }

    /// Registers synthetic `hashCode(): Int` for data class so member resolution finds it.
    func collectSyntheticDataClassHashCode(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        guard symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true else {
            return
        }
        let hashCodeName = interner.intern("hashCode")
        let hashCodeFQName = ownerFQName + [hashCodeName]
        let intType = types.make(.primitive(.int, .nonNull))
        let hasUserDeclaredHashCode = symbols.lookupAll(fqName: hashCodeFQName).contains { id in
            guard let symbol = symbols.symbol(id),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let signature = symbols.functionSignature(for: id)
            else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == intType
        }
        guard !hasUserDeclaredHashCode else {
            return
        }
        let funcSymbol = symbols.define(
            kind: .function,
            name: hashCodeName,
            fqName: hashCodeFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: intType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: []
            ),
            for: funcSymbol
        )
        scope.insert(funcSymbol)
    }

    /// DATA-002 / STDLIB-090: Registers synthetic `componentN()` functions for each
    /// primary constructor parameter of a data class.
    /// `component1()` returns the first constructor property, `component2()` the second, etc.
    func collectSyntheticDataClassComponentN(
        classDecl: ClassDecl,
        ast: ASTModule,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        localTypeParameters: [InternedString: SymbolID] = [:]
    ) {
        for (index, param) in classDecl.primaryConstructorParams.enumerated() {
            let componentName = interner.intern("component\(index + 1)")
            let componentFQName = ownerFQName + [componentName]

            // Skip if a user-declared componentN already exists
            let hasUserDeclared = symbols.lookupAll(fqName: componentFQName).contains { id in
                guard let sym = symbols.symbol(id),
                      sym.kind == .function,
                      !sym.flags.contains(.synthetic)
                else { return false }
                return true
            }
            guard !hasUserDeclared else { continue }

            let returnType = resolveTypeRef(
                param.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters,
                diagnostics: diagnostics
            ) ?? types.anyType

            let funcSymbol = symbols.define(
                kind: .function,
                name: componentName,
                fqName: componentFQName,
                declSite: classDecl.range,
                visibility: restrictedVisibility(symbols.symbol(ownerSymbol)?.visibility ?? .public, .public),
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(ownerSymbol, for: funcSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: ownerType,
                    parameterTypes: [],
                    returnType: returnType,
                    isSuspend: false,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: []
                ),
                for: funcSymbol
            )
            scope.insert(funcSymbol)
        }
    }

    /// Registers synthetic `toString(): String` for data class so member resolution finds it.
    func collectSyntheticDataClassToString(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        guard symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true else {
            return
        }
        let toStringName = interner.intern("toString")
        let toStringFQName = ownerFQName + [toStringName]
        let stringType = types.make(.primitive(.string, .nonNull))
        let hasUserDeclaredToString = symbols.lookupAll(fqName: toStringFQName).contains { id in
            guard let symbol = symbols.symbol(id),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let signature = symbols.functionSignature(for: id)
            else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == stringType
        }
        guard !hasUserDeclaredToString else {
            return
        }
        let funcSymbol = symbols.define(
            kind: .function,
            name: toStringName,
            fqName: toStringFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: stringType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: []
            ),
            for: funcSymbol
        )
        scope.insert(funcSymbol)
    }

    /// Registers synthetic `equals(other: Any?): Boolean` for data class (structural comparison).
    func collectSyntheticDataClassEquals(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        guard symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true else {
            return
        }
        let equalsName = interner.intern("equals")
        let equalsFQName = ownerFQName + [equalsName]
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = types.nullableAnyType
        let hasUserDeclaredEquals = symbols.lookupAll(fqName: equalsFQName).contains { id in
            guard let symbol = symbols.symbol(id),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let signature = symbols.functionSignature(for: id)
            else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == [nullableAnyType]
                && signature.returnType == boolType
        }
        guard !hasUserDeclaredEquals else {
            return
        }
        let funcSymbol = symbols.define(
            kind: .function,
            name: equalsName,
            fqName: equalsFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSymbol)
        let otherParamName = interner.intern("other")
        let otherParamSymbol = symbols.define(
            kind: .valueParameter,
            name: otherParamName,
            fqName: equalsFQName + [otherParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [nullableAnyType],
                returnType: boolType,
                isSuspend: false,
                valueParameterSymbols: [otherParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: []
            ),
            for: funcSymbol
        )
        scope.insert(funcSymbol)
    }
    func collectSyntheticDataClassCopy(
        classDecl: ClassDecl,
        ast: ASTModule,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        localTypeParameters: [InternedString: SymbolID] = [:]
    ) {
        let copyName = interner.intern("copy")
        let copyFQName = ownerFQName + [copyName]
        guard symbols.lookupAll(fqName: copyFQName).isEmpty else {
            return
        }

        let ownerSemanticSymbol = symbols.symbol(ownerSymbol)
        let copyVisibility = dataClassCopyVisibility(
            for: classDecl,
            classSymbol: ownerSemanticSymbol
        )
        let copySymbol = symbols.define(
            kind: .function,
            name: copyName,
            fqName: copyFQName,
            declSite: classDecl.range,
            visibility: copyVisibility,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: copySymbol)

        let localNamespaceFQName = copyFQName + [interner.intern("$\(copySymbol.rawValue)")]
        let copyParams = collectValueParameters(
            classDecl.primaryConstructorParams,
            localNamespaceFQName: localNamespaceFQName,
            declSite: classDecl.range,
            ast: ast,
            symbols: symbols,
            types: types,
            interner: interner,
            localTypeParameters: localTypeParameters,
            diagnostics: diagnostics,
            fallbackType: types.anyType
        )

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: copyParams.paramTypes,
                returnType: ownerType,
                valueParameterSymbols: copyParams.paramSymbols,
                valueParameterHasDefaultValues: Array(repeating: true, count: copyParams.paramSymbols.count),
                valueParameterIsVararg: copyParams.paramIsVararg
            ),
            for: copySymbol
        )
        scope.insert(copySymbol)
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
        relativeOwnerFQName: [InternedString]? = nil,
        currentPackageFQName: [InternedString]? = nil,
        imports: [ImportDecl] = [],
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
                relativeOwnerFQName: relativeOwnerFQName,
                currentPackageFQName: currentPackageFQName,
                imports: imports,
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
            guard let typeParamSym = localTypeParameters[typeParam.name] else {
                continue
            }
            let resolvedBounds = typeParam.upperBounds.compactMap { boundRef in
                resolveTypeRef(
                    boundRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters
                )
            }
            if !resolvedBounds.isEmpty {
                symbols.setTypeParameterUpperBounds(resolvedBounds, for: typeParamSym)
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
        registerSyntheticAnyStub(symbols: symbols, types: types, interner: interner, kotlinPkg: kotlinPkg)
        let kotlinPropertiesPkg = ensureKotlinPropertiesPackage(symbols: symbols, interner: interner)
        registerSyntheticPropertyInterfaceStubs(
            symbols: symbols, types: types, interner: interner,
            kotlinPkg: kotlinPkg, kotlinPropertiesPkg: kotlinPropertiesPkg
        )
        // Random stubs must be registered before collection stubs so that
        // shuffled(random: Random) can look up the kotlin.random.Random symbol.
        registerSyntheticRandomStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCollectionStubs(symbols: symbols, types: types, interner: interner)
        // STDLIB-REFLECT-068: Now that List is registered, update KAnnotatedElement.annotations
        // to List<Annotation>.
        patchKAnnotatedElementAnnotationsType(symbols: symbols, types: types, interner: interner)
        // STDLIB-REFLECT-069: Now that Collection is registered, update
        // KDeclarationContainer.members to Collection<KCallable<*>>.
        patchKDeclarationContainerMembersType(symbols: symbols, types: types, interner: interner)
        // STDLIB-REFLECT-063: Now that List is registered, update KFunction.parameters type to
        // List<Any?> so that `.size` resolves correctly on the parameters property.
        patchKFunctionParametersType(symbols: symbols, types: types, interner: interner)
        // KType.arguments depends on kotlin.collections.List and KTypeProjection.
        patchKTypeArgumentsType(symbols: symbols, types: types, interner: interner)
        // KTypeParameter.upperBounds depends on kotlin.collections.List.
        patchKTypeParameterUpperBoundsType(symbols: symbols, types: types, interner: interner)
        registerSyntheticRangeProgressionStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticRangeUntilStubs(symbols: symbols, types: types, interner: interner)
        if types.comparableInterfaceSymbol == nil {
            registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
        }
        registerSyntheticBuilderDSLStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticComparatorStubs(symbols: symbols, types: types, interner: interner)
        patchArrayBinarySearchComparatorStub(symbols: symbols, types: types, interner: interner)
        patchArraySortedArrayWithComparatorStub(symbols: symbols, types: types, interner: interner)
        registerSyntheticComparisonStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticStringStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCharStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticMathStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticStdlibLoopStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticScopeFunctionStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticTestFrameworkStubs(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinPkg: kotlinPkg
        )
        registerSyntheticCoroutineStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticExceptionStubs(symbols: symbols, types: types, interner: interner, kotlinPkg: kotlinPkg)
        registerSyntheticContractStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticPreconditionStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticRegexStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticHexFormatStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticResultStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticKotlinVersionStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticDeepRecursiveStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticDurationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticInstantStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticClockStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticExperimentalTimeStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticPlatformTimeConversionStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticStringBuilderStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticTODOAndIOStubs(symbols: symbols, types: types, interner: interner)
        // Function interfaces are registered by TODO/IO stubs, so patch KProperty2's Function2 supertype here.
        patchKProperty2FunctionSupertype(symbols: symbols, types: types, interner: interner)
        registerSyntheticCloseableStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticFileIOStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticFilesUtilityStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticPathStubs(symbols: symbols, types: types, interner: interner)
        registerLateListIndexedMembers(symbols: symbols, types: types, interner: interner)
        registerSyntheticCoercionStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticEnumStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticAtomicStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticUuidStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticSerializationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticURIStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticURLStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNetworkStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticAdvancedNetworkStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticLoggingStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticSecurityStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCacheStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticResourceBundleStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticLocaleConstructorStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNumberFormatStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticDateFormatStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticMetaprogStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticBigIntegerStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticThreadLocalStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticConcurrencyStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCoroutineCancellationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCoroutineIntrinsicsStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticReadWriteLockStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsQualifierStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeRefRuntimeStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticBase64Stubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsModuleStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeConcurrentStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticExperimentalMarkerStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCoroutinesABIStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsExternalInheritorsOnlyStubs(symbols: symbols, interner: interner)
        registerSyntheticKPropertyIsInitializedStub(symbols: symbols, types: types, interner: interner)
    }

    /// Register the synthetic `kotlin.Any` and `kotlin.Annotation` built-in stubs.
    ///
    /// `Any` is needed as the root nominal type for default superclass binding, and
    /// `Annotation` is the built-in supertype used by annotation classes and the
    /// `Annotation` type name resolver.
    func registerSyntheticAnyStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]? = nil
    ) {
        let kotlinPkg = kotlinPkg ?? ensureKotlinPackage(symbols: symbols, interner: interner)

        let anySymbol = ensureClassSymbol(
            named: "Any",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )

        let annotationSymbol = ensureInterfaceSymbol(
            named: "Annotation",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        types.annotationInterfaceSymbol = annotationSymbol

        symbols.setDirectSupertypes([anySymbol], for: annotationSymbol)
        types.setNominalDirectSupertypes([anySymbol], for: annotationSymbol)
    }

    func registerSyntheticContractStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let contractsFQName = ensurePackage(
            path: ["kotlin", "contracts"],
            symbols: symbols,
            interner: interner
        )
        let contractsPkg = symbols.lookup(fqName: contractsFQName) ?? SymbolID.invalid
        let builderSymbol = ensureClassSymbol(
            named: "ContractBuilder",
            in: contractsFQName,
            symbols: symbols,
            interner: interner
        )
        let contractEffectSymbol = ensureInterfaceSymbol(
            named: "ContractEffect",
            in: contractsFQName,
            symbols: symbols,
            interner: interner
        )
        let effectSymbol = ensureInterfaceSymbol(
            named: "Effect",
            in: contractsFQName,
            symbols: symbols,
            interner: interner
        )
        let simpleEffectSymbol = ensureInterfaceSymbol(
            named: "SimpleEffect",
            in: contractsFQName,
            symbols: symbols,
            interner: interner
        )
        let conditionalEffectSymbol = ensureInterfaceSymbol(
            named: "ConditionalEffect",
            in: contractsFQName,
            symbols: symbols,
            interner: interner
        )
        let holdsInSymbol = ensureInterfaceSymbol(
            named: "HoldsIn",
            in: contractsFQName,
            symbols: symbols,
            interner: interner
        )
        if contractsPkg != .invalid {
            symbols.setParentSymbol(contractsPkg, for: builderSymbol)
            symbols.setParentSymbol(contractsPkg, for: contractEffectSymbol)
            symbols.setParentSymbol(contractsPkg, for: effectSymbol)
            symbols.setParentSymbol(contractsPkg, for: simpleEffectSymbol)
            symbols.setParentSymbol(contractsPkg, for: conditionalEffectSymbol)
            symbols.setParentSymbol(contractsPkg, for: holdsInSymbol)
        }

        let experimentalContractsSymbol = ensureAnnotationClassSymbol(
            named: "ExperimentalContracts",
            in: contractsFQName,
            symbols: symbols,
            interner: interner
        )
        if contractsPkg != .invalid {
            symbols.setParentSymbol(contractsPkg, for: experimentalContractsSymbol)
        }
        let experimentalContractsAnnotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.TYPEALIAS",
                ]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Retention",
                arguments: ["AnnotationRetention.BINARY"]
            ),
        ]
        var existingAnnotations = symbols.annotations(for: experimentalContractsSymbol)
        for annotation in experimentalContractsAnnotations where !existingAnnotations.contains(annotation) {
            existingAnnotations.append(annotation)
        }
        symbols.setAnnotations(existingAnnotations, for: experimentalContractsSymbol)

        let experimentalExtendedContractsSymbol = ensureAnnotationClassSymbol(
            named: "ExperimentalExtendedContracts",
            in: contractsFQName,
            symbols: symbols,
            interner: interner
        )
        if contractsPkg != .invalid {
            symbols.setParentSymbol(contractsPkg, for: experimentalExtendedContractsSymbol)
        }
        let experimentalExtendedContractsAnnotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.RequiresOptIn"
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.TYPEALIAS",
                ]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Retention",
                arguments: ["AnnotationRetention.BINARY"]
            ),
        ]
        var existingExtendedAnnotations = symbols.annotations(for: experimentalExtendedContractsSymbol)
        for annotation in experimentalExtendedContractsAnnotations where !existingExtendedAnnotations.contains(annotation) {
            existingExtendedAnnotations.append(annotation)
        }
        symbols.setAnnotations(existingExtendedAnnotations, for: experimentalExtendedContractsSymbol)

        let experimentalFQName = ensurePackage(
            path: ["kotlin", "experimental"],
            symbols: symbols,
            interner: interner
        )
        let experimentalPkg = symbols.lookup(fqName: experimentalFQName) ?? SymbolID.invalid
        let experimentalTypeInferenceSymbol = ensureAnnotationClassSymbol(
            named: "ExperimentalTypeInference",
            in: experimentalFQName,
            symbols: symbols,
            interner: interner
        )
        if experimentalPkg != SymbolID.invalid {
            symbols.setParentSymbol(experimentalPkg, for: experimentalTypeInferenceSymbol)
        }
        let experimentalTypeInferenceAnnotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.TYPE",
                    "AnnotationTarget.TYPEALIAS",
                ]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Retention",
                arguments: ["AnnotationRetention.BINARY"]
            ),
        ]
        var experimentalTypeInferenceExisting = symbols.annotations(for: experimentalTypeInferenceSymbol)
        for annotation in experimentalTypeInferenceAnnotations where !experimentalTypeInferenceExisting.contains(annotation) {
            experimentalTypeInferenceExisting.append(annotation)
        }
        symbols.setAnnotations(experimentalTypeInferenceExisting, for: experimentalTypeInferenceSymbol)

        let builderType = types.make(.classType(ClassType(classSymbol: builderSymbol, args: [], nullability: .nonNull)))
        let contractEffectType = types.make(.classType(ClassType(classSymbol: contractEffectSymbol, args: [], nullability: .nonNull)))
        let effectType = types.make(.classType(ClassType(classSymbol: effectSymbol, args: [], nullability: .nonNull)))
        let simpleEffectType = types.make(.classType(ClassType(classSymbol: simpleEffectSymbol, args: [], nullability: .nonNull)))
        let conditionalEffectType = types.make(.classType(ClassType(classSymbol: conditionalEffectSymbol, args: [], nullability: .nonNull)))
        let holdsInType = types.make(.classType(ClassType(classSymbol: holdsInSymbol, args: [], nullability: .nonNull)))

        symbols.setPropertyType(contractEffectType, for: contractEffectSymbol)
        symbols.setPropertyType(effectType, for: effectSymbol)
        symbols.setPropertyType(simpleEffectType, for: simpleEffectSymbol)
        symbols.setPropertyType(conditionalEffectType, for: conditionalEffectSymbol)
        symbols.setPropertyType(holdsInType, for: holdsInSymbol)

        symbols.setDirectSupertypes([contractEffectSymbol], for: effectSymbol)
        symbols.setDirectSupertypes([effectSymbol], for: simpleEffectSymbol)
        symbols.setDirectSupertypes([effectSymbol], for: conditionalEffectSymbol)
        symbols.setDirectSupertypes([effectSymbol], for: holdsInSymbol)

        let holdsInAnnotations = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.contracts.ExperimentalContracts"),
            MetadataAnnotationRecord(annotationFQName: "kotlin.contracts.ExperimentalExtendedContracts"),
        ]
        var existingHoldsInAnnotations = symbols.annotations(for: holdsInSymbol)
        for annotation in holdsInAnnotations where !existingHoldsInAnnotations.contains(annotation) {
            existingHoldsInAnnotations.append(annotation)
        }
        symbols.setAnnotations(existingHoldsInAnnotations, for: holdsInSymbol)

        let contractName = interner.intern("contract")
        let contractFQName = contractsFQName + [contractName]
        if symbols.lookup(fqName: contractFQName) == nil {
            let symbol = symbols.define(
                kind: .function,
                name: contractName,
                fqName: contractFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            let blockType = types.make(.functionType(FunctionType(
                receiver: builderType,
                params: [],
                returnType: types.unitType
            )))
            symbols.setFunctionSignature(
                FunctionSignature(parameterTypes: [blockType], returnType: types.unitType),
                for: symbol
            )
            if contractsPkg != .invalid {
                symbols.setParentSymbol(contractsPkg, for: symbol)
            }
        }

        func ensureMember(
            owner: SymbolID,
            ownerFQName: [InternedString],
            name: String,
            receiverType: TypeID,
            params: [TypeID],
            returnType: TypeID
        ) {
            let interned = interner.intern(name)
            let fqName = ownerFQName + [interned]
            // Check existing overloads by full signature (receiver type + parameter
            // types + return type) to allow functions with the same fqName but
            // different signatures, while preventing true duplicates.  Comparing
            // only parameter count would incorrectly treat overloads with the same
            // arity but different parameter types as duplicates.
            let existingIDs = symbols.lookupAll(fqName: fqName)
            let alreadyRegistered = existingIDs.contains { id in
                guard let sig = symbols.functionSignature(for: id) else { return false }
                return sig.receiverType == receiverType
                    && sig.parameterTypes == params
                    && sig.returnType == returnType
            }
            guard !alreadyRegistered else { return }
            let symbol = symbols.define(
                kind: .function,
                name: interned,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setFunctionSignature(
                FunctionSignature(receiverType: receiverType, parameterTypes: params, returnType: returnType),
                for: symbol
            )
            symbols.setParentSymbol(owner, for: symbol)
        }

        ensureMember(
            owner: builderSymbol,
            ownerFQName: contractsFQName + [interner.intern("ContractBuilder")],
            name: "returns",
            receiverType: builderType,
            params: [],
            returnType: simpleEffectType
        )
        ensureMember(
            owner: builderSymbol,
            ownerFQName: contractsFQName + [interner.intern("ContractBuilder")],
            name: "returns",
            receiverType: builderType,
            params: [types.booleanType],
            returnType: simpleEffectType
        )
        ensureMember(
            owner: simpleEffectSymbol,
            ownerFQName: contractsFQName + [interner.intern("SimpleEffect")],
            name: "implies",
            receiverType: simpleEffectType,
            params: [types.booleanType],
            returnType: conditionalEffectType
        )
        // STDLIB-593 stub: `ContractBuilder.returnsNotNull()` -- forward declaration
        // so that user code containing `contract { returnsNotNull() }` resolves.
        ensureMember(
            owner: builderSymbol,
            ownerFQName: contractsFQName + [interner.intern("ContractBuilder")],
            name: "returnsNotNull",
            receiverType: builderType,
            params: [],
            returnType: simpleEffectType
        )

        let holdsInName = interner.intern("holdsIn")
        let holdsInFQName = contractsFQName + [interner.intern("ContractBuilder"), holdsInName]
        let holdsInAlreadyDefined = symbols.lookupAll(fqName: holdsInFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == builderType
                && signature.parameterTypes.count == 2
                && signature.returnType == holdsInType
        }
        if !holdsInAlreadyDefined {
            let typeParamName = interner.intern("R")
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: holdsInFQName + [typeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let typeParamType = types.make(.typeParam(TypeParamType(
                symbol: typeParamSymbol,
                nullability: .nonNull
            )))
            let symbol = symbols.define(
                kind: .function,
                name: holdsInName,
                fqName: holdsInFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(builderSymbol, for: symbol)
            symbols.setParentSymbol(symbol, for: typeParamSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: builderType,
                    parameterTypes: [types.booleanType, typeParamType],
                    returnType: holdsInType,
                    typeParameterSymbols: [typeParamSymbol]
                ),
                for: symbol
            )
            symbols.setAnnotations(
                [MetadataAnnotationRecord(annotationFQName: "kotlin.contracts.ExperimentalExtendedContracts")],
                for: symbol
            )
        }

        // STDLIB-592: InvocationKind enum class stub
        let invocationKindSymbol = ensureClassSymbol(
            named: "InvocationKind",
            in: contractsFQName,
            symbols: symbols,
            interner: interner
        )
        if contractsPkg != .invalid {
            symbols.setParentSymbol(contractsPkg, for: invocationKindSymbol)
        }
        let invocationKindType = types.make(.classType(ClassType(
            classSymbol: invocationKindSymbol, args: [], nullability: .nonNull
        )))
        // Register enum entries: AT_MOST_ONCE, AT_LEAST_ONCE, EXACTLY_ONCE, UNKNOWN
        let invocationKindFQName = contractsFQName + [interner.intern("InvocationKind")]
        for entry in ["AT_MOST_ONCE", "AT_LEAST_ONCE", "EXACTLY_ONCE", "UNKNOWN"] {
            let entryName = interner.intern(entry)
            let entryFQName = invocationKindFQName + [entryName]
            if symbols.lookup(fqName: entryFQName) == nil {
                let entrySymbol = symbols.define(
                    kind: .property,
                    name: entryName,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .constValue]
                )
                symbols.setParentSymbol(invocationKindSymbol, for: entrySymbol)
            }
        }

        // STDLIB-592: callsInPlace overloads on ContractBuilder.
        let callsInPlaceName = interner.intern("callsInPlace")
        let callsInPlaceFQBase = contractsFQName + [interner.intern("ContractBuilder"), callsInPlaceName]
        func registerCallsInPlaceOverload(
            extraParameterTypes: [TypeID] = []
        ) {
            let parameterCount = extraParameterTypes.count + 1
            let alreadyDefined = symbols.lookupAll(fqName: callsInPlaceFQBase).contains { symbolID in
                guard let symbol = symbols.symbol(symbolID),
                      symbol.kind == .function,
                      let signature = symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.receiverType == builderType
                    && signature.parameterTypes.count == parameterCount
                    && signature.returnType == effectType
            }
            guard !alreadyDefined else {
                return
            }

            let typeParamName = interner.intern("P")
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: callsInPlaceFQBase + [typeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let typeParamType = types.make(.typeParam(TypeParamType(
                symbol: typeParamSymbol,
                nullability: .nonNull
            )))
            let parameterTypes = [typeParamType] + extraParameterTypes
            let symbol = symbols.define(
                kind: .function,
                name: callsInPlaceName,
                fqName: callsInPlaceFQBase,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(builderSymbol, for: symbol)
            symbols.setParentSymbol(symbol, for: typeParamSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: builderType,
                    parameterTypes: parameterTypes,
                    returnType: effectType,
                    typeParameterSymbols: [typeParamSymbol]
                ),
                for: symbol
            )
        }
        // Single-arg: callsInPlace(lambda)
        registerCallsInPlaceOverload()
        // Two-arg: callsInPlace(lambda, kind)
        registerCallsInPlaceOverload(extraParameterTypes: [invocationKindType])
    }

    /// Look up or define a synthetic interface symbol in the given package.
    func ensureInterfaceSymbol(
        named name: String,
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner,
        visibility: Visibility = .public
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .interface, name: internedName, fqName: fqName,
            declSite: nil, visibility: visibility, flags: [.synthetic]
        )
    }

    func ensureClassSymbol(
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
            kind: .class,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    func ensureAnnotationClassSymbol(
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
            kind: .annotationClass,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
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

    func ensurePackage(
        path: [String],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        var fqName: [InternedString] = []
        for component in path {
            let interned = interner.intern(component)
            fqName.append(interned)
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: interned,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
        return fqName
    }
}
