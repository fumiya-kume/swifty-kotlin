import Foundation

enum DataClassSyntheticMethodPhase {
    case beforeMemberHeaders
    case afterMemberHeaders
}

extension DataFlowSemaPhase {
    private func syntheticDataClassMemberTypeParameterSymbols(
        ownerSymbol: SymbolID,
        types: TypeSystem
    ) -> [SymbolID] {
        types.nominalTypeParameterSymbols(for: ownerSymbol)
    }

    func hasImportedLibrarySymbol(
        fqName: [InternedString],
        kind: SymbolKind,
        symbols: SymbolTable
    ) -> Bool {
        // Imported stdlib declarations own the public Kotlin surface; synthetic
        // fallback stubs should not reintroduce direct runtime links there.
        symbols.lookupAll(fqName: fqName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID) else {
                return false
            }
            return symbol.kind == kind && symbol.flags.contains(.importedLibrary)
        }
    }

    func hasSourceOrImportedLibrarySymbol(
        fqName: [InternedString],
        kind: SymbolKind,
        symbols: SymbolTable
    ) -> Bool {
        symbols.lookupAll(fqName: fqName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID), symbol.kind == kind else {
                return false
            }
            return symbol.flags.contains(.importedLibrary) || !symbol.flags.contains(.synthetic)
        }
    }

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
        case let .enumEntryDecl(enumEntryDecl):
            enumEntryDecl.annotations
        }
    }

    func registerAnnotations(
        for decl: Decl,
        symbol: SymbolID,
        declRange: SourceRange?,
        sourceFileID: FileID?,
        sourceManager: SourceManager?,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        registerAnnotations(
            declarationAnnotations(for: decl),
            symbol: symbol,
            declRange: declRange,
            sourceFileID: sourceFileID,
            sourceManager: sourceManager,
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
        sourceFileID: FileID?,
        sourceManager: SourceManager?,
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

        if let ksSymbolName = astAnnotations.first(where: { KnownCompilerAnnotation.ksSymbolName.matches($0.name) }) {
            if !isBundledSourceFile(sourceFileID, sourceManager: sourceManager) {
                diagnostics.error(
                    "KSWIFTK-SEMA-0007",
                    "@KsSymbolName is reserved for bundled stdlib declarations.",
                    range: declRange
                )
            }
            let symbolKind = symbols.symbol(symbol)?.kind
            if (symbolKind == .function || symbolKind == .constructor),
               let linkName = ksSymbolName.arguments.first.map(annotationStringArgumentValue(_:)),
               !linkName.isEmpty
            {
                symbols.setExternalLinkName(linkName, for: symbol)
            }
        }

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

    func diagnoseReservedExternalFunctionUse(
        _ function: FunDecl,
        sourceFileID: FileID,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine
    ) {
        guard function.modifiers.contains(.external),
              !isBundledSourceFile(sourceFileID, sourceManager: sourceManager)
        else {
            return
        }
        diagnostics.error(
            "KSWIFTK-SEMA-0008",
            "The external modifier is reserved for bundled stdlib declarations.",
            range: function.range
        )
    }

    private func isBundledSourceFile(_ fileID: FileID?, sourceManager: SourceManager?) -> Bool {
        guard let fileID, let sourceManager else {
            return false
        }
        return sourceManager.origin(of: fileID)?.isBundledStdlib == true
    }

    private func annotationStringArgumentValue(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let equals = trimmed.firstIndex(of: "=") {
            let name = trimmed[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "name" || name == "value" {
                trimmed = String(trimmed[trimmed.index(after: equals)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        while trimmed.count >= 2,
              let first = trimmed.first,
              let last = trimmed.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        return trimmed
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\'", with: "'")
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

    /// Assigns the compilation module FQN to every source symbol that has a source file but no
    /// explicit module (library imports set their own module FQN during `loadImportedLibrarySymbols`).
    func assignCompilationModuleFQNames(
        symbols: SymbolTable,
        moduleName: String,
        interner: StringInterner
    ) {
        let moduleFQN = interner.intern(moduleName)
        for symbol in symbols.allSymbols() where symbols.moduleFQN(for: symbol.id) == nil {
            if symbols.sourceFileID(for: symbol.id) != nil {
                symbols.setModuleFQN(moduleFQN, for: symbol.id)
            }
        }
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

    /// Computes the effective visibility for a class's constructor (primary or
    /// secondary) and whether that visibility was inherited from the owning
    /// class/object rather than written explicitly on the constructor itself.
    ///
    /// The distinction matters for `VisibilityChecker`: an inherited-private
    /// constructor's true accessibility ceiling is the owner's own visibility
    /// (e.g. file scope for a top-level `private class`), whereas an explicitly
    /// `private constructor` stays scoped to the class body/companion even when
    /// its owner happens to carry the same visibility keyword.
    func constructorVisibilityDetail(
        explicitModifiers: Modifiers,
        classKind: SymbolKind,
        isSealedClass: Bool,
        declarationVisibility: Visibility
    ) -> (visibility: Visibility, isInheritedFromOwner: Bool) {
        let explicitVisibilityModifiers: Modifiers = [.private, .internal, .protected, .public]
        if !explicitModifiers.isDisjoint(with: explicitVisibilityModifiers) {
            return (visibility(from: explicitModifiers), false)
        }
        if classKind == .class, isSealedClass {
            return (.protected, false)
        }
        return (declarationVisibility, true)
    }

    func primaryConstructorVisibilityDetail(
        for classDecl: ClassDecl,
        classKind: SymbolKind,
        declarationVisibility: Visibility
    ) -> (visibility: Visibility, isInheritedFromOwner: Bool) {
        constructorVisibilityDetail(
            explicitModifiers: classDecl.primaryConstructorModifiers,
            classKind: classKind,
            isSealedClass: classDecl.modifiers.contains(.sealed),
            declarationVisibility: declarationVisibility
        )
    }

    func primaryConstructorVisibility(
        for classDecl: ClassDecl,
        classKind: SymbolKind,
        declarationVisibility: Visibility
    ) -> Visibility {
        primaryConstructorVisibilityDetail(
            for: classDecl,
            classKind: classKind,
            declarationVisibility: declarationVisibility
        ).visibility
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

    func hasDeclarationConflict(
        newKind: SymbolKind,
        existing: [SemanticSymbol],
        symbols: SymbolTable? = nil,
        newIsExtensionProperty: Bool = false
    ) -> Bool {
        guard !existing.isEmpty else {
            return false
        }
        // Package symbols share the FQ-name table but live in a separate namespace,
        // so they never conflict with declarations in that package.
        if newKind == .package {
            return false
        }
        let nonPackageExisting = existing.filter { $0.kind != .package }
        guard !nonPackageExisting.isEmpty else {
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
            if newIsExtensionProperty, let symbols {
                return nonPackageExisting.contains { sym in
                    if isCallableLike(sym.kind) { return false }
                    if sym.kind == .property {
                        return symbols.extensionPropertyReceiverType(for: sym.id) == nil
                    }
                    return true
                }
            }
            return nonPackageExisting.contains { !isCallableLike($0.kind) }
        }
        if isCallableLike(newKind) {
            return nonPackageExisting.contains {
                !(isCallableLike($0.kind) || $0.kind == .property || isNominalTypeSymbol($0.kind))
            }
        }
        // KSP-CAP-006: a class/interface/object/enum/annotation-class/typealias
        // may coexist with a top-level function of the same name (e.g. `class
        // Random` + `fun Random(seed: Long): Random`, the real kotlin-stdlib
        // factory-function idiom). This mirrors the tolerance already granted
        // above for the opposite declaration order (callable declared first),
        // so the check no longer depends on which of the two comes first in
        // source order. A second nominal type (or a property) of the same name
        // still conflicts.
        if isNominalTypeSymbol(newKind) {
            return nonPackageExisting.contains { !isCallableLike($0.kind) }
        }
        if isOverloadableSymbol(newKind) {
            return nonPackageExisting.contains(where: { !isOverloadableSymbol($0.kind) })
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
        additionalExisting: [SemanticSymbol] = [],
        newIsExtensionProperty: Bool = false
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
            let existingNonPackage = existing.filter {
                $0.kind != .package && !$0.flags.contains(.synthetic)
            }
            if existingNonPackage.count == 1,
               let existingSymbol = existingNonPackage.first,
               isCompatibleExpectActualPair(newKind: newKind, newFlags: newFlags, existing: existingSymbol)
            {
                return
            }
            if existingNonPackage.isEmpty {
                return
            }
        }
        if newKind == .property,
           !newFlags.contains(.synthetic)
        {
            let existingNonPackage = existing.filter { $0.kind != .package }
            if !existingNonPackage.isEmpty,
               existingNonPackage.allSatisfy({ $0.kind == .property && $0.flags.contains(.synthetic) })
            {
                return
            }
        }
        if hasDeclarationConflict(
            newKind: newKind,
            existing: existing,
            symbols: symbols,
            newIsExtensionProperty: newIsExtensionProperty
        ) {
            diagnostics.error(
                "KSWIFTK-SEMA-0001",
                "Duplicate declaration in the same package scope.",
                range: range
            )
        }
    }

    private func hasUserDeclaredFunction(
        fqName: [InternedString],
        receiverType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        symbols: SymbolTable
    ) -> Bool {
        symbols.lookupAll(fqName: fqName).contains { id in
            guard let symbol = symbols.symbol(id),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let signature = symbols.functionSignature(for: id)
            else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
        }
    }

    /// Registers synthetic `toString(): String` for data types so member resolution finds it.
    func collectSyntheticToString(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        requireDataTypeFlag: Bool,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        if requireDataTypeFlag {
            guard symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true else {
                return
            }
        }
        let toStringName = interner.intern("toString")
        let toStringFQName = ownerFQName + [toStringName]
        let stringType = types.stringType
        let classTypeParameterSymbols = syntheticDataClassMemberTypeParameterSymbols(
            ownerSymbol: ownerSymbol,
            types: types
        )
        guard !hasUserDeclaredFunction(
            fqName: toStringFQName,
            receiverType: ownerType,
            parameterTypes: [],
            returnType: stringType,
            symbols: symbols
        ) else {
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
                typeParameterSymbols: classTypeParameterSymbols,
                classTypeParameterCount: classTypeParameterSymbols.count
            ),
            for: funcSymbol
        )
        scope.insert(funcSymbol)
    }

    /// Registers synthetic `equals(other: Any?): Boolean` for data types.
    func collectSyntheticEquals(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        requireDataTypeFlag: Bool,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        if requireDataTypeFlag {
            guard symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true else {
                return
            }
        }
        let equalsName = interner.intern("equals")
        let equalsFQName = ownerFQName + [equalsName]
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = types.nullableAnyType
        let classTypeParameterSymbols = syntheticDataClassMemberTypeParameterSymbols(
            ownerSymbol: ownerSymbol,
            types: types
        )
        guard !hasUserDeclaredFunction(
            fqName: equalsFQName,
            receiverType: ownerType,
            parameterTypes: [nullableAnyType],
            returnType: boolType,
            symbols: symbols
        ) else {
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
                typeParameterSymbols: classTypeParameterSymbols,
                classTypeParameterCount: classTypeParameterSymbols.count
            ),
            for: funcSymbol
        )
        scope.insert(funcSymbol)
    }

    /// Registers synthetic `hashCode(): Int` for data class so member resolution finds it.
    func collectSyntheticHashCode(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        requireDataTypeFlag: Bool,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        if requireDataTypeFlag {
            guard symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true else {
                return
            }
        }
        let hashCodeName = interner.intern("hashCode")
        let hashCodeFQName = ownerFQName + [hashCodeName]
        let intType = types.make(.primitive(.int, .nonNull))
        let classTypeParameterSymbols = syntheticDataClassMemberTypeParameterSymbols(
            ownerSymbol: ownerSymbol,
            types: types
        )
        guard !hasUserDeclaredFunction(
            fqName: hashCodeFQName,
            receiverType: ownerType,
            parameterTypes: [],
            returnType: intType,
            symbols: symbols
        ) else {
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
                typeParameterSymbols: classTypeParameterSymbols,
                classTypeParameterCount: classTypeParameterSymbols.count
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
                diagnostics: diagnostics,
                usageRange: classDecl.range
            ) ?? types.anyType
            let classTypeParameterSymbols = syntheticDataClassMemberTypeParameterSymbols(
                ownerSymbol: ownerSymbol,
                types: types
            )

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
                    typeParameterSymbols: classTypeParameterSymbols,
                    classTypeParameterCount: classTypeParameterSymbols.count
                ),
                for: funcSymbol
            )
            scope.insert(funcSymbol)
        }
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
        let classTypeParameterSymbols = syntheticDataClassMemberTypeParameterSymbols(
            ownerSymbol: ownerSymbol,
            types: types
        )

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: copyParams.paramTypes,
                returnType: ownerType,
                valueParameterSymbols: copyParams.paramSymbols,
                valueParameterHasDefaultValues: Array(repeating: true, count: copyParams.paramSymbols.count),
                valueParameterIsVararg: copyParams.paramIsVararg,
                valueParameterAllowsNonLocalReturn: copyParams.paramAllowsNonLocalReturn,
                typeParameterSymbols: classTypeParameterSymbols,
                classTypeParameterCount: classTypeParameterSymbols.count
            ),
            for: copySymbol
        )
        scope.insert(copySymbol)
    }

    func collectSyntheticDataClassMethods(
        classDecl: ClassDecl,
        ast: ASTModule,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        phase: DataClassSyntheticMethodPhase,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        localTypeParameters: [InternedString: SymbolID] = [:]
    ) {
        switch phase {
        case .beforeMemberHeaders:
            collectSyntheticDataClassComponentN(
                classDecl: classDecl,
                ast: ast,
                ownerSymbol: ownerSymbol,
                ownerFQName: ownerFQName,
                ownerType: ownerType,
                symbols: symbols,
                types: types,
                scope: scope,
                interner: interner,
                diagnostics: diagnostics,
                localTypeParameters: localTypeParameters
            )
            collectSyntheticDataClassCopy(
                classDecl: classDecl,
                ast: ast,
                ownerSymbol: ownerSymbol,
                ownerFQName: ownerFQName,
                ownerType: ownerType,
                symbols: symbols,
                types: types,
                scope: scope,
                interner: interner,
                diagnostics: diagnostics,
                localTypeParameters: localTypeParameters
            )
            collectSyntheticHashCode(
                ownerSymbol: ownerSymbol,
                ownerFQName: ownerFQName,
                ownerType: ownerType,
                requireDataTypeFlag: true,
                symbols: symbols,
                types: types,
                scope: scope,
                interner: interner
            )
        case .afterMemberHeaders:
            collectSyntheticToString(
                ownerSymbol: ownerSymbol,
                ownerFQName: ownerFQName,
                ownerType: ownerType,
                requireDataTypeFlag: true,
                symbols: symbols,
                types: types,
                scope: scope,
                interner: interner
            )
            collectSyntheticEquals(
                ownerSymbol: ownerSymbol,
                ownerFQName: ownerFQName,
                ownerType: ownerType,
                requireDataTypeFlag: true,
                symbols: symbols,
                types: types,
                scope: scope,
                interner: interner
            )
        }
    }

    /// Collects value parameters into parallel arrays of types, symbols, default-value flags,
    /// vararg flags, and non-local-return permissions. Shared by constructor and function
    /// header collection.
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
    ) -> (paramTypes: [TypeID], paramSymbols: [SymbolID], paramHasDefaultValues: [Bool], paramIsVararg: [Bool], paramAllowsNonLocalReturn: [Bool]) {
        var paramTypes: [TypeID] = []
        var paramSymbols: [SymbolID] = []
        var paramHasDefaultValues: [Bool] = []
        var paramIsVararg: [Bool] = []
        var paramAllowsNonLocalReturn: [Bool] = []
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
                diagnostics: diagnostics,
                usageRange: declSite
            ) ?? fallbackType
            paramTypes.append(resolvedType)
            paramSymbols.append(paramSymbol)
            paramHasDefaultValues.append(valueParam.hasDefaultValue)
            paramIsVararg.append(valueParam.isVararg)
            paramAllowsNonLocalReturn.append(!valueParam.isCrossinline && !valueParam.isNoinline)
        }
        return (paramTypes, paramSymbols, paramHasDefaultValues, paramIsVararg, paramAllowsNonLocalReturn)
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
                    localTypeParameters: localTypeParameters,
                    usageRange: declSite
                )
            }
            if !resolvedBounds.isEmpty {
                symbols.setTypeParameterUpperBounds(resolvedBounds, for: typeParamSym)
                symbols.recordTypeParameterForBoundConflictCheck(typeParamSym, declSite: declSite)
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
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex = .empty
    ) {
        let skipStats = SyntheticStubSkipStatsCollector()
        let shouldClearContextOnReturn =
            !BundledSyntheticStubRegistration.preBundledPass
            && !BundledSyntheticStubRegistration.postBundledPass
        defer {
            if shouldClearContextOnReturn {
                BundledSyntheticStubRegistration.clear()
            }
        }
        BundledSyntheticStubRegistration.bundledIndex = bundledIndex
        BundledSyntheticStubRegistration.types = types
        if BundledSyntheticStubRegistration.postBundledPass {
            registerSyntheticPostBundledMemberStubs(
                symbols: symbols,
                types: types,
                interner: interner
            )
            return
        }
        let kotlinPkg = ensureKotlinPackage(symbols: symbols, interner: interner)
        let kotlinPropertiesPkg = ensureKotlinPropertiesPackage(symbols: symbols, interner: interner)
        let registryContext = SyntheticDelegateStubRegistryContext(
            kotlinPkg: kotlinPkg,
            kotlinPropertiesPkg: kotlinPropertiesPkg,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )

        registerSyntheticDelegateRegistryStubs(
            symbols: symbols,
            types: types,
            interner: interner,
            context: registryContext
        )
        skipStats.logIfEnabled()
    }

    /// Replay deferred extension-member stub registration after bundled headers are indexed.
    func registerSyntheticPostBundledMemberStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let bundledIndex = BundledSyntheticStubRegistration.bundledIndex
        let skipStats = SyntheticStubSkipStatsCollector()
        defer {
            skipStats.logIfEnabled()
        }
        let kotlinPkg = ensureKotlinPackage(symbols: symbols, interner: interner)
        registerSyntheticCollectionStubs(
            symbols: symbols,
            types: types,
            interner: interner,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )
        patchKFunctionParametersType(symbols: symbols, types: types, interner: interner)
        patchKTypeArgumentsType(symbols: symbols, types: types, interner: interner)
        patchKTypeParameterUpperBoundsType(symbols: symbols, types: types, interner: interner)
        registerSyntheticRangeProgressionStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticRangeUntilStubs(symbols: symbols, types: types, interner: interner)
        if types.comparableInterfaceSymbol == nil {
            registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
        }
        registerSyntheticBuilderDSLStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticStringStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCharStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticMathStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCoroutineStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticExceptionStubs(symbols: symbols, types: types, interner: interner, kotlinPkg: kotlinPkg)
        registerSyntheticDurationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticInstantStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticClockStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticExperimentalTimeStubs(symbols: symbols, types: types, interner: interner, bundledIndex: bundledIndex)
        let stringBuilderOwner = [interner.intern("kotlin"), interner.intern("text"), interner.intern("StringBuilder")]
        if bundledIndex.contains(ownerFQName: stringBuilderOwner, name: interner.intern("append"), arity: 1) {
            patchSourceBackedStringBuilderSupertypes(symbols: symbols, types: types, interner: interner)
        } else {
            registerSyntheticStringBuilderStubs(symbols: symbols, types: types, interner: interner)
        }
        registerSyntheticTODOAndIOStubs(
            symbols: symbols,
            types: types,
            interner: interner,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )
        patchKPropertyFunctionSupertypes(symbols: symbols, types: types, interner: interner)
        patchKMutableProperty0FunctionSupertype(symbols: symbols, types: types, interner: interner)
        patchKMutableProperty1FunctionSupertype(symbols: symbols, types: types, interner: interner)
        registerSyntheticFileIOStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticPathStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCoercionStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticBucketedExtendedStdlibStubs(symbols: symbols, types: types, interner: interner)
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
        types.anyClassSymbol = anySymbol

        let annotationSymbol = ensureInterfaceSymbol(
            named: "Annotation",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        types.annotationInterfaceSymbol = annotationSymbol

        symbols.setDirectSupertypes([anySymbol], for: annotationSymbol)
        types.setNominalDirectSupertypes([anySymbol], for: annotationSymbol)

        // Register toString(), hashCode(), equals() as members of kotlin.Any so that
        // member calls on user-defined class instances resolve instead of producing <error>.
        guard let anyInfo = symbols.symbol(anySymbol) else { return }
        let anyClassType = types.make(.classType(ClassType(
            classSymbol: anySymbol, args: [], nullability: .nonNull)))

        // Kotlin/Native exposes Any's implicit public constructor in metadata,
        // although the actual class declaration is compiler-provided rather
        // than bundled Kotlin source. The KIR constructor path performs the
        // object allocation; no constructor body is emitted for this symbol.
        let anyConstructorName = interner.intern("<init>")
        let anyConstructorFQName = anyInfo.fqName + [anyConstructorName]
        if symbols.lookupAll(fqName: anyConstructorFQName).isEmpty {
            let constructorSymbol = symbols.define(
                kind: .constructor,
                name: anyConstructorName,
                fqName: anyConstructorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic])
            symbols.setParentSymbol(anySymbol, for: constructorSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: anyClassType,
                    isSuspend: false,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: []),
                for: constructorSymbol)
        }

        // Any has only the two-word object header and is the root of the
        // nominal allocation hierarchy. Keep its layout empty so the existing
        // Any member fallback remains responsible for toString/hashCode/equals
        // dispatch while constructors still receive a stable nominal type ID.
        if symbols.nominalLayout(for: anySymbol) == nil {
            symbols.setNominalLayout(
                NominalLayout(
                    objectHeaderWords: 2,
                    instanceFieldCount: 0,
                    instanceSizeWords: 2,
                    vtableSlots: [:],
                    itableSlots: [:],
                    superClass: nil),
                for: anySymbol)
        }

        let stringType = types.stringType
        let intType = types.intType
        let booleanType = types.booleanType
        let nullableAnyType = types.nullableAnyType

        let anyMemberSpecs: [(name: String, link: String, params: [TypeID], ret: TypeID)] = [
            ("toString", "kk_any_member_to_string", [], stringType),
            ("hashCode", "kk_any_member_hashCode", [], intType),
            ("equals",   "kk_any_member_equals",   [nullableAnyType], booleanType),
        ]
        for spec in anyMemberSpecs {
            let memberName = interner.intern(spec.name)
            let memberFQName = anyInfo.fqName + [memberName]
            if !symbols.lookupAll(fqName: memberFQName).isEmpty { continue }

            var paramSymbols: [SymbolID] = []
            for (i, paramType) in spec.params.enumerated() {
                let pName = interner.intern("p\(i)")
                let pSym = symbols.define(
                    kind: .valueParameter, name: pName,
                    fqName: memberFQName + [pName],
                    declSite: nil, visibility: .private, flags: [.synthetic])
                symbols.setPropertyType(paramType, for: pSym)
                paramSymbols.append(pSym)
            }

            let memberSymbol = symbols.define(
                kind: .function, name: memberName,
                fqName: memberFQName,
                declSite: nil, visibility: .public, flags: [.synthetic, .openType])
            symbols.setParentSymbol(anySymbol, for: memberSymbol)
            symbols.setExternalLinkName(spec.link, for: memberSymbol)
            for pSym in paramSymbols {
                symbols.setParentSymbol(memberSymbol, for: pSym)
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: anyClassType,
                    parameterTypes: spec.params,
                    returnType: spec.ret,
                    isSuspend: false,
                    valueParameterSymbols: paramSymbols,
                    valueParameterHasDefaultValues: Array(repeating: false, count: paramSymbols.count),
                    valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count)),
                for: memberSymbol)
        }
    }

    /// KSP-719: The bundled `kotlin/Annotation.kt` source declares
    /// `public interface Annotation {}` with no explicit supertype. That causes
    /// `bindInheritanceEdges` to overwrite the synthetic `Annotation` symbol's
    /// direct supertype list with an empty array, losing the `kotlin.Any`
    /// supertype that `registerSyntheticAnyStub` had installed. Restore it so
    /// `Any` member dispatch and nominal-subtype traversal stay intact.
    func patchBundledAnnotationSupertype(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let annotationSymbol = types.annotationInterfaceSymbol else { return }
        let anyFQName = [interner.intern("kotlin"), interner.intern("Any")]
        guard let anySymbol = symbols.lookup(fqName: anyFQName) else { return }

        let symbolSups = symbols.directSupertypes(for: annotationSymbol)
        if !symbolSups.contains(anySymbol) {
            let newSups = Array(Set(symbolSups + [anySymbol])).sorted(by: { $0.rawValue < $1.rawValue })
            symbols.setDirectSupertypes(newSups, for: annotationSymbol)
        }

        let typeSups = types.directNominalSupertypes(for: annotationSymbol)
        if !typeSups.contains(anySymbol) {
            types.setNominalDirectSupertypes(typeSups + [anySymbol], for: annotationSymbol)
        }
    }

    /// KSP-707: The bundled `kotlin/Preconditions.kt` source declares `require`/
    /// `check`/`assert` without a `contract { ... }` block, so their smart-cast
    /// narrowing (e.g. `require(x != null); x.length`) is not derived from the
    /// AST. Attach the `ContractNonNullEffect` directly to the source-backed
    /// symbols once header collection has registered them, so
    /// `applyContractEffects` can branch on the passed-in condition expression.
    func patchSourceBackedPreconditionContractEffects(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let lazyMessageType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let preconditionFunctions: [(name: String, parameterTypes: [TypeID])] = [
            ("require", [types.booleanType]),
            ("require", [types.booleanType, lazyMessageType]),
            ("check", [types.booleanType]),
            ("check", [types.booleanType, lazyMessageType]),
            ("assert", [types.booleanType]),
            ("assert", [types.booleanType, lazyMessageType]),
        ]

        for entry in preconditionFunctions {
            let functionName = interner.intern(entry.name)
            let functionFQName = kotlinPkg + [functionName]
            guard let symbol = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                guard let symbol = symbols.symbol(symbolID),
                      symbol.kind == .function,
                      // Symbols loaded from a precompiled stdlib library artifact
                      // (`--stdlib-library`, used by Scripts/diff_kotlinc.sh) carry
                      // both `.importedLibrary` and `.synthetic`, so only exclude
                      // synthetic placeholders that are NOT backed by an import.
                      !symbol.flags.contains(.synthetic) || symbol.flags.contains(.importedLibrary),
                      let signature = symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes == entry.parameterTypes
                    && signature.returnType == types.unitType
            }) else {
                continue
            }
            guard let signature = symbols.functionSignature(for: symbol),
                  !signature.valueParameterSymbols.isEmpty
            else {
                continue
            }
            symbols.setContractNonNullEffect(
                ContractNonNullEffect(
                    parameterSymbol: signature.valueParameterSymbols[0],
                    appliesOnAnyReturn: true
                ),
                for: symbol
            )
        }
    }

    func resolveNumberClassSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]? = nil
    ) {
        let kotlinPkg = kotlinPkg ?? ensureKotlinPackage(symbols: symbols, interner: interner)
        let numberName = interner.intern("Number")
        let numberFQName = kotlinPkg + [numberName]

        if let numberSymbol = symbols.lookup(fqName: numberFQName) {
            types.numberClassSymbol = numberSymbol
            return
        }

        guard let anySymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("Any")]) else { return }

        let numberSymbol = ensureClassSymbol(
            named: "Number",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.synthetic, .abstractType], for: numberSymbol)
        symbols.setDirectSupertypes([anySymbol], for: numberSymbol)
        types.setNominalDirectSupertypes([anySymbol], for: numberSymbol)
        types.numberClassSymbol = numberSymbol
    }

    /// Resolve the source-backed or imported kotlin.Unit object while
    /// preserving the compiler's builtin Unit value representation.
    func resolveUnitClassSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]? = nil
    ) {
        let kotlinPkg = kotlinPkg ?? ensureKotlinPackage(symbols: symbols, interner: interner)
        let unitName = BuiltinTypeNames(interner: interner).unit
        let unitFQName = kotlinPkg + [unitName]
        if let unitSymbol = symbols.lookupAll(fqName: unitFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .object
        }) {
            types.unitClassSymbol = unitSymbol
        }
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

    func ensureEnumClassSymbol(
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
            kind: .enumClass,
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
