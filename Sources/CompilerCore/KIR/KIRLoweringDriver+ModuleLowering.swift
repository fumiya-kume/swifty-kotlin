import Foundation

extension KIRLoweringDriver {
    func lowerModule(
        ast: ASTModule,
        sema: SemaModule,
        compilationCtx: CompilationContext
    ) -> KIRModule {
        ctx.resetModuleState()
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: sema)

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
        ctx.functionDefaultArgumentsBySymbol = callSupportLowerer.collectFunctionDefaultArgumentExpressions(
            ast: ast,
            sema: sema
        )

        // Collect all top-level property init instructions (regular + delegate) in declaration order.
        // Using a single array ensures Kotlin's strict declaration-order initialization guarantee.
        var allTopLevelInitInstructions: KIRLoweringEmitContext = []

        // Maps delegated property symbol → delegate storage symbol (e.g. `$delegate_`).
        // We store the delegate handle into this storage symbol in main, and load it
        // at use-sites when rewriting getValue calls.
        var delegateStorageSymbolByPropertySymbol: [SymbolID: SymbolID] = [:]

        for file in ast.sortedFiles {
            let declIDs = lowerTopLevelDecls(
                file: file,
                shared: shared,
                compilationCtx: compilationCtx,
                allTopLevelInitInstructions: &allTopLevelInitInstructions,
                delegateStorageSymbolByPropertySymbol: &delegateStorageSymbolByPropertySymbol
            )
            files.append(KIRFile(fileID: file.fileID, decls: declIDs))
        }

        appendCompanionInitializerCalls(
            arena: arena, sema: sema,
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
        return KIRModule(files: files, arena: arena)
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
                    interfaceDecl, symbol: symbol, shared: shared
                ))

            case let .objectDecl(objectDecl):
                declIDs.append(contentsOf: lowerTopLevelObjectDecl(
                    objectDecl, symbol: symbol, shared: shared
                ))

            case let .funDecl(function):
                declIDs.append(contentsOf: lowerTopLevelFunDecl(
                    function, symbol: symbol, shared: shared
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
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let arena = shared.arena
        var ifaceNestedObjects = interfaceDecl.nestedObjects
        if let companionDeclID = interfaceDecl.companionObject {
            ifaceNestedObjects.append(companionDeclID)
        }
        let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
            memberFunctions: interfaceDecl.memberFunctions,
            memberProperties: [],
            nestedClasses: interfaceDecl.nestedClasses,
            nestedObjects: ifaceNestedObjects,
            shared: shared
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
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let arena = shared.arena
        let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: objectDecl.memberProperties,
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            shared: shared
        )
        let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
        var declIDs = [kirID]
        declIDs.append(contentsOf: allDecls)
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

    private func appendCompanionInitializerCalls(
        arena: KIRArena,
        sema: SemaModule,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext
    ) {
        guard !ctx.companionInitializerFunctions.isEmpty else { return }
        for initializer in ctx.companionInitializerFunctions {
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.unitType
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
