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
        var sourceByFileID: [Int32: String] = [:]
        for file in ast.files {
            let contents = compilationCtx.sourceManager.contents(of: file.fileID)
            sourceByFileID[file.fileID.rawValue] = String(data: contents, encoding: .utf8) ?? ""
        }
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
                    // Interface properties have no backing storage; pass empty list.
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
                    declIDs.append(kirID)
                    declIDs.append(contentsOf: allDecls)
                    declIDs.append(contentsOf: synthesizeCompanionInitializerIfNeeded(
                        companionDeclID: interfaceDecl.companionObject,
                        ownerSymbol: symbol,
                        shared: shared
                    ))

                case let .objectDecl(objectDecl):
                    let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
                        memberFunctions: objectDecl.memberFunctions,
                        memberProperties: objectDecl.memberProperties,
                        nestedClasses: objectDecl.nestedClasses,
                        nestedObjects: objectDecl.nestedObjects,
                        shared: shared
                    )
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
                    declIDs.append(kirID)
                    declIDs.append(contentsOf: allDecls)

                case let .funDecl(function):
                    ctx.resetScopeForFunction()
                    ctx.beginCallableLoweringScope()
                    let signature = sema.symbols.functionSignature(for: symbol)
                    var params: [KIRParameter] = []
                    if let signature {
                        if let receiverType = signature.receiverType {
                            let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: symbol)
                            params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                            ctx.currentImplicitReceiverSymbol = receiverSymbol
                            ctx.currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
                        }
                        params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                            KIRParameter(symbol: pair.0, type: pair.1)
                        })
                    }
                    if function.isInline, let signature,
                       !signature.reifiedTypeParameterIndices.isEmpty
                    {
                        let intType = sema.types.make(.primitive(.int, .nonNull))
                        for index in signature.reifiedTypeParameterIndices.sorted() {
                            guard index < signature.typeParameterSymbols.count else { continue }
                            let typeParamSymbol = signature.typeParameterSymbols[index]
                            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
                            params.append(KIRParameter(symbol: tokenSymbol, type: intType))
                        }
                    }
                    let returnType = signature?.returnType ?? sema.types.unitType
                    var body: KIRLoweringEmitContext = [.beginBlock]
                    if let receiverExpr = ctx.currentImplicitReceiverExprID,
                       let receiverSymbol = ctx.currentImplicitReceiverSymbol
                    {
                        body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))
                    }
                    switch function.body {
                    case let .block(exprIDs, _):
                        var lastValue: KIRExprID?
                        var terminatedByReturn = false
                        for exprID in exprIDs {
                            if let expr = ast.arena.expr(exprID),
                               case let .returnExpr(value, _, _) = expr
                            {
                                if let value {
                                    let lowered = lowerExpr(
                                        value,
                                        shared: shared, emit: &body
                                    )
                                    body.append(.returnValue(lowered))
                                } else {
                                    body.append(.returnUnit)
                                }
                                terminatedByReturn = true
                                break
                            }
                            if let expr = ast.arena.expr(exprID),
                               case .throwExpr = expr
                            {
                                _ = lowerExpr(
                                    exprID,
                                    shared: shared, emit: &body
                                )
                                terminatedByReturn = true
                                break
                            }
                            lastValue = lowerExpr(
                                exprID,
                                shared: shared, emit: &body
                            )
                            // Detect nested termination (e.g., if/when/try with return in all branches)
                            if let lastValue, controlFlowLowerer.isTerminatedExpr(lastValue, arena: arena, sema: sema) {
                                terminatedByReturn = true
                                break
                            }
                        }
                        if !terminatedByReturn {
                            if let lastValue {
                                body.append(.returnValue(lastValue))
                            } else {
                                body.append(.returnUnit)
                            }
                        }
                    case let .expr(exprID, _):
                        let value = lowerExpr(
                            exprID,
                            shared: shared, emit: &body
                        )
                        body.append(.returnValue(value))
                    case .unit:
                        body.append(.returnUnit)
                    }
                    body.append(.endBlock)
                    let kirID = arena.appendDecl(
                        .function(
                            KIRFunction(
                                symbol: symbol,
                                name: function.name,
                                params: params,
                                returnType: returnType,
                                body: body,
                                isSuspend: function.isSuspend,
                                isInline: function.isInline,
                                sourceRange: function.range
                            )
                        )
                    )
                    declIDs.append(kirID)
                    if let defaults = ctx.functionDefaultArgumentsBySymbol[symbol],
                       let sig = signature
                    {
                        let stubID = callSupportLowerer.generateDefaultStubFunction(
                            originalSymbol: symbol,
                            originalName: function.name,
                            signature: sig,
                            defaultExpressions: defaults,
                            shared: shared
                        )
                        declIDs.append(stubID)
                    }
                    declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
                    ctx.currentImplicitReceiverExprID = nil
                    ctx.currentImplicitReceiverSymbol = nil

                case let .propertyDecl(propertyDecl):
                    let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let isExtensionProperty = propertyDecl.receiverType != nil
                    if !isExtensionProperty {
                        let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: propType)))
                        declIDs.append(kirID)
                    }

                    // Emit backing field global for properties with custom accessors.
                    if !isExtensionProperty,
                       let backingFieldSymbol = sema.symbols.backingFieldSymbol(for: symbol)
                    {
                        let backingFieldType = sema.symbols.propertyType(for: backingFieldSymbol) ?? propType
                        let backingFieldKirID = arena.appendDecl(
                            .global(KIRGlobal(symbol: backingFieldSymbol, type: backingFieldType))
                        )
                        declIDs.append(backingFieldKirID)
                    }

                    // Lower getter body as a KIR accessor function (top-level property).
                    if let getter = propertyDecl.getter, getter.body != .unit {
                        memberLowerer.lowerAccessorBody(
                            accessorBody: getter.body,
                            propertySymbol: symbol,
                            propertyType: propType,
                            accessorKind: .getter,
                            setterParamName: nil,
                            shared: shared,
                            allDecls: &declIDs
                        )
                    }

                    // Lower setter body as a KIR accessor function (top-level property).
                    if let setter = propertyDecl.setter, setter.body != .unit {
                        memberLowerer.lowerAccessorBody(
                            accessorBody: setter.body,
                            propertySymbol: symbol,
                            propertyType: propType,
                            accessorKind: .setter,
                            setterParamName: setter.parameterName,
                            shared: shared,
                            allDecls: &declIDs
                        )
                    }

                    // Collect top-level property initialization instructions
                    // (declaration order is preserved since we iterate topLevelDecls in order).
                    if let initializer = propertyDecl.initializer,
                       propertyDecl.delegateExpression == nil,
                       !isExtensionProperty
                    {
                        // Emit runtime init when the property is NOT a compile-time
                        // constant, OR when it is mutable (var).  Mutable properties
                        // are never constant-folded at use-sites (ExprLowerer skips
                        // inlining for .mutable), so their globals must be initialised
                        // to the declared value at program start.
                        if propertyConstantInitializers[symbol] == nil
                            || (sema.symbols.symbol(symbol)?.flags.contains(.mutable) == true)
                        {
                            ctx.resetScopeForFunction()
                            ctx.beginCallableLoweringScope()
                            var initInstructions: KIRLoweringEmitContext = []
                            let initValue = lowerExpr(
                                initializer,
                                shared: shared, emit: &initInstructions
                            )
                            let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
                            initInstructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
                            initInstructions.append(.copy(from: initValue, to: globalRef))
                            allTopLevelInitInstructions.append(contentsOf: initInstructions)
                            declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
                        }
                    }

                    // Create delegate initialization.
                    if propertyDecl.delegateExpression != nil,
                       !isExtensionProperty
                    {
                        let interner = compilationCtx.interner
                        let delegateType = sema.types.anyType

                        let delegateStorageSymbol: SymbolID
                        if let existingStorage = sema.symbols.delegateStorageSymbol(for: symbol) {
                            delegateStorageSymbol = existingStorage
                        } else {
                            let delegateStorageName = interner.intern("$delegate_\(interner.resolve(propertyDecl.name))")
                            let delegateStorageFQName = (sema.symbols.symbol(symbol)?.fqName.dropLast() ?? []) + [delegateStorageName]
                            delegateStorageSymbol = sema.symbols.define(
                                kind: .field,
                                name: delegateStorageName,
                                fqName: Array(delegateStorageFQName),
                                declSite: propertyDecl.range,
                                visibility: .private,
                                flags: []
                            )
                            sema.symbols.setDelegateStorageSymbol(delegateStorageSymbol, for: symbol)
                        }

                        // Declare delegate storage global.
                        let delegateKirID = arena.appendDecl(
                            .global(KIRGlobal(symbol: delegateStorageSymbol, type: delegateType))
                        )
                        declIDs.append(delegateKirID)

                        delegateStorageSymbolByPropertySymbol[symbol] = delegateStorageSymbol

                        // Determine delegate kind first so we can choose the right accessor strategy.
                        let delegateKind = detectDelegateKind(
                            delegateExpr: propertyDecl.delegateExpression,
                            ast: ast,
                            interner: interner
                        )

                        // Synthesize getValue/setValue accessor functions only for custom
                        // delegates. Built-in delegates (lazy, observable, vetoable) use
                        // their own runtime helpers (kk_lazy_get_value, etc.) and do NOT
                        // need the generic KProperty accessor, which references the
                        // unimplemented kk_kproperty_stub_create symbol.
                        if case .custom = delegateKind {
                            memberLowerer.lowerDelegateAccessor(
                                propertySymbol: symbol,
                                propertyType: propType,
                                delegateStorageSymbol: delegateStorageSymbol,
                                accessorKind: .getter,
                                shared: shared,
                                allDecls: &declIDs
                            )
                            if propertyDecl.isVar {
                                memberLowerer.lowerDelegateAccessor(
                                    propertySymbol: symbol,
                                    propertyType: propType,
                                    delegateStorageSymbol: delegateStorageSymbol,
                                    accessorKind: .setter,
                                    shared: shared,
                                    allDecls: &declIDs
                                )
                            }
                        }

                        ctx.resetScopeForFunction()
                        ctx.beginCallableLoweringScope()
                        var initInstructions: KIRLoweringEmitContext = []

                        switch delegateKind {
                        case .lazy:
                            // Create lambda function from delegate body.
                            let lambdaFnPtr = lowerDelegateLambdaBody(
                                delegateBody: propertyDecl.delegateBody,
                                propertySymbol: symbol,
                                paramCount: 0,
                                shared: shared,
                                emit: &initInstructions
                            )
                            // Emit thread safety mode constant.
                            let modeValue = Int64(compilationCtx.options.lazyThreadSafetyMode.rawValue)
                            let modeExpr = arena.appendExpr(.intLiteral(modeValue), type: sema.types.anyType)
                            initInstructions.append(.constValue(result: modeExpr, value: .intLiteral(modeValue)))
                            // Emit kk_lazy_create(lambdaFnPtr, mode).
                            let createResult = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)), type: delegateType
                            )
                            let lazyCreateName = interner.intern("kk_lazy_create")
                            initInstructions.append(.call(
                                symbol: nil,
                                callee: lazyCreateName,
                                arguments: [lambdaFnPtr, modeExpr],
                                result: createResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            // Store delegate handle in the backing field global.
                            initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))

                        case .observable:
                            // Lower the initial value argument from the delegate expression.
                            let initialValueExpr = lowerDelegateInitialValue(
                                delegateExpr: propertyDecl.delegateExpression,
                                shared: shared,
                                emit: &initInstructions
                            )
                            // Create callback lambda from delegate body (3 params: prop, old, new).
                            let callbackFnPtr = lowerDelegateLambdaBody(
                                delegateBody: propertyDecl.delegateBody,
                                propertySymbol: symbol,
                                paramCount: 3,
                                shared: shared,
                                emit: &initInstructions
                            )
                            // Emit kk_observable_create(initialValue, callbackFnPtr).
                            let createResult = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)), type: delegateType
                            )
                            let observableCreateName = interner.intern("kk_observable_create")
                            initInstructions.append(.call(
                                symbol: nil,
                                callee: observableCreateName,
                                arguments: [initialValueExpr, callbackFnPtr],
                                result: createResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            // Store delegate handle in the backing field global.
                            initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))

                        case .vetoable:
                            // Lower the initial value argument from the delegate expression.
                            let initialValueExpr = lowerDelegateInitialValue(
                                delegateExpr: propertyDecl.delegateExpression,
                                shared: shared,
                                emit: &initInstructions
                            )
                            // Create callback lambda from delegate body (3 params: prop, old, new).
                            let callbackFnPtr = lowerDelegateLambdaBody(
                                delegateBody: propertyDecl.delegateBody,
                                propertySymbol: symbol,
                                paramCount: 3,
                                shared: shared,
                                emit: &initInstructions
                            )
                            // Emit kk_vetoable_create(initialValue, callbackFnPtr).
                            let createResult = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)), type: delegateType
                            )
                            let vetoableCreateName = interner.intern("kk_vetoable_create")
                            initInstructions.append(.call(
                                symbol: nil,
                                callee: vetoableCreateName,
                                arguments: [initialValueExpr, callbackFnPtr],
                                result: createResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            // Store delegate handle in the backing field global.
                            initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))

                        case .custom:
                            // Custom delegate: lower the full delegate expression as the
                            // delegate object and store it directly. The runtime's
                            // getValue/setValue will be called through
                            // kk_property_access at use-sites.
                            let delegateObjExpr = lowerExpr(
                                propertyDecl.delegateExpression!,
                                shared: shared,
                                emit: &initInstructions
                            )
                            // Emit kk_custom_delegate_create(delegateObj) to wrap the
                            // delegate into the standard handle format.
                            let createResult = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)), type: delegateType
                            )
                            let customCreateName = interner.intern("kk_custom_delegate_create")
                            initInstructions.append(.call(
                                symbol: nil,
                                callee: customCreateName,
                                arguments: [delegateObjExpr],
                                result: createResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            // Store delegate handle in the backing field global.
                            initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))
                        }

                        allTopLevelInitInstructions.append(contentsOf: initInstructions)
                        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
                    }

                case .typeAliasDecl:
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                    declIDs.append(kirID)

                case .enumEntryDecl:
                    let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: sema.types.anyType)))
                    declIDs.append(kirID)
                }
            }
            files.append(KIRFile(fileID: file.fileID, decls: declIDs))
        }

        if !ctx.companionInitializerFunctions.isEmpty {
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
}
