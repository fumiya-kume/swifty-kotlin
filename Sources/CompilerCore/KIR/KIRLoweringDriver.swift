import Foundation

/// Dispatch hub for KIR lowering. Replaces the monolithic extension-based splitting
/// of `BuildKIRPhase` with independent delegate classes.
///
/// Each delegate holds an `unowned` back-reference to this driver so that mutually
/// recursive calls (e.g. `lowerExpr` → `lowerCallExpr` → `lowerExpr`) can be
/// dispatched through the driver rather than sharing a single fat class instance.
final class KIRLoweringDriver {
    let ctx: KIRLoweringContext

    // Delegates (lazy to break initialization ordering; each holds unowned back-reference)
    private(set) lazy var exprLowerer = ExprLowerer(driver: self)
    private(set) lazy var callLowerer = CallLowerer(driver: self)
    private(set) lazy var controlFlowLowerer = ControlFlowLowerer(driver: self)
    private(set) lazy var memberLowerer = MemberLowerer(driver: self)
    private(set) lazy var lambdaLowerer = LambdaLowerer(driver: self)
    private(set) lazy var objectLiteralLowerer = ObjectLiteralLowerer(driver: self)
    private(set) lazy var callSupportLowerer = CallSupportLowerer(driver: self)

    // Stateless utilities (no back-reference needed)
    let constantCollector = ConstantCollector()

    init(ctx: KIRLoweringContext) {
        self.ctx = ctx
    }

    // MARK: - Main Recursive Dispatch Entry Point

    func lowerExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        return exprLowerer.lowerExpr(
            exprID,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }

    // MARK: - Module Lowering

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
        ctx.functionDefaultArgumentsBySymbol = callSupportLowerer.collectFunctionDefaultArgumentExpressions(
            ast: ast,
            sema: sema
        )

        for file in ast.sortedFiles {
            var declIDs: [KIRDeclID] = []
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      let symbol = sema.bindings.declSymbols[declID] else {
                    continue
                }

                switch decl {
                case .classDecl(let classDecl):
                    // Collect nested objects including the companion object
                    var allNestedObjects = classDecl.nestedObjects
                    if let companionDeclID = classDecl.companionObject {
                        allNestedObjects.append(companionDeclID)
                    }
                    let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
                        memberFunctions: classDecl.memberFunctions,
                        memberProperties: classDecl.memberProperties,
                        nestedClasses: classDecl.nestedClasses,
                        nestedObjects: allNestedObjects,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: compilationCtx.interner,
                        propertyConstantInitializers: propertyConstantInitializers
                    )
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
                    declIDs.append(kirID)
                    declIDs.append(contentsOf: allDecls)

                    let ctorFQName = (sema.symbols.symbol(symbol)?.fqName ?? []) + [compilationCtx.interner.intern("<init>")]
                    let ctorSymbols = sema.symbols.lookupAll(
                        fqName: ctorFQName
                    )
                    for ctorSymbol in ctorSymbols {
                        guard let signature = sema.symbols.functionSignature(for: ctorSymbol) else {
                            continue
                        }
                        ctx.resetScopeForFunction()
                        ctx.beginCallableLoweringScope()

                        let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: ctorSymbol)
                        var params = [KIRParameter(symbol: receiverSymbol, type: signature.returnType)]
                        ctx.currentImplicitReceiverSymbol = receiverSymbol
                        ctx.currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: signature.returnType)

