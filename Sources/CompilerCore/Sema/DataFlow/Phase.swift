import Foundation

final class DataFlowSemaPhase: CompilerPhase {
    static let name = "DataFlowSema"

    init() {}

    func run(_ ctx: CompilationContext) throws {
        guard let ast = ctx.ast else {
            throw CompilerPipelineError.invalidInput("No AST available for semantic analysis.")
        }

        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let bindings = BindingTable()

        // Build the bundled declaration index from AST before synthetic registration,
        // but keep bundled SymbolTable header collection after synthetic type foundations.
        // Computed before SemaModule construction so it can be passed into the
        // initializer directly (see SemaModule.bundledIndex) rather than set
        // via a later mutation, matching the existing importedInlineFunctions
        // constructor-parameter convention.
        var bundledIndex = BundledDeclarationIndex.build(
            ast: ast,
            symbols: symbols,
            types: types,
            sourceManager: ctx.sourceManager,
            interner: ctx.interner
        )
        let sema = SemaModule(
            symbols: symbols, types: types,
            bindings: bindings, diagnostics: ctx.diagnostics,
            bundledIndex: bundledIndex
        )

        let fileScopes = buildFileScopes(ast: ast, symbols: symbols, interner: ctx.interner)
        let (importedInlineFunctions, importDeferredWork) = loadImports(ctx: ctx, symbols: symbols, types: types)
        sema.importedInlineFunctions = importedInlineFunctions

        // KSP-706: when compiling against bundled stdlib source rather than a
        // prebuilt library artifact, forward-declare `kotlin.Pair`/`kotlin.Triple`
        // from `Tuples.kt` now, before `registerSyntheticDelegateStubs` below runs
        // stub registrations that reference `Pair<...>` in their signatures. When
        // a prebuilt library is used instead, `loadImports` above already defined
        // the real symbols, so this pass simply finds nothing to do.
        var predeclaredEarlyHeaders: [DeclID: SymbolID] = [:]
        predeclareBundledTupleHeaders(
            ast: ast, fileScopes: fileScopes, symbols: symbols,
            sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
            interner: ctx.interner, into: &predeclaredEarlyHeaders
        )
        // KSP-711: `StringEncoding.kt` owns `Charset`/`Charsets`, but FileIO
        // extension bridges need the source symbol before synthetic
        // registration constructs their signatures.
        predeclareBundledStringEncodingHeaders(
            ast: ast, fileScopes: fileScopes, symbols: symbols,
            sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
            interner: ctx.interner, into: &predeclaredEarlyHeaders
        )
        // KSP-1522: bundled collection and interop headers refer to the
        // source-backed Random types while synthetic members are registered.
        // Forward-declare those real nominal headers before the synthetic pass
        // so this ordering does not require placeholder anchors.
        predeclareBundledRandomHeaders(
            ast: ast, fileScopes: fileScopes, symbols: symbols,
            sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
            interner: ctx.interner, into: &predeclaredEarlyHeaders
        )
        // KSP-1210: Platform.osFamily is typed against the source-backed
        // OsFamily enum before the native platform property stubs are built.
        predeclareBundledOsFamilyHeaders(
            ast: ast, fileScopes: fileScopes, symbols: symbols,
            sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
            interner: ctx.interner, into: &predeclaredEarlyHeaders
        )
        predeclareBundledMemoryUsageHeaders(
            ast: ast, fileScopes: fileScopes, symbols: symbols,
            sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
            interner: ctx.interner, into: &predeclaredEarlyHeaders
        )
        predeclareBundledAnnotationHeaders(
            ast: ast, fileScopes: fileScopes, symbols: symbols,
            sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
            interner: ctx.interner, into: &predeclaredEarlyHeaders
        )
        // KSP-1337: make the source-backed KVariance enum available before
        // reflection synthetic stubs construct signatures that reference it.
        predeclareBundledKVarianceHeaders(
            ast: ast, fileScopes: fileScopes, symbols: symbols,
            sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
            interner: ctx.interner, into: &predeclaredEarlyHeaders
        )
        // KSP-1334: make the source-backed KTypeProjection nominal available
        // before reflection synthetic stubs attach its residual properties.
        predeclareBundledKTypeProjectionHeaders(
            ast: ast, fileScopes: fileScopes, symbols: symbols,
            sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
            interner: ctx.interner, into: &predeclaredEarlyHeaders
        )
        // KSP-1150: make the source-backed CancellationException nominal
        // available before coroutine residual stubs are registered. This lets
        // the residual pass retain its no-stdlib fallback without recreating
        // the bundled class or its constructors.
        predeclareBundledCancellationExceptionHeaders(
            ast: ast, fileScopes: fileScopes, symbols: symbols,
            sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
            interner: ctx.interner, into: &predeclaredEarlyHeaders
        )

        if let stdlibLibraryPath = ctx.options.stdlibLibraryPath {
            bundledIndex = mergeImportedStdlibSymbolsIntoBundledIndex(
                bundledIndex: bundledIndex,
                stdlibLibraryPath: stdlibLibraryPath,
                symbols: symbols,
                types: types,
                interner: ctx.interner
            )
            // STDLIB-SHARED-002: SemaModule was created before imported symbols were
            // merged into the bundled index, so update it before any type-checker
            // queries rely on source-backed stdlib declarations.
            sema.bundledIndex = bundledIndex
        }

        initializeSourceBackedCloseableTypes(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )

        registerSyntheticDelegateStubs(
            symbols: symbols,
            types: types,
            interner: ctx.interner,
            bundledIndex: bundledIndex
        )

        // Synthetic nominal anchors (e.g. kotlin.Comparator) register methods after
        // library import. Apply imported class/interface layouts only after those
        // synthetic methods exist, so vtable/itable slots can resolve.
        applyImportedLibraryDeferredWork(
            importDeferredWork,
            symbols: symbols,
            types: types,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )
        normalizeImportedLibraryMemberSignatures(
            importDeferredWork,
            symbols: symbols,
            types: types,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )
        initializeSourceBackedCloseableTypes(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        // Keep overlap diagnostics as an explicit guard test helper. Emitting
        // them during normal Sema pollutes user diagnostics for unaffected code.
        // Enum header synthesis runs during bundled header collection rather
        // than synthetic stub registration, so expose the same bundled index
        // while headers are collected for source-backed enum API skip guards.
        let previousBundledIndex = BundledSyntheticStubRegistration.bundledIndex
        BundledSyntheticStubRegistration.bundledIndex = bundledIndex
        collectAllHeaders(
            ast: ast, fileScopes: fileScopes,
            symbols: symbols, types: types, bindings: bindings, ctx: ctx,
            predeclared: predeclaredEarlyHeaders
        )
        BundledSyntheticStubRegistration.bundledIndex = previousBundledIndex
        initializeSourceBackedCloseableTypes(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        types.functionInterfaceSymbol = symbols.lookupAll(
            fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern("Function")]
        ).first { symbols.symbol($0)?.kind == .interface }
        bundledIndex.warnSyntheticOverlaps(
            symbols: symbols,
            types: types,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )
        assignCompilationModuleFQNames(
            symbols: symbols,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner
        )
        // KSP-499 Stage 3: keep the bundled declaration index reachable via
        // `sema.bundledIndex` for the rest of the compilation (body
        // type-checking, KIR lowering) — the transient
        // `BundledSyntheticStubRegistration` thread-local used above is
        // already cleared by `registerSyntheticDelegateStubs`'s own `defer`
        // once header registration finished.
        sema.bundledIndex = bundledIndex
        runValidationPasses(ast: ast, symbols: symbols, bindings: bindings, types: types, ctx: ctx)
        patchSourceBackedCharIteratorReturnType(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        patchSourceBackedIndexedValueReturnType(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        patchSourceBackedPreconditionContractEffects(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        runBodyAnalysis(ast: ast, symbols: symbols, types: types, bindings: bindings, ctx: ctx)

        ctx.storeSema(sema)
    }

    func buildFileScopes(
        ast: ASTModule, symbols: SymbolTable, interner: StringInterner
    ) -> [Int32: FileScope] {
        let rootScope = PackageScope(parent: nil, symbols: symbols)
        var fileScopes: [Int32: FileScope] = [:]
        for file in ast.sortedFiles {
            let packageSymbol = definePackageSymbol(for: file, symbols: symbols, interner: interner)
            let packageScope = PackageScope(parent: rootScope, symbols: symbols)
            packageScope.insert(packageSymbol)
            fileScopes[file.fileID.rawValue] = FileScope(parent: packageScope, symbols: symbols)
        }
        return fileScopes
    }

    private func loadImports(
        ctx: CompilationContext, symbols: SymbolTable, types: TypeSystem
    ) -> ([SymbolID: KIRFunction], LibraryImportDeferredWork) {
        var importedInlineFunctions: [SymbolID: KIRFunction] = [:]
        let deferredWork = loadImportedLibrarySymbols(
            options: ctx.options, symbols: symbols, types: types,
            diagnostics: ctx.diagnostics, interner: ctx.interner,
            importedInlineFunctions: &importedInlineFunctions
        )
        return (importedInlineFunctions, deferredWork)
    }

    private func mergeImportedStdlibSymbolsIntoBundledIndex(
        bundledIndex: BundledDeclarationIndex,
        stdlibLibraryPath: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> BundledDeclarationIndex {
        let manifestPath = URL(fileURLWithPath: stdlibLibraryPath).appendingPathComponent("manifest.json").path
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let manifest = try? JSONDecoder().decode(LibraryManifest.self, from: data),
              let moduleName = manifest.moduleName, !moduleName.isEmpty
        else {
            return bundledIndex
        }
        let stdlibModuleName = interner.intern(moduleName)
        var importedStdlibKeys: Set<BundledMemberKey> = []
        for symbol in symbols.allSymbols() where symbol.flags.contains(.importedLibrary) {
            guard symbols.moduleFQN(for: symbol.id) == stdlibModuleName else { continue }
            guard let key = BundledDeclarationIndex.memberKey(
                for: symbol, symbolID: symbol.id, symbols: symbols, types: types, interner: interner
            ) else { continue }
            importedStdlibKeys.insert(key)

            // STDLIB-SHARED-012: Source-backed extension functions imported from a
            // stdlib artifact must be attached to their receiver nominal type so
            // collection/sequence member-call fallback resolution (which keys off
            // parentSymbol == owner) can find them. Skip retained runtime-bridge
            // overlaps so synthetic ABI stubs keep routing through kk_* entries.
            guard symbol.kind == .function,
                  !BundledDeclarationIndex.isRuntimeBackedSyntheticRetainedOverlap(key, interner: interner),
                  let signature = symbols.functionSignature(for: symbol.id),
                  let receiverType = signature.receiverType,
                  let receiverSymbol = BundledDeclarationIndex.receiverOwnerSymbol(
                      for: receiverType,
                      types: types
                  )
            else { continue }
            symbols.setParentSymbol(receiverSymbol, for: symbol.id)
        }
        var updatedIndex = bundledIndex
        updatedIndex.insertImportedStdlibSymbols(keys: importedStdlibKeys, interner: interner)
        return updatedIndex
    }

    func collectAllHeaders(
        ast: ASTModule, fileScopes: [Int32: FileScope],
        symbols: SymbolTable, types: TypeSystem, bindings: BindingTable,
        ctx: CompilationContext,
        predeclared initialPredeclared: [DeclID: SymbolID] = [:]
    ) {
        // Collect bundled/residual stdlib headers before user headers so that
        // source-backed stdlib declarations (e.g. `kotlin.experimental`
        // annotation classes) are registered before user signatures that
        // reference them are resolved inline during header collection. This
        // keeps resolution independent of the order in which the SourceManager
        // assigned file IDs (the driver injects bundled sources first, but test
        // harnesses may add user sources first).
        let orderedFiles = ast.sortedFiles.sorted { lhs, rhs in
            let lhsBundled = ctx.sourceManager.origin(of: lhs.fileID)?.isBundledStdlib == true
            let rhsBundled = ctx.sourceManager.origin(of: rhs.fileID)?.isBundledStdlib == true
            if lhsBundled != rhsBundled {
                return lhsBundled
            }
            return lhs.fileID.rawValue < rhs.fileID.rawValue
        }
        // BUG-143: forward-declare every top-level nominal type first, so a
        // signature may reference a class/interface/object declared later in the
        // same file (or in a file collected later). Seeded with whatever
        // the early bundled nominal pass in `Phase.run` already predeclared;
        // `predeclareNominalTypeHeaders` skips declarations already present.
        var predeclared = initialPredeclared
        for file in orderedFiles {
            guard let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
                interner: ctx.interner, into: &predeclared
            )
        }
        // Resolve kotlin.Number as early as possible. Number is a builtin type
        // name (BuiltinTypeNames.number), so signatures that mention `Number`
        // need types.numberClassSymbol set before they are resolved.
        resolveNumberClassSymbol(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        resolveUnitClassSymbol(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )

        // Type aliases are collected before the remaining headers so that their
        // underlying type is available to signatures that mention the alias.
        for collectsTypeAliases in [true, false] {
            for file in orderedFiles {
                guard let fileScope = fileScopes[file.fileID.rawValue] else { continue }
                if collectsTypeAliases {
                    registerFileAnnotations(
                        file: file,
                        symbols: symbols,
                        diagnostics: ctx.diagnostics,
                        interner: ctx.interner
                    )
                }
                for declID in file.topLevelDecls {
                    let isTypeAlias: Bool
                    if case .typeAliasDecl = ast.arena.decl(declID) {
                        isTypeAlias = true
                    } else {
                        isTypeAlias = false
                    }
                    guard isTypeAlias == collectsTypeAliases else { continue }
                    collectHeader(
                        declID: declID, file: file, ast: ast,
                        symbols: symbols, types: types, bindings: bindings,
                        scope: fileScope, sourceManager: ctx.sourceManager,
                        diagnostics: ctx.diagnostics, interner: ctx.interner,
                        ctx: ctx, predeclaredSymbol: predeclared[declID]
                    )
                }
            }
        }
    }

    private func runValidationPasses(
        ast: ASTModule, symbols: SymbolTable, bindings: BindingTable,
        types: TypeSystem, ctx: CompilationContext
    ) {
        bindInheritanceEdges(ast: ast, symbols: symbols, bindings: bindings, types: types, interner: ctx.interner)
        // KSP-719: Restore kotlin.Any as the direct supertype of the bundled
        // kotlin.Annotation source, because its source declaration has no
        // explicit supertype clause and would otherwise erase the synthetic
        // supertype installed by registerSyntheticAnyStub.
        patchBundledAnnotationSupertype(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        // BUG-166: StringBuilder's Appendable/CharSequence conformance is
        // synthetic (not written in the bundled Kotlin source's `class
        // StringBuilder { ... }` declaration), so bindInheritanceEdges above —
        // which recomputes every nominal's directSupertypes from its AST
        // super-type clause and defaults to just `Any` when that clause is
        // empty — unconditionally overwrites whatever this patch had set
        // if it ran any earlier (e.g. before this function, as a prior
        // version of this fix did). That left `val x: Appendable =
        // StringBuilder()` unable to satisfy the assignment's subtype
        // constraint (KSWIFTK-TYPE-0001) despite Appendable's own itable
        // layout being otherwise correct. Patching here, immediately after
        // bindInheritanceEdges and before every other validation pass and
        // synthesizeNominalLayouts below, ensures both the constraint solver
        // and itable slot synthesis see the complete supertype list.
        patchSourceBackedStringBuilderSupertypes(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        // KSP-944: MutableList's source declaration owns its official
        // List/MutableCollection edges, while the retained compiler shell
        // still supplies the MutableIterable residual compatibility edge.
        patchSourceBackedMutableListSupertypes(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        validateTypeParameterUpperBounds(
            symbols: symbols, types: types, interner: ctx.interner, diagnostics: ctx.diagnostics
        )
        validateSealedHierarchy(
            ast: ast, symbols: symbols, bindings: bindings,
            diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        validateClassDelegation(
            ast: ast, symbols: symbols, bindings: bindings, types: types,
            diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        validateAbstractOverrides(
            ast: ast, symbols: symbols, bindings: bindings, types: types,
            diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        validateAbstractClassConstraints(
            ast: ast, symbols: symbols, bindings: bindings, types: types,
            diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        validateDiamondOverrides(
            ast: ast, symbols: symbols, bindings: bindings,
            diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        validateOpenFinalOverride(
            ast: ast, symbols: symbols, bindings: bindings, types: types,
            diagnostics: ctx.diagnostics, interner: ctx.interner,
            compilationModuleName: ctx.options.moduleName
        )
        validateExpectActualMatching(
            ast: ast,
            symbols: symbols,
            types: types,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )
        validateAnnotationTargets(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )
        validateExperimentalTypeInferenceOptIn(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            diagnostics: ctx.diagnostics
        )
        validateExperimentalVersionOverloadingOptIn(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner,
            options: ctx.options
        )
        validateConstructorDelegation(ast: ast, symbols: symbols, diagnostics: ctx.diagnostics)
        validateDeclarationSiteVariance(
            ast: ast, symbols: symbols, bindings: bindings,
            types: types, diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        synthesizeClassDelegationForwardingMethodSymbols(
            ast: ast, symbols: symbols, bindings: bindings,
            types: types, interner: ctx.interner
        )
        synthesizeNominalLayouts(symbols: symbols, types: types, interner: ctx.interner)
        attachCompilerMetadataAnnotations(
            symbols: symbols,
            types: types,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner
        )
    }

    private func runBodyAnalysis(
        ast: ASTModule, symbols: SymbolTable, types: TypeSystem,
        bindings: BindingTable, ctx: CompilationContext
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                analyzeBody(
                    declID: declID, ast: ast, symbols: symbols, types: types,
                    bindings: bindings, diagnostics: ctx.diagnostics, interner: ctx.interner
                )
            }
        }
    }
}
