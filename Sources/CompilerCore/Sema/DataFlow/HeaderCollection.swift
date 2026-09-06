import Foundation

extension DataFlowSemaPhase {
    func isValueClassDeclaration(_ classDecl: ClassDecl) -> Bool {
        classDecl.modifiers.contains(.value) || classDecl.modifiers.contains(.inline)
    }

    func registerFileAnnotations(
        file: ASTFile,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard !file.annotations.isEmpty else {
            return
        }

        let packageSymbol = symbols.lookup(fqName: file.packageFQName.isEmpty ? [interner.intern("_root_")] : file.packageFQName)
        let records = file.annotations.map { annotation in
            MetadataAnnotationRecord(
                annotationFQName: annotation.name,
                arguments: annotation.arguments,
                useSiteTarget: annotation.useSiteTarget
            )
        }
        if let packageSymbol {
            var merged = symbols.annotations(for: packageSymbol)
            for record in records where !merged.contains(record) {
                merged.append(record)
            }
            symbols.setAnnotations(merged, for: packageSymbol)
        }

        for annotation in file.annotations where KnownCompilerAnnotation.suppress.matches(annotation.name) {
            guard let fileRange = file.range else {
                continue
            }
            for argument in annotation.arguments {
                let code = argument.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                diagnostics.addSuppression(code: code, range: fileRange)
            }
        }
    }

    /// Describes the symbol a top-level declaration introduces, without touching
    /// the symbol table. Shared by the forward-declaration pass and `collectHeader`
    /// so both agree on kind/visibility/flags.
    private func topLevelDeclarationDescriptor(
        for decl: Decl,
        diagnostics: DiagnosticEngine?
    ) -> (kind: SymbolKind, name: InternedString, range: SourceRange?, visibility: Visibility, flags: SymbolFlags)? {
        switch decl {
        case let .classDecl(classDecl):
            var classFlags = flags(from: classDecl.modifiers)
            classFlags.remove(.inlineFunction)
            if isValueClassDeclaration(classDecl) {
                classFlags.insert(.valueType)
            }

            // STDLIB-CLASS-010: Check for conflicting modifiers
            if classDecl.modifiers.contains(.abstract) && classDecl.modifiers.contains(.final) {
                diagnostics?.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Class cannot be both 'abstract' and 'final'.",
                    range: classDecl.range
                )
            }
            if classDecl.modifiers.contains(.sealed) && classDecl.modifiers.contains(.final) {
                diagnostics?.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Class cannot be both 'sealed' and 'final'.",
                    range: classDecl.range
                )
            }

