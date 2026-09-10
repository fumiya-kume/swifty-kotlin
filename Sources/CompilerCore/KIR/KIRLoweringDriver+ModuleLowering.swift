
extension KIRLoweringDriver {
    func lowerModule(
        ast: ASTModule,
        sema: SemaModule,
        compilationCtx: CompilationContext
    ) -> KIRModule {
        ctx.resetModuleState()
        ctx.lazyThreadSafetyMode = compilationCtx.options.lazyThreadSafetyMode
        ctx.initializeSyntheticLambdaSymbolAllocator(
            sema: sema,
            stdlibOnly: compilationCtx.options.stdlibOnly
        )

        let arena = KIRArena()
        var files: [KIRFile] = []
        let sourceByFileID = buildSourceByFileID(ast: ast, compilationCtx: compilationCtx)
        let propertyConstantInitializers = constantCollector.collectPropertyConstantInitializers(
            ast: ast,
            sema: sema,
            interner: compilationCtx.interner,
            sourceByFileID: sourceByFileID
        )
        let shared = KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: arena,
            interner: compilationCtx.interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
        ctx.setFunctionDefaultArguments(callSupportLowerer.collectFunctionDefaultArgumentExpressions(
            ast: ast,
            sema: sema
        ))

        // Collect all top-level property init instructions (regular + delegate) in declaration order.
        // Using a single array ensures Kotlin's strict declaration-order initialization guarantee.
        var allTopLevelInitInstructions: KIRLoweringEmitContext = []

        // Maps delegated property symbol → delegate storage symbol (e.g. `$delegate_`).
        // We store the delegate handle into this storage symbol in main, and load it
        // at use-sites when rewriting getValue calls.
        var delegateStorageSymbolByPropertySymbol: [SymbolID: SymbolID] = [:]

        for file in ast.sortedFiles {
            if shouldSkipBundledFileForOutput(file, compilationCtx: compilationCtx) {
                continue
            }
            let declIDs = lowerTopLevelDecls(
                file: file,
                shared: shared,
                compilationCtx: compilationCtx,
                allTopLevelInitInstructions: &allTopLevelInitInstructions,
                delegateStorageSymbolByPropertySymbol: &delegateStorageSymbolByPropertySymbol
            )
            files.append(KIRFile(fileID: file.fileID, decls: declIDs))
        }

        emitSyntheticTopLevelExternalPropertyInitializers(
            arena: arena,
            sema: sema,
            interner: compilationCtx.interner,
            allTopLevelInitInstructions: &allTopLevelInitInstructions
        )

        appendCompanionInitializerCalls(
            arena: arena, sema: sema,
            allTopLevelInitInstructions: &allTopLevelInitInstructions
        )

        appendImportedLibraryInitializerCalls(
            arena: arena,
            sema: sema,
            interner: compilationCtx.interner,
            allTopLevelInitInstructions: &allTopLevelInitInstructions
        )

        postProcessTopLevelInitializersAndDelegates(
            ast: ast,
            sema: sema,
            compilationCtx: compilationCtx,
            arena: arena,
            allTopLevelInitInstructions: allTopLevelInitInstructions,
            delegateStorageSymbolByPropertySymbol: delegateStorageSymbolByPropertySymbol
        )
        let module = KIRModule(files: files, arena: arena)
        module.arena.callableValueInfoByExprID = ctx.callableValueInfoByExprID
        return module
    }

    private func shouldSkipBundledFileForOutput(
        _ file: ASTFile,
        compilationCtx: CompilationContext
    ) -> Bool {
        guard compilationCtx.sourceManager.origin(of: file.fileID)?.isBundledStdlib == true else {
            return false
        }

        // When emitting a dedicated stdlib .kklib, the bundled/residual source
        // bodies must be lowered into objects and inline-KIR artifacts.
        if compilationCtx.options.stdlibOnly {
            return false
        }

        switch compilationCtx.options.emit {
        case .kirDump, .library:
            return true
        case .executable, .object, .llvmIR:
            return false
        }
    }