                        params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                            KIRParameter(symbol: pair.0, type: pair.1)
                        })
                        let returnType = signature.returnType
                        var body: [KIRInstruction] = [.beginBlock]

                        if let receiverExpr = ctx.currentImplicitReceiverExprID,
                           let receiverSym = ctx.currentImplicitReceiverSymbol {
                            body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSym)))
                        }

                        let isSecondary = sema.symbols.symbol(ctorSymbol)?.declSite != classDecl.range

                        if !isSecondary {
                            // Emit member property initializers as field stores.
                            for propDeclID in classDecl.memberProperties {
                                guard let propDecl = ast.arena.decl(propDeclID),
                                      case .propertyDecl(let prop) = propDecl,
                                      let propSymbol = sema.bindings.declSymbols[propDeclID],
                                      let initExpr = prop.initializer else {
                                    continue
                                }
                                let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
                                let propType = sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
                                let initValue = lowerExpr(
                                    initExpr,
                                    ast: ast,
                                    sema: sema,
                                    arena: arena,
                                    interner: compilationCtx.interner,
                                    propertyConstantInitializers: propertyConstantInitializers,
                                    instructions: &body
                                )
                                let fieldRef = arena.appendExpr(.symbolRef(targetSymbol), type: propType)
                                body.append(.copy(from: initValue, to: fieldRef))
                            }

                            for initBlock in classDecl.initBlocks {
                                switch initBlock {
                                case .block(let exprIDs, _):
                                    for exprID in exprIDs {
                                        _ = lowerExpr(
                                            exprID,
                                            ast: ast,
                                            sema: sema,
                                            arena: arena,
                                            interner: compilationCtx.interner,
                                            propertyConstantInitializers: propertyConstantInitializers,
                                            instructions: &body
                                        )
                                    }
                                case .expr(let exprID, _):
                                    _ = lowerExpr(
                                        exprID,
                                        ast: ast,
                                        sema: sema,
                                        arena: arena,
                                        interner: compilationCtx.interner,
                                        propertyConstantInitializers: propertyConstantInitializers,
                                        instructions: &body
                                    )
                                case .unit:
                                    break
                                }
                            }
                        }

                        if isSecondary {
                            for secondaryCtor in classDecl.secondaryConstructors {
                                guard secondaryCtor.range == sema.symbols.symbol(ctorSymbol)?.declSite else {
                                    continue
                                }
                                if let delegation = secondaryCtor.delegationCall {
                                    let delegationTarget: [InternedString]
                                    switch delegation.kind {
                                    case .this:
                                        delegationTarget = ctorFQName
                                    case .super_:
                                        let supertypes = sema.symbols.directSupertypes(for: symbol)
                                        let classSupertypes = supertypes.filter {
                                            let kind = sema.symbols.symbol($0)?.kind
                                            return kind == .class || kind == .enumClass
                                        }
                                        if let superclass = classSupertypes.first {
                                            delegationTarget = (sema.symbols.symbol(superclass)?.fqName ?? []) + [compilationCtx.interner.intern("<init>")]
                                        } else {
                                            delegationTarget = []
                                        }
                                    }
                                    if !delegationTarget.isEmpty {
                                        var argIDs: [KIRExprID] = []
                                        if let receiver = ctx.currentImplicitReceiverExprID {
                                            argIDs.append(receiver)
                                        }
                                        for arg in delegation.args {
                                            let lowered = lowerExpr(
                                                arg.expr,
                                                ast: ast,
                                                sema: sema,
                                                arena: arena,
                                                interner: compilationCtx.interner,
                                                propertyConstantInitializers: propertyConstantInitializers,
                                                instructions: &body
                                            )
                                            argIDs.append(lowered)
                                        }
                                        let delegationResultID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.unitType)
                                        body.append(.call(
                                            symbol: sema.symbols.lookupAll(fqName: delegationTarget).first,
                                            callee: compilationCtx.interner.intern("<init>"),
                                            arguments: argIDs,
                                            result: delegationResultID,
                                            canThrow: false,
                                            thrownResult: nil
                                        ))
                                    }
                                }
                                switch secondaryCtor.body {
                                case .block(let exprIDs, _):
                                    for exprID in exprIDs {
                                        _ = lowerExpr(
                                            exprID,
                                            ast: ast,
                                            sema: sema,
                                            arena: arena,
                                            interner: compilationCtx.interner,
                                            propertyConstantInitializers: propertyConstantInitializers,
                                            instructions: &body
                                        )
                                    }
                                case .expr(let exprID, _):
                                    _ = lowerExpr(
                                        exprID,
                                        ast: ast,
                                        sema: sema,
                                        arena: arena,
                                        interner: compilationCtx.interner,
                                        propertyConstantInitializers: propertyConstantInitializers,
                                        instructions: &body
                                    )
                                case .unit:
                                    break
                                }
                                break
                            }
                        }

                        if let receiver = ctx.currentImplicitReceiverExprID {
                            body.append(.returnValue(receiver))
                        } else {
                            body.append(.returnUnit)
                        }
                        body.append(.endBlock)

                        let ctorKirID = arena.appendDecl(
                            .function(
                                KIRFunction(
                                    symbol: ctorSymbol,
                                    name: classDecl.name,
                                    params: params,
                                    returnType: returnType,
                                    body: body,
                                    isSuspend: false,
                                    isInline: false
                                )
                            )
                        )
                        declIDs.append(ctorKirID)
                        // Generate default argument stub for constructors with defaults.
                        if let defaults = ctx.functionDefaultArgumentsBySymbol[ctorSymbol] {
                            let stubID = callSupportLowerer.generateDefaultStubFunction(
                                originalSymbol: ctorSymbol,
                                originalName: classDecl.name,
                                signature: signature,
                                defaultExpressions: defaults,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: compilationCtx.interner,
                                propertyConstantInitializers: propertyConstantInitializers
                            )
                            declIDs.append(stubID)
                        }
                        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
                    }

                case .interfaceDecl(let interfaceDecl):
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
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: compilationCtx.interner,
                        propertyConstantInitializers: propertyConstantInitializers
                    )
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
                    declIDs.append(kirID)
                    declIDs.append(contentsOf: allDecls)

                case .objectDecl(let objectDecl):
                    let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
                        memberFunctions: objectDecl.memberFunctions,
                        memberProperties: objectDecl.memberProperties,
                        nestedClasses: objectDecl.nestedClasses,
                        nestedObjects: objectDecl.nestedObjects,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: compilationCtx.interner,
                        propertyConstantInitializers: propertyConstantInitializers
                    )
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
                    declIDs.append(kirID)
                    declIDs.append(contentsOf: allDecls)

                case .funDecl(let function):
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
                       !signature.reifiedTypeParameterIndices.isEmpty {
                        let intType = sema.types.make(.primitive(.int, .nonNull))
                        for index in signature.reifiedTypeParameterIndices.sorted() {
                            guard index < signature.typeParameterSymbols.count else { continue }
                            let typeParamSymbol = signature.typeParameterSymbols[index]
                            let tokenSymbol = SymbolID(rawValue: -20_000 - typeParamSymbol.rawValue)
                            params.append(KIRParameter(symbol: tokenSymbol, type: intType))
                        }
                    }
                    let returnType = signature?.returnType ?? sema.types.unitType
                    var body: [KIRInstruction] = [.beginBlock]
                    if let receiverExpr = ctx.currentImplicitReceiverExprID,
                       let receiverSymbol = ctx.currentImplicitReceiverSymbol {
                        body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))
                    }
                    switch function.body {
                    case .block(let exprIDs, _):
                        var lastValue: KIRExprID?
                        var terminatedByReturn = false
                        for exprID in exprIDs {
                            if let expr = ast.arena.expr(exprID),
                               case .returnExpr(let value, _) = expr {
                                if let value {
                                    let lowered = lowerExpr(
                                        value,
                                        ast: ast,
                                        sema: sema,
                                        arena: arena,
                                        interner: compilationCtx.interner,
                                        propertyConstantInitializers: propertyConstantInitializers,
                                        instructions: &body
                                    )
                                    body.append(.returnValue(lowered))
                                } else {
                                    body.append(.returnUnit)
                                }
                                terminatedByReturn = true
                                break
                            }
                            if let expr = ast.arena.expr(exprID),
                               case .throwExpr = expr {
                                _ = lowerExpr(
                                    exprID,
                                    ast: ast,
                                    sema: sema,
                                    arena: arena,
                                    interner: compilationCtx.interner,
                                    propertyConstantInitializers: propertyConstantInitializers,
                                    instructions: &body
                                )
                                terminatedByReturn = true
                                break
                            }
                            lastValue = lowerExpr(
                                exprID,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: compilationCtx.interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &body
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
                    case .expr(let exprID, _):
                        let value = lowerExpr(
                            exprID,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: compilationCtx.interner,
                            propertyConstantInitializers: propertyConstantInitializers,
                            instructions: &body
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
                                isInline: function.isInline
                            )
                        )
                    )
                    declIDs.append(kirID)
                    if let defaults = ctx.functionDefaultArgumentsBySymbol[symbol],
                       let sig = signature {
                        let stubID = callSupportLowerer.generateDefaultStubFunction(
                            originalSymbol: symbol,
                            originalName: function.name,
                            signature: sig,
                            defaultExpressions: defaults,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: compilationCtx.interner,
                            propertyConstantInitializers: propertyConstantInitializers
                        )
                        declIDs.append(stubID)
                    }
                    declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
                    ctx.currentImplicitReceiverExprID = nil
                    ctx.currentImplicitReceiverSymbol = nil

                case .propertyDecl:
                    let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: sema.types.anyType)))
                    declIDs.append(kirID)

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

        return KIRModule(files: files, arena: arena)
    }
}