            // STDLIB-CLASS-010: Abstract classes are implicitly open
            if classDecl.modifiers.contains(.abstract) {
                classFlags.insert(.openType)
            }
            // STDLIB-CLASS-010: Sealed classes are implicitly abstract
            if classDecl.modifiers.contains(.sealed) {
                classFlags.insert(.abstractType)
                classFlags.insert(.openType)
            }
            return (
                kind: classSymbolKind(for: classDecl),
                name: classDecl.name,
                range: classDecl.range,
                visibility: visibility(from: classDecl.modifiers),
                flags: classFlags
            )
        case let .interfaceDecl(interfaceDecl):
            var interfaceFlags = flags(from: interfaceDecl.modifiers)
            if interfaceDecl.isFunInterface {
                interfaceFlags.insert(.funInterface)
            }
            return (
                kind: .interface,
                name: interfaceDecl.name,
                range: interfaceDecl.range,
                visibility: visibility(from: interfaceDecl.modifiers),
                flags: interfaceFlags
            )
        case let .objectDecl(objectDecl):
            return (
                kind: .object,
                name: objectDecl.name,
                range: objectDecl.range,
                visibility: visibility(from: objectDecl.modifiers),
                flags: flags(from: objectDecl.modifiers)
            )
        case let .funDecl(funDecl):
            return (
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
            return (
                kind: .property,
                name: propertyDecl.name,
                range: propertyDecl.range,
                visibility: visibility(from: propertyDecl.modifiers),
                flags: propertyFlags
            )
        case let .typeAliasDecl(typeAliasDecl):
            return (
                kind: .typeAlias,
                name: typeAliasDecl.name,
                range: typeAliasDecl.range,
                visibility: visibility(from: typeAliasDecl.modifiers),
                flags: flags(from: typeAliasDecl.modifiers)
            )
        case let .enumEntryDecl(entry):
            return (
                kind: .field,
                name: entry.name,
                range: entry.range,
                visibility: .public,
                flags: []
            )
        }
    }

    private func defineTopLevelSymbol(
        declaration: (kind: SymbolKind, name: InternedString, range: SourceRange?, visibility: Visibility, flags: SymbolFlags),
        decl: Decl,
        file: ASTFile,
        symbols: SymbolTable,
        scope: Scope,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) -> SymbolID {
        let fqName = file.packageFQName + [declaration.name]
        let scopeExisting = scope.lookup(declaration.name).compactMap { symbolID -> SemanticSymbol? in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.fqName == fqName
            else {
                return nil
            }
            return symbol
        }
        let newIsExtensionProperty: Bool
        if case let .propertyDecl(pd) = decl {
            newIsExtensionProperty = pd.receiverType != nil
        } else {
            newIsExtensionProperty = false
        }
        let reusableSyntheticSymbol = reusableSyntheticDeclarationSymbol(
            kind: declaration.kind,
            fqName: fqName,
            declarationFlags: declaration.flags,
            file: file,
            sourceManager: sourceManager,
            symbols: symbols
        )
        if reusableSyntheticSymbol == nil {
            checkAndReportDuplicateDeclaration(
                newKind: declaration.kind,
                fqName: fqName,
                range: declaration.range,
                symbols: symbols,
                diagnostics: diagnostics,
                newFlags: declaration.flags,
                additionalExisting: scopeExisting,
                newIsExtensionProperty: newIsExtensionProperty
            )
        }
        let symbol: SymbolID
        if let reusableSyntheticSymbol {
            symbol = reusableSyntheticSymbol
            symbols.removeFlags(.synthetic, for: symbol)
            // Preserve semantic modifiers from the bundled declaration when a
            // predeclared synthetic placeholder is reused. Without this,
            // abstract/open/sealed flags are lost for source-backed types such
            // as kotlin.random.Random.
            symbols.insertFlags(declaration.flags, for: symbol)
            if shouldRestoreDeclSiteForReusableSyntheticSymbol(fqName: fqName, interner: interner) {
                symbols.setDeclSite(declaration.range, for: symbol)
            }
        } else {
            symbol = symbols.define(
                kind: declaration.kind,
                name: declaration.name,
                fqName: fqName,
                declSite: declaration.range,
                visibility: declaration.visibility,
                flags: declaration.flags,
                isExtensionProperty: newIsExtensionProperty
            )
        }
        symbols.setSourceFileID(file.fileID, for: symbol)
        scope.insert(symbol)
        return symbol
    }

    /// BUG-143: Registers the symbols of top-level nominal type declarations
    /// (class/interface/object/typealias) before any signature type annotation is
    /// resolved, so declarations can reference types declared further down in the
    /// same file. Returns the pre-registered symbols keyed by declaration so that
    /// `collectHeader` reuses them instead of defining a second symbol.
    ///
    /// Idempotent per `declID`: a declaration already present in `predeclared`
    /// (e.g. from `predeclareBundledTupleHeaders`'s earlier, narrower pass) is
    /// left untouched rather than defined a second time.
    func predeclareNominalTypeHeaders(
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        scope: Scope,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        for declID in file.topLevelDecls {
            guard predeclared[declID] == nil else { continue }
            guard let decl = ast.arena.decl(declID) else { continue }
            switch decl {
            case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                break
            case .funDecl, .propertyDecl, .enumEntryDecl:
                continue
            }
            guard let declaration = topLevelDeclarationDescriptor(for: decl, diagnostics: nil) else {
                continue
            }
            predeclared[declID] = defineTopLevelSymbol(
                declaration: declaration,
                decl: decl,
                file: file,
                symbols: symbols,
                scope: scope,
                sourceManager: sourceManager,
                diagnostics: diagnostics,
                interner: interner
            )
        }
    }

    /// KSP-706: forward-declares `kotlin.Pair`/`kotlin.Triple` from their bundled
    /// `Tuples.kt` source before early synthetic stub registration runs. Several
    /// stub registrations (list/map/sequence `zip`/`partition`/`unzip`, ...)
    /// build `Pair<...>` return types and look the class up by name well before
    /// `collectAllHeaders` visits `Tuples.kt` in the normal pass. Running this
    /// narrow slice of `predeclareNominalTypeHeaders` first gives them the real
    /// class symbol directly, instead of routing through a throwaway synthetic
    /// placeholder that `collectHeader` swaps out later.
    ///
    /// Configurations with neither bundled stdlib source nor a merged library
    /// import (e.g. `--no-stdlib`) never get a real declaration for `Pair`/
    /// `Triple` at all, so a bare synthetic shell is defined as a fallback for
    /// whichever of the two names is still unresolved afterward -- matching
    /// what the deleted `HeaderHelpers+SyntheticPairTripleAnchors.swift` did
    /// unconditionally, but only as a last resort now.
    func predeclareBundledTupleHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let pairName = interner.intern("Pair")
        let tripleName = interner.intern("Triple")
        let kotlinPkg = [interner.intern("kotlin")]
        for file in ast.sortedFiles where file.packageFQName == kotlinPkg {
            let declaresTupleClass = file.topLevelDecls.contains { declID in
                guard case let .classDecl(classDecl)? = ast.arena.decl(declID) else { return false }
                return classDecl.name == pairName || classDecl.name == tripleName
            }
            guard declaresTupleClass, let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
        for name in [pairName, tripleName] {
            let fqName = kotlinPkg + [name]
            if let existing = symbols.lookup(fqName: fqName) {
                // Compatibility shells intentionally keep a nil declSite so bundled
                // source declarations do not displace them in golden semantic dumps
                // (`GoldenHarnessDump.isExcludedBundledSymbol` filters bundled-file
                // declSites out; the pre-KSP-706 anchor never restored declSite for
                // Pair/Triple either -- see `shouldRestoreDeclSiteForReusableSyntheticSymbol`).
                symbols.setDeclSite(nil, for: existing)
            } else {
                _ = symbols.define(
                    kind: .class,
                    name: name,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
    }

    /// KSP-711: forward-declares `Charset` and `Charsets` from
    /// `StringEncoding.kt` before synthetic FileIO bridges are registered.
    /// Their source symbols must be available while bridge signatures are
    /// constructed; `collectAllHeaders` later fills in the complete headers.
    func predeclareBundledStringEncodingHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let charsetFQName = [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("Charset"),
        ]
        guard symbols.lookup(fqName: charsetFQName) == nil else { return }

        for file in ast.sortedFiles
            where sourceManager.path(of: file.fileID) == "__bundled_kotlin/text/StringEncoding.kt"
        {
            guard let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
        if let charsetSymbol = symbols.lookup(fqName: charsetFQName) {
            // Keep the source file association for metadata and declaration
            // binding, while retaining the historical compatibility-shell
            // visibility used by semantic inventory goldens. The normal header
            // pass still fills the source-backed declaration details.
            symbols.setDeclSite(nil, for: charsetSymbol)
        }
    }

    /// KSP-918: forward-declare the six `kotlin.annotation` core declarations
    /// before synthetic annotation bootstrap runs. Their source declarations
    /// refer to one another through `@Target`, `@Retention`, and
    /// `@MustBeDocumented`, so the symbols must exist before annotations are
    /// registered on the first source header.
    func predeclareBundledAnnotationHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [interner.intern("kotlin"), interner.intern("annotation")]
        let coreNames: Set<InternedString> = [
            interner.intern("AnnotationRetention"),
            interner.intern("AnnotationTarget"),
            interner.intern("MustBeDocumented"),
            interner.intern("Repeatable"),
            interner.intern("Retention"),
            interner.intern("Target"),
        ]

        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresCoreType = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case let .classDecl(classDecl):
                    return coreNames.contains(classDecl.name)
                case let .interfaceDecl(interfaceDecl):
                    return coreNames.contains(interfaceDecl.name)
                case let .objectDecl(objectDecl):
                    return coreNames.contains(objectDecl.name)
                case let .typeAliasDecl(typeAliasDecl):
                    return coreNames.contains(typeAliasDecl.name)
                default:
                    return false
                }
            }
            guard declaresCoreType, let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            predeclareNominalTypeHeaders(
                file: file,
                ast: ast,
                symbols: symbols,
                scope: fileScope,
                sourceManager: sourceManager,
                diagnostics: diagnostics,
                interner: interner,
                into: &predeclared
            )
        }
    }

    /// KSP-1522: forward-declares the source-backed `kotlin.random.Random` and
    /// `java.util.Random` nominal types before synthetic collection and Sequence
    /// members resolve their parameter types. `JavaRandomInterop.kt` can also be
    /// collected before `JavaUtilRandom.kt`, so both owners must be available in
    /// the same early pass.
    func predeclareBundledRandomHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let targets: [([InternedString], InternedString)] = [
            (
                [interner.intern("kotlin"), interner.intern("random")],
                interner.intern("Random")
            ),
            (
                [interner.intern("java"), interner.intern("util")],
                interner.intern("Random")
            ),
        ]
        for (packageFQName, targetName) in targets {
            for file in ast.sortedFiles where file.packageFQName == packageFQName {
                let declaresTargetNominal = file.topLevelDecls.contains { declID in
                    guard let decl = ast.arena.decl(declID) else { return false }
                    switch decl {
                    case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                        return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                    case .funDecl, .propertyDecl, .enumEntryDecl:
                        return false
                    }
                }
                guard declaresTargetNominal,
                      let fileScope = fileScopes[file.fileID.rawValue]
                else { continue }
                predeclareNominalTypeHeaders(
                    file: file, ast: ast, symbols: symbols, scope: fileScope,
                    sourceManager: sourceManager, diagnostics: diagnostics,
                    interner: interner, into: &predeclared
                )
            }
        }
    }

    /// KSP-1150: forward-declares the source-backed cancellation nominal before
    /// residual coroutine registration needs its type and constructor owner.
    func predeclareBundledCancellationExceptionHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
            interner.intern("cancellation"),
        ]
        let targetName = interner.intern("CancellationException")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTarget = file.topLevelDecls.contains { declID in
                guard case let .classDecl(classDecl)? = ast.arena.decl(declID) else {
                    return false
                }
                return classDecl.name == targetName
            }
            guard declaresTarget,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file,
                ast: ast,
                symbols: symbols,
                scope: fileScope,
                sourceManager: sourceManager,
                diagnostics: diagnostics,
                interner: interner,
                into: &predeclared
            )
        }
    }

    /// KSP-1210: forward-declares the source-backed Native OsFamily enum before
    /// Platform.osFamily's retained runtime bridge resolves its property type.
    func predeclareBundledOsFamilyHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [interner.intern("kotlin"), interner.intern("native")]
        let targetName = interner.intern("OsFamily")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTargetNominal = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTargetNominal,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-1266: forward-declares the source-backed Native MemoryUsage class
    /// before GCInfo's residual synthetic properties resolve their value type.
    func predeclareBundledMemoryUsageHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [
            interner.intern("kotlin"),
            interner.intern("native"),
            interner.intern("runtime"),
        ]
        let targetName = interner.intern("MemoryUsage")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTargetNominal = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTargetNominal,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-1334: forward-declares the source-backed KTypeProjection nominal
    /// before reflection synthetic stubs resolve its property owner.
    func predeclareBundledKTypeProjectionHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [interner.intern("kotlin"), interner.intern("reflect")]
        let targetName = interner.intern("KTypeProjection")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTarget = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTarget,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-1337: forward-declares the source-backed KVariance enum before
    /// reflection synthetic stubs construct signatures that reference it.
    func predeclareBundledKVarianceHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [interner.intern("kotlin"), interner.intern("reflect")]
        let targetName = interner.intern("KVariance")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTarget = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTarget,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func collectHeader(
        declID: DeclID,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        ctx: CompilationContext,
        predeclaredSymbol: SymbolID? = nil
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        let package = file.packageFQName
        let anyType = types.anyType
        let unitType = types.unitType

        guard let declaration = topLevelDeclarationDescriptor(
            for: decl,
            diagnostics: diagnostics
        ) else { return }
        let fqName = package + [declaration.name]
        let symbol = predeclaredSymbol ?? defineTopLevelSymbol(
            declaration: declaration,
            decl: decl,
            file: file,
            symbols: symbols,
            scope: scope,
            sourceManager: sourceManager,
            diagnostics: diagnostics,
            interner: interner
        )
        bindings.bindDecl(declID, symbol: symbol)

        if case let .funDecl(funDecl) = decl {
            diagnoseReservedExternalFunctionUse(
                funDecl,
                sourceFileID: file.fileID,
                sourceManager: sourceManager,
                diagnostics: diagnostics
            )
        }
        registerAnnotations(
            for: decl,
            symbol: symbol,
            declRange: declaration.range,
            sourceFileID: file.fileID,
            sourceManager: sourceManager,
            symbols: symbols,
            diagnostics: diagnostics
        )
        attachUuidSourceMigrationClassAnnotationIfNeeded(
            to: symbol,
            fqName: fqName,
            sourceFileID: file.fileID,
            ctx: ctx,
            symbols: symbols,
            interner: interner
        )

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
                sourceFileID: file.fileID,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )

            // Nested class/object headers must be collected before the primary
            // constructor parameter types are resolved, because those parameter
            // types (or their default values) may reference a nested type
            // (e.g. `annotation class RequiresOptIn(val level: Level = Level.ERROR)`).
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: [],
                    properties: [],
                    nestedClasses: classDecl.nestedClasses,
                    nestedObjects: classDecl.nestedObjects
                ),
                owner: OwnerContext(fqName: fqName, symbol: symbol, type: classType),
                sourceFileID: file.fileID,
                ctx: ctx,
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
                let primaryCtorVisibilityDetail = primaryConstructorVisibilityDetail(
                    for: classDecl,
                    classKind: declaration.kind,
                    declarationVisibility: declaration.visibility
                )
                let primaryCtorSymbol = symbols.define(
                    kind: .constructor,
                    name: declaration.name,
                    fqName: primaryCtorFQName,
                    declSite: classDecl.range,
                    visibility: primaryCtorVisibilityDetail.visibility,
                    flags: primaryCtorVisibilityDetail.isInheritedFromOwner ? [.constructorVisibilityInherited] : []
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
                        relativeOwnerFQName: fqName,
                        currentPackageFQName: package,
                        imports: file.imports,
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
                            valueParameterAllowsNonLocalReturn: params.paramAllowsNonLocalReturn,
                            typeParameterSymbols: classTypeParamSymbols,
                            classTypeParameterCount: classTypeParamSymbols.count
                        ),
                        for: primaryCtorSymbol
                    )
                    registerAnnotations(
                        classDecl.primaryConstructorAnnotations,
                        symbol: primaryCtorSymbol,
                        declRange: classDecl.range,
                        sourceFileID: file.fileID,
                        sourceManager: sourceManager,
                        symbols: symbols,
                        diagnostics: diagnostics
                    )
                }
            }

            for (ctorIndex, secondaryCtor) in classDecl.secondaryConstructors.enumerated() {
                let secCtorVisibilityDetail = constructorVisibilityDetail(
                    explicitModifiers: secondaryCtor.modifiers,
                    classKind: declaration.kind,
                    isSealedClass: classDecl.modifiers.contains(.sealed),
                    declarationVisibility: declaration.visibility
                )
                let secCtorSymbol = symbols.define(
                    kind: .constructor,
                    name: declaration.name,
                    fqName: primaryCtorFQName,
                    declSite: secondaryCtor.range,
                    visibility: secCtorVisibilityDetail.visibility,
                    flags: secCtorVisibilityDetail.isInheritedFromOwner ? [.constructorVisibilityInherited] : []
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
                    relativeOwnerFQName: fqName,
                    currentPackageFQName: package,
                    imports: file.imports,
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
                        valueParameterAllowsNonLocalReturn: params.paramAllowsNonLocalReturn,
                        typeParameterSymbols: classTypeParamSymbols,
                        classTypeParameterCount: classTypeParamSymbols.count
                    ),
                    for: secCtorSymbol
                )
                registerAnnotations(
                    secondaryCtor.annotations,
                    symbol: secCtorSymbol,
                    declRange: secondaryCtor.range,
                    sourceFileID: file.fileID,
                    sourceManager: sourceManager,
                    symbols: symbols,
                    diagnostics: diagnostics
                )
            }

            // Value class validation: must have exactly one primary constructor parameter
            if isValueClassDeclaration(classDecl) {
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
                        relativeOwnerFQName: fqName,
                        currentPackageFQName: package,
                        imports: file.imports,
                        diagnostics: diagnostics,
                        usageRange: classDecl.range
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
                    symbols.setParentSymbol(symbol, for: entrySymbol)
                    symbols.setPropertyType(classType, for: entrySymbol)
                    classScope.insert(entrySymbol)
                }
                collectSyntheticEnumEntryProperties(
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    symbols: symbols,
                    types: types,
                    scope: classScope,
                    interner: interner
                )
                collectSyntheticEnumValuesMember(
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    enumType: classType,
                    symbols: symbols,
                    types: types,
                    scope: classScope,
                    interner: interner
                )
            }
            if declaration.flags.contains(.dataType) {
                collectSyntheticDataClassMethods(
                    classDecl: classDecl,
                    ast: ast,
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    ownerType: classType,
                    phase: .beforeMemberHeaders,
                    symbols: symbols,
                    types: types,
                    scope: classScope,
                    interner: interner,
                    diagnostics: diagnostics,
                    localTypeParameters: classLocalTypeParameters
                )
            }
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: classDecl.memberFunctions,
                    properties: classDecl.memberProperties,
                    nestedClasses: [],
                    nestedObjects: []
                ),
                owner: OwnerContext(fqName: fqName, symbol: symbol, type: classType),
                sourceFileID: file.fileID,
                ctx: ctx,
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
            if declaration.flags.contains(.dataType) {
                collectSyntheticDataClassMethods(
                    classDecl: classDecl,
                    ast: ast,
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    ownerType: classType,
                    phase: .afterMemberHeaders,
                    symbols: symbols,
                    types: types,
                    scope: classScope,
                    interner: interner,
                    diagnostics: diagnostics,
                    localTypeParameters: classLocalTypeParameters
                )
            }
            // Process companion object: register as nested object and link to owner class
            if let companionDeclID = classDecl.companionObject {
                collectCompanionObjectHeader(
                    companionDeclID: companionDeclID,
                    ownerFQName: fqName,
                    ownerSymbol: symbol,
                    ownerType: classType,
                    sourceFileID: file.fileID,
                    ctx: ctx,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: classScope,
                    diagnostics: diagnostics,
                    interner: interner
                )
            } else if declaration.kind == .enumClass {
                // Synthesize implicit companion for enum classes (valueOf, entries)
                let companionName = interner.intern("Companion")
                let companionFQName = fqName + [companionName]
                let companionSymbol = symbols.define(
                    kind: .object,
                    name: companionName,
                    fqName: companionFQName,
                    declSite: classDecl.range,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(symbol, for: companionSymbol)
                symbols.setCompanionObjectSymbol(companionSymbol, for: symbol)
                classScope.insert(companionSymbol)
                let companionType = types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
                let companionScope = ClassMemberScope(
                    parent: classScope,
                    symbols: symbols,
                    ownerSymbol: companionSymbol,
                    thisType: companionType
                )
                collectSyntheticEnumCompanionMembers(
                    companionSymbol: companionSymbol,
                    companionFQName: companionFQName,
                    enumType: classType,
                    symbols: symbols,
                    types: types,
                    scope: companionScope,
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
                sourceFileID: file.fileID,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: interfaceDecl.memberFunctions,
                    properties: interfaceDecl.memberProperties,
                    nestedClasses: interfaceDecl.nestedClasses,
                    nestedObjects: interfaceDecl.nestedObjects
                ),
                owner: OwnerContext(fqName: fqName, symbol: symbol, type: interfaceType),
                sourceFileID: file.fileID,
                ctx: ctx,
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
                    ownerType: interfaceType,
                    sourceFileID: file.fileID,
                    ctx: ctx,
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
            // Unit keeps its builtin value representation, but its source-backed
            // object symbol must remain available for ordinary member dispatch.
            let builtinNames = BuiltinTypeNames(interner: interner)
            let isUnitObject = package == [interner.intern("kotlin")] && declaration.name == builtinNames.unit
            if isUnitObject {
                types.unitClassSymbol = symbol
            }
            // Unit's value representation is a builtin type, but its member
            // declarations are source-backed. Use the builtin type as the
            // member receiver so normal overload resolution accepts Unit
            // values without a name-based dispatch exception.
            let objectType = isUnitObject
                ? unitType
                : types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            let objectScope = ClassMemberScope(
                parent: scope,
                symbols: symbols,
                ownerSymbol: symbol,
                thisType: objectType
            )
            collectNestedTypeAliases(
                objectDecl.nestedTypeAliases,
                ownerFQName: fqName,
                sourceFileID: file.fileID,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: objectDecl.memberFunctions,
                    properties: objectDecl.memberProperties,
                    nestedClasses: objectDecl.nestedClasses,
                    nestedObjects: objectDecl.nestedObjects
                ),
                owner: OwnerContext(fqName: fqName, symbol: symbol, type: objectType),
                sourceFileID: file.fileID,
                ctx: ctx,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: objectScope,
                diagnostics: diagnostics,
                interner: interner
            )
            if objectDecl.modifiers.contains(.data) {
                collectSyntheticToString(
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    ownerType: objectType,
                    requireDataTypeFlag: false,
                    symbols: symbols,
                    types: types,
                    scope: objectScope,
                    interner: interner
                )
                collectSyntheticEquals(
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    ownerType: objectType,
                    requireDataTypeFlag: false,
                    symbols: symbols,
                    types: types,
                    scope: objectScope,
                    interner: interner
                )
            }

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
                relativeOwnerFQName: package,
                currentPackageFQName: package,
                imports: file.imports,
                diagnostics: diagnostics,
                usageRange: funDecl.range
            )
            let params = collectValueParameters(
                funDecl.valueParams,
                localNamespaceFQName: localNamespaceFQName,
                declSite: funDecl.range,
                ast: ast, symbols: symbols, types: types,
                interner: interner,
                localTypeParameters: typeParamResult.localTypeParameters,
                relativeOwnerFQName: package,
                currentPackageFQName: package,
                imports: file.imports,
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
                relativeOwnerFQName: package,
                currentPackageFQName: package,
                imports: file.imports,
                diagnostics: diagnostics,
                usageRange: funDecl.range
            ) {
                explicit
            } else {
                switch funDecl.body {
                case .unit, .block:
                    unitType
                case .expr:
                    anyType
                }
            }
            let upperBoundsByTypeParam: [[TypeID]] = typeParamResult.typeParameterSymbols.map {
                symbols.typeParameterUpperBounds(for: $0)
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: params.paramTypes,
                    returnType: returnType,
                    isSuspend: funDecl.isSuspend,
                    valueParameterSymbols: params.paramSymbols,
                    valueParameterHasDefaultValues: params.paramHasDefaultValues,
                    valueParameterIsVararg: params.paramIsVararg,
                    valueParameterAllowsNonLocalReturn: params.paramAllowsNonLocalReturn,
                    typeParameterSymbols: typeParamResult.typeParameterSymbols,
                    reifiedTypeParameterIndices: typeParamResult.reifiedIndices,
                    typeParameterUpperBoundsList: upperBoundsByTypeParam
                ),
                for: symbol
            )

            // KSP-INF-011: Attach public/internal top-level extension functions to their
            // receiver nominal type so member-call fallback resolution can find
            // source-backed stdlib replacements (e.g. List<T>.joinToString in
            // StringSplitJoin.kt) even when the declaring package differs from the
            // receiver owner package. Skip private extensions so they retain
            // file-private visibility rather than being gated by the receiver class.
            // Also skip functions whose synthetic runtime stub is intentionally retained
            // as a migration bridge (e.g. List.first), so call sites keep routing
            // through the kk_* ABI entry.
            if declaration.visibility != .private,
               let receiverType,
               let receiverSymbol = BundledDeclarationIndex.receiverOwnerSymbol(
                   for: receiverType,
                   types: types
               ),
               let semanticSymbol = symbols.symbol(symbol),
               let key = BundledDeclarationIndex.memberKey(
                   for: semanticSymbol,
                   symbolID: symbol,
                   symbols: symbols,
                   types: types,
                   interner: interner
               ),
               !BundledDeclarationIndex.isRuntimeBackedSyntheticRetainedOverlap(key, interner: interner) {
                symbols.setParentSymbol(receiverSymbol, for: symbol)

                // KSP-443: Runtime-linked bundled extension functions are registered
                // under their declaring package FQ, but synthetic-member-link tests
                // and surface-spec checks resolve by owner + member name. Create a
                // synthetic member alias under the receiver class FQ that reuses the
                // same signature and externalLinkName, so lookups like
                // kotlin.sequences.Sequence.toHashSet resolve to kk_sequence_toHashSet.
                if let externalLinkName = symbols.externalLinkName(for: symbol),
                   !externalLinkName.isEmpty,
                   let ownerSymbol = symbols.symbol(receiverSymbol),
                   let signature = symbols.functionSignature(for: symbol) {
                    let memberFQName = ownerSymbol.fqName + [semanticSymbol.name]
                    let alreadyExists = symbols.lookupAll(fqName: memberFQName).contains { existingID in
                        guard existingID != symbol,
                              let existingSig = symbols.functionSignature(for: existingID),
                              symbols.parentSymbol(for: existingID) == receiverSymbol
                        else {
                            return false
                        }
                        return existingSig == signature
                    }
                    if !alreadyExists {
                        var aliasFlags = semanticSymbol.flags
                        aliasFlags.insert(.synthetic)
                        let aliasSymbol = symbols.define(
                            kind: .function,
                            name: semanticSymbol.name,
                            fqName: memberFQName,
                            declSite: nil,
                            visibility: semanticSymbol.visibility,
                            flags: aliasFlags
                        )
                        symbols.setParentSymbol(receiverSymbol, for: aliasSymbol)
                        symbols.setFunctionSignature(signature, for: aliasSymbol)
                        symbols.setExternalLinkName(externalLinkName, for: aliasSymbol)
                    }
                }
            }

            checkAndReportJVMErasedCallableConflict(
                for: symbol,
                fqName: fqName,
                range: funDecl.range,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics
            )

        case let .propertyDecl(propertyDecl):
            let resolvedType = resolveTypeRef(
                propertyDecl.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                relativeOwnerFQName: package,
                currentPackageFQName: package,
                imports: file.imports,
                diagnostics: diagnostics,
                usageRange: propertyDecl.range
            ) ?? types.nullableAnyType
            symbols.setPropertyType(resolvedType, for: symbol)

            if let getter = propertyDecl.getter, getter.body != .unit {
                symbols.setPropertyHasCustomGetter(true, for: symbol)
            }

            if let receiverType = resolveTypeRef(
                propertyDecl.receiverType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                relativeOwnerFQName: package,
                currentPackageFQName: package,
                imports: file.imports,
                diagnostics: diagnostics,
                usageRange: propertyDecl.range
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

            // Materialize a backing field symbol for top-level properties with
            // custom accessors or explicit backing field declarations
            // (mirrors member property backing field logic).
            // Simple properties with only an initializer don't need a separate
            // backing field — the property symbol IS the storage.
            // Getter-only computed properties never need a backing field.
            let hasExplicitBackingField = propertyDecl.explicitBackingField != nil
            let isGetterOnlyComputed = propertyDecl.getter != nil
                && propertyDecl.setter == nil
                && propertyDecl.initializer == nil
                && !hasExplicitBackingField
            let needsBackingField = hasExplicitBackingField
                || (!isGetterOnlyComputed
                    && (propertyDecl.getter != nil || propertyDecl.setter != nil))
            if needsBackingField, propertyDecl.delegateExpression == nil, propertyDecl.receiverType == nil {
                let fieldName = interner.intern("$backing_\(interner.resolve(propertyDecl.name))")
                let fieldFQName = fqName.dropLast() + [fieldName]
                let backingFieldSymbol = symbols.define(
                    kind: .backingField,
                    name: fieldName,
                    fqName: Array(fieldFQName),
                    declSite: propertyDecl.range,
                    visibility: .private,
                    flags: propertyDecl.isVar ? [.mutable] : []
                )
                // When an explicit backing field declares its own type, use that
                // type for the backing field symbol instead of the property type.
                let backingFieldType: TypeID
                if let explicitField = propertyDecl.explicitBackingField,
                   let explicitType = explicitField.type
                {
                    backingFieldType = resolveTypeRef(
                        explicitType,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        localTypeParameters: [:],
                        relativeOwnerFQName: package,
                        currentPackageFQName: package,
                        imports: file.imports,
                        diagnostics: diagnostics,
                        usageRange: propertyDecl.range
                    ) ?? resolvedType
                } else {
                    backingFieldType = resolvedType
                }
                symbols.setPropertyType(backingFieldType, for: backingFieldSymbol)
                symbols.setBackingFieldSymbol(backingFieldSymbol, for: symbol)
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
                currentPackageFQName: package,
                imports: file.imports,
                diagnostics: diagnostics,
                usageRange: typeAliasDecl.range
            ) {
                symbols.setTypeAliasUnderlyingType(resolvedUnderlying, for: symbol)
            }

        case .enumEntryDecl:
            break
        }
    }

    /// Returns the predeclared synthetic nominal that a bundled source
    /// declaration takes over, if one exists. Early synthetic stub passes
    /// register nominal placeholders (e.g. `kotlin.Comparator`) so other stubs
    /// can reference the type before bundled header collection runs; the
    /// bundled declaration then claims that placeholder instead of defining a
    /// duplicate symbol. User sources never claim placeholders — a same-name
    /// collision there must still surface as KSWIFTK-SEMA-0001.
    func reusableSyntheticDeclarationSymbol(
        kind: SymbolKind,
        fqName: [InternedString],
        declarationFlags: SymbolFlags,
        file: ASTFile,
        sourceManager: SourceManager,
        symbols: SymbolTable
    ) -> SymbolID? {
        guard kind == .class || kind == .interface || kind == .object || kind == .enumClass else { return nil }
        guard sourceManager.path(of: file.fileID).hasPrefix("__bundled_") else { return nil }
        // expect/actual declarations keep the coexistence path that
        // checkAndReportDuplicateDeclaration already grants them over
        // synthetic-only collisions, instead of claiming the placeholder.
        guard !declarationFlags.contains(.expectDeclaration),
              !declarationFlags.contains(.actualDeclaration)
        else { return nil }
        return symbols.lookupAll(fqName: fqName).first { symbolID in
            guard let symbol = symbols.symbol(symbolID) else { return false }
            return symbol.kind == kind && symbol.flags.contains(.synthetic)
        }
    }

    private func shouldRestoreDeclSiteForReusableSyntheticSymbol(
        fqName: [InternedString],
        interner: StringInterner
    ) -> Bool {
        // Compatibility shells intentionally keep a nil declSite so bundled
        // source declarations do not displace them in golden semantic dumps.
        // KSP-683 needs the migrated Duration nominals to remain source-backed
        // for their value-class and enum metadata.
        let resolvedFQName = fqName.map(interner.resolve)
        return resolvedFQName == ["kotlin", "native", "ref", "WeakReference"]
            || resolvedFQName == ["kotlin", "ranges", "IntProgression"]
            || resolvedFQName == ["kotlin", "time", "Duration"]
            || resolvedFQName == ["kotlin", "time", "DurationUnit"]
            || resolvedFQName == ["kotlin", "text", "CharCategory"]
            || resolvedFQName == ["kotlin", "native", "concurrent", "TransferMode"]
    }

    /// The fully-qualified names a bundled source file is allowed to claim from
    /// an earlier synthetic registration. A file may declare more than one such
    /// nominal (`Exceptions.kt` declares the whole common exception hierarchy).
    private func reusableSyntheticSourceDeclarationKeys(
        for file: ASTFile,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [[InternedString]] {
        let names: [[String]] = switch sourceManager.path(of: file.fileID) {
        case "__bundled_kotlin/Lazy.kt":
            [["kotlin", "Lazy"]]
        case "__bundled_kotlin/Annotation.kt":
            [["kotlin", "Annotation"]]
        case "__bundled_kotlin/Comparable.kt":
            [["kotlin", "Comparable"]]
        case "__bundled_kotlin/CharSequence.kt":
            [["kotlin", "CharSequence"]]
        case "__bundled_kotlin/AutoCloseable.kt":
            [["kotlin", "AutoCloseable"]]
        case "__bundled_kotlin/Comparator.kt":
            [["kotlin", "Comparator"]]
        case "__bundled_kotlin/Enum.kt":
            [["kotlin", "Enum"]]
        case "__bundled_kotlin/io/Closeable.kt":
            [["kotlin", "io", "Closeable"]]
        case "__bundled_kotlin/collections/RandomAccess.kt":
            [["kotlin", "collections", "RandomAccess"]]
        case "__bundled_kotlin/collections/Iterable.kt":
            [["kotlin", "collections", "Iterable"]]
        case "__bundled_kotlin/collections/Collection.kt":
            [["kotlin", "collections", "Collection"]]
        case "__bundled_kotlin/collections/List.kt":
            [["kotlin", "collections", "List"]]
        case "__bundled_kotlin/collections/MutableIterable.kt":
            [["kotlin", "collections", "MutableIterable"]]
        case "__bundled_kotlin/collections/MutableCollection.kt":
            [["kotlin", "collections", "MutableCollection"]]
        case "__bundled_kotlin/collections/AbstractCollection.kt":
            [["kotlin", "collections", "AbstractCollection"]]
        case "__bundled_kotlin/collections/AbstractMutableCollection.kt":
            [["kotlin", "collections", "AbstractMutableCollection"]]
        case "__bundled_kotlin/collections/AbstractList.kt":
            [["kotlin", "collections", "AbstractList"]]
        case "__bundled_kotlin/Result/Stdlib.kt":
            [["kotlin", "Result"]]
        case "__bundled_kotlin/text/StringBuilder.kt":
            [["kotlin", "text", "StringBuilder"]]
        case "__bundled_kotlin/uuid/Uuid.kt":
            [["kotlin", "uuid", "Uuid"]]
        case "__bundled_java/math/BigDecimal.kt":
            [["java", "math", "BigDecimal"]]
        case "__bundled_kotlin/random/Random.kt":
            [["kotlin", "random", "Random"]]
        case "__bundled_kotlin/random/JavaUtilRandom.kt":
            [["java", "util", "Random"]]
        case "__bundled_kotlin/text/StringEncoding.kt":
            [["kotlin", "text", "Charset"]]
        case "__bundled_kotlin/Throwable.kt":
            [["kotlin", "Throwable"]]
        case "__bundled_kotlin/text/CharacterCodingException.kt":
            [["kotlin", "text", "CharacterCodingException"]]
        case "__bundled_kotlin/RuntimeException/Stdlib.kt":
            [["kotlin", "RuntimeException"]]
        case "__bundled_kotlin/NumberFormatException/Stdlib.kt":
            [["kotlin", "NumberFormatException"]]
        case "__bundled_kotlin/IndexOutOfBoundsException/Stdlib.kt":
            [["kotlin", "IndexOutOfBoundsException"]]
        case "__bundled_kotlin/NullPointerException/Stdlib.kt":
            [["kotlin", "NullPointerException"]]
        case "__bundled_kotlin/Exceptions.kt":
            [
                ["kotlin", "Error"],
                ["kotlin", "Exception"],
                ["kotlin", "IllegalArgumentException"],
                ["kotlin", "IllegalStateException"],
                ["kotlin", "ConcurrentModificationException"],
                ["kotlin", "UnsupportedOperationException"],
                ["kotlin", "ClassCastException"],
                ["kotlin", "AssertionError"],
                ["kotlin", "NoSuchElementException"],
                ["kotlin", "ArithmeticException"],
                ["kotlin", "NoWhenBranchMatchedException"],
                ["kotlin", "UninitializedPropertyAccessException"],
            ]
        case "__bundled_kotlin/properties/Interfaces.kt":
            [["kotlin", "properties", "ReadWriteProperty"]]
        case "__bundled_kotlin/time/TimeSource.kt":
            [
                ["kotlin", "time", "TimeSource"],
                ["kotlin", "time", "TimeSource", "WithComparableMarks"],
                ["kotlin", "time", "TimeSource", "Monotonic"],
            ]
        case "__bundled_kotlin/time/TimeSources.kt":
            [
                ["kotlin", "time", "AbstractLongTimeSource"],
                ["kotlin", "time", "AbstractDoubleTimeSource"],
                ["kotlin", "time", "TestTimeSource"],
            ]
        case "__bundled_kotlin/time/Duration.kt":
            [["kotlin", "time", "Duration"]]
        case "__bundled_kotlin/time/DurationUnit.kt":
            [["kotlin", "time", "DurationUnit"]]
        case "__bundled_kotlin/sequences/Sequence.kt":
            [["kotlin", "sequences", "Sequence"]]
        case "__bundled_kotlin/ranges/Ranges.kt":
            [
                ["kotlin", "ranges", "ClosedRange"],
                ["kotlin", "ranges", "ClosedFloatingPointRange"],
                ["kotlin", "ranges", "OpenEndRange"],
            ]
        default:
            []
        }
        return names.map { $0.map { interner.intern($0) } }
    }

    /// Registers type parameters for a nominal type (class or interface) as symbols,
    /// sets their variances and upper bounds, and returns the symbol list and local map.
    func registerNominalTypeParameters(
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
        // When a bundled source declaration reuses a synthetic shell
        // (`reusableSyntheticDeclarationSymbol`), the shell's type parameters are already
        // referenced by the residual synthetic members registered against it. Defining fresh
        // symbols here would leave those members typed against orphaned type parameters, so
        // adopt the shell's symbols and only re-apply variances and bounds to them.
        let existingTypeParamSymbols = types.nominalTypeParameterSymbols(for: ownerSymbol)
        let reusesShellTypeParameters = existingTypeParamSymbols.count == typeParams.count
            && zip(existingTypeParamSymbols, typeParams).allSatisfy { existing, declared in
                symbols.symbol(existing)?.name == declared.name
            }
        let typeParamNamespace = fqName + [interner.intern("\(namespacePrefix)\(ownerSymbol.rawValue)")]
        for (index, typeParam) in typeParams.enumerated() {
            let typeParamSymbol: SymbolID
            if reusesShellTypeParameters {
                typeParamSymbol = existingTypeParamSymbols[index]
            } else {
                let typeParamFQName = typeParamNamespace + [typeParam.name]
                typeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: typeParam.name,
                    fqName: typeParamFQName,
                    declSite: declSite,
                    visibility: .private,
                    flags: []
                )
            }
            typeParamSymbols.append(typeParamSymbol)
            localTypeParameters[typeParam.name] = typeParamSymbol
        }
        types.setNominalTypeParameterSymbols(
            typeParamSymbols,
            for: ownerSymbol
        )
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
                    diagnostics: diagnostics
                )
            }
            if !resolvedBounds.isEmpty {
                symbols.setTypeParameterUpperBounds(resolvedBounds, for: typeParamSym)
                symbols.recordTypeParameterForBoundConflictCheck(typeParamSym, declSite: declSite)
            }
        }

        return (symbols: typeParamSymbols, localMap: localTypeParameters)
    }
}