    private func buildSourceByFileID(
        ast: ASTModule, compilationCtx: CompilationContext
    ) -> [Int32: String] {
        var result: [Int32: String] = [:]
        for file in ast.files {
            let contents = compilationCtx.sourceManager.contents(of: file.fileID)
            result[file.fileID.rawValue] = String(data: contents, encoding: .utf8) ?? ""
        }
        return result
    }

    // MARK: - Per-file top-level declaration lowering

    private func lowerTopLevelDecls(
        file: ASTFile,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext,
        delegateStorageSymbolByPropertySymbol: inout [SymbolID: SymbolID]
    ) -> [KIRDeclID] {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena

        var declIDs: [KIRDeclID] = []
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID),
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }

            switch decl {
            case let .classDecl(classDecl):
                declIDs.append(contentsOf: lowerTopLevelClassDecl(
                    classDecl,
                    symbol: symbol,
                    shared: shared,
                    compilationCtx: compilationCtx
                ))

            case let .interfaceDecl(interfaceDecl):
                declIDs.append(contentsOf: lowerTopLevelInterfaceDecl(
                    interfaceDecl, symbol: symbol, shared: shared,
                    compilationCtx: compilationCtx
                ))

            case let .objectDecl(objectDecl):
                declIDs.append(contentsOf: lowerTopLevelObjectDecl(
                    objectDecl, symbol: symbol, shared: shared,
                    compilationCtx: compilationCtx
                ))

            case let .funDecl(function):
                declIDs.append(contentsOf: lowerTopLevelFunDecl(
                    function,
                    symbol: symbol,
                    shared: shared,
                    compilationCtx: compilationCtx
                ))

            case let .propertyDecl(propertyDecl):
                declIDs.append(contentsOf: lowerTopLevelPropertyDecl(
                    propertyDecl, symbol: symbol,
                    shared: shared, compilationCtx: compilationCtx,
                    allTopLevelInitInstructions: &allTopLevelInitInstructions,
                    delegateStorageSymbolByPropertySymbol: &delegateStorageSymbolByPropertySymbol
                ))

            case .typeAliasDecl:
                let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                declIDs.append(kirID)

            case .enumEntryDecl:
                let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: sema.types.anyType)))
                declIDs.append(kirID)
            }
        }
        return declIDs
    }

    // MARK: - Interface declaration

    private func lowerTopLevelInterfaceDecl(
        _ interfaceDecl: InterfaceDecl,
        symbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> [KIRDeclID] {
        let arena = shared.arena
        var ifaceNestedObjects = interfaceDecl.nestedObjects
        if let companionDeclID = interfaceDecl.companionObject {
            ifaceNestedObjects.append(companionDeclID)
        }
        let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
            memberFunctions: interfaceDecl.memberFunctions,
            memberProperties: interfaceDecl.memberProperties,
            nestedClasses: interfaceDecl.nestedClasses,
            nestedObjects: ifaceNestedObjects,
            shared: shared,
            compilationCtx: compilationCtx,
            isInterfaceContext: true
        )
        let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
        var declIDs = [kirID]
        declIDs.append(contentsOf: allDecls)
        declIDs.append(contentsOf: synthesizeCompanionInitializerIfNeeded(
            companionDeclID: interfaceDecl.companionObject,
            ownerSymbol: symbol,
            shared: shared
        ))
        return declIDs
    }

    // MARK: - Object declaration

    private func lowerTopLevelObjectDecl(
        _ objectDecl: ObjectDecl,
        symbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: objectDecl.memberProperties,
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            shared: shared,
            compilationCtx: compilationCtx
        )
        let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
        var declIDs = [kirID]
        declIDs.append(contentsOf: allDecls)

        // Every source-backed top-level object needs a global slot for its
        // singleton heap pointer. Without it, an object crossing an Any
        // boundary is lowered as an unresolved symbol reference and reaches
        // the runtime as the raw zero value instead of a registered handle.
        let objectType = sema.types.make(.classType(ClassType(
            classSymbol: symbol, args: [], nullability: .nonNull
        )))
        let globalID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: objectType)))
        declIDs.append(globalID)

        // Synthesise an initializer for the top-level object so that
        // property initializers and init blocks run during module init
        // (property initializers first, then init blocks).
        declIDs.append(contentsOf: synthesizeObjectInitializer(
            objectDecl,
            objectSymbol: symbol,
            shared: shared
        ))
        return declIDs
    }

    // MARK: - Companion initializer calls

    private func emitSyntheticTopLevelExternalPropertyInitializers(
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext
    ) {
        var existingGlobals: Set<SymbolID> = []
        for declaration in arena.declarations {
            guard case let .global(global) = declaration else { continue }
            existingGlobals.insert(global.symbol)
        }

        for symbolInfo in sema.symbols.allSymbols()
        where symbolInfo.kind == .property || symbolInfo.kind == .field || symbolInfo.kind == .backingField
        {
            let symbol = symbolInfo.id
            guard !existingGlobals.contains(symbol),
                  sema.symbols.backingFieldSymbol(for: symbol) == nil,
                  sema.symbols.extensionPropertyReceiverType(for: symbol) == nil,
                  let propertyType = sema.symbols.propertyType(for: symbol),
                  let externalLinkName = sema.symbols.externalLinkName(for: symbol),
                  !externalLinkName.isEmpty
            else {
                continue
            }

            let parentKind = sema.symbols.parentSymbol(for: symbol).flatMap {
                sema.symbols.symbol($0)?.kind
            }
            if parentKind != nil && parentKind != .package && parentKind != .object {
                continue
            }

            _ = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: propertyType)))
            existingGlobals.insert(symbol)

            let result = arena.appendTemporary(type: propertyType
            )
            let storage = arena.appendExpr(
                .symbolRef(symbol),
                type: propertyType
            )

            allTopLevelInitInstructions.append(
                .call(
                    symbol: nil,
                    callee: interner.intern(externalLinkName),
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            allTopLevelInitInstructions.append(
                .copy(from: result, to: storage)
            )
        }
    }

    private func appendImportedLibraryInitializerCalls(
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext
    ) {
        func appendInitializer(_ initializerSymbol: SymbolID?) {
            guard let initializerSymbol else { return }
            guard let externalLinkName = sema.symbols.externalLinkName(for: initializerSymbol),
                  !externalLinkName.isEmpty
            else {
                return
            }
            let result = arena.appendTemporary(type: sema.types.unitType)
            allTopLevelInitInstructions.append(
                .call(
                    symbol: initializerSymbol,
                    callee: interner.intern(externalLinkName),
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        for symbol in sema.symbols.allSymbols() where symbol.flags.contains(.importedLibrary) {
            switch symbol.kind {
            case .object:
                appendInitializer(sema.symbols.objectInitializerSymbol(for: symbol.id))
            case .class, .interface, .annotationClass:
                appendInitializer(sema.symbols.companionObjectInitializerSymbol(for: symbol.id))
            case .enumClass:
                appendInitializer(sema.symbols.companionObjectInitializerSymbol(for: symbol.id))
                appendInitializer(sema.symbols.enumStaticInitSymbol(for: symbol.id))
            default:
                break
            }
        }
    }

    private func appendCompanionInitializerCalls(
        arena: KIRArena,
        sema: SemaModule,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext
    ) {
        let companionInitializers = ctx.allCompanionInitializers()
        guard !companionInitializers.isEmpty else { return }
        for initializer in companionInitializers {
            let result = arena.appendTemporary(type: sema.types.unitType
            )
            allTopLevelInitInstructions.append(
                .call(
                    symbol: initializer.symbol,
                    callee: initializer.name,
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }
    }
}
