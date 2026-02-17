import Foundation

// Internal visibility is required for cross-file extension decomposition.
public final class BuildKIRPhase: CompilerPhase {
    public static let name = "BuildKIR"
    var functionDefaultArgumentsBySymbol: [SymbolID: [ExprID?]] = [:]
    var localValuesBySymbol: [SymbolID: KIRExprID] = [:]
    var currentImplicitReceiverExprID: KIRExprID?
    var currentImplicitReceiverSymbol: SymbolID?
    var loopControlStack: [(continueLabel: Int32, breakLabel: Int32)] = []
    var nextLoopLabel: Int32 = 10_000

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let ast = ctx.ast, let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Sema phase did not run.")
        }

        let arena = KIRArena()
        var files: [KIRFile] = []
        var sourceByFileID: [Int32: String] = [:]
        for file in ast.files {
            let contents = ctx.sourceManager.contents(of: file.fileID)
            sourceByFileID[file.fileID.rawValue] = String(data: contents, encoding: .utf8) ?? ""
        }
        let propertyConstantInitializers = collectPropertyConstantInitializers(
            ast: ast,
            sema: sema,
            interner: ctx.interner,
            sourceByFileID: sourceByFileID
        )
        functionDefaultArgumentsBySymbol = collectFunctionDefaultArgumentExpressions(
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
                    let (directMembers, allDecls) = lowerMemberDecls(
                        memberFunctions: classDecl.memberFunctions,
                        memberProperties: classDecl.memberProperties,
                        nestedClasses: classDecl.nestedClasses,
                        nestedObjects: classDecl.nestedObjects,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: ctx.interner,
                        propertyConstantInitializers: propertyConstantInitializers
                    )
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
                    declIDs.append(kirID)
                    declIDs.append(contentsOf: allDecls)

                    let ctorFQName = (sema.symbols.symbol(symbol)?.fqName ?? []) + [ctx.interner.intern("<init>")]
                    let ctorSymbols = sema.symbols.lookupAll(
                        fqName: ctorFQName
                    )
                    for ctorSymbol in ctorSymbols {
                        guard let signature = sema.symbols.functionSignature(for: ctorSymbol) else {
                            continue
                        }
                        localValuesBySymbol.removeAll(keepingCapacity: true)
                        currentImplicitReceiverExprID = nil
                        currentImplicitReceiverSymbol = nil
                        loopControlStack.removeAll(keepingCapacity: true)
                        nextLoopLabel = 10_000

                        let receiverSymbol = syntheticReceiverParameterSymbol(functionSymbol: ctorSymbol)
                        var params = [KIRParameter(symbol: receiverSymbol, type: signature.returnType)]
                        currentImplicitReceiverSymbol = receiverSymbol
                        currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: signature.returnType)

                        params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                            KIRParameter(symbol: pair.0, type: pair.1)
                        })
                        let returnType = signature.returnType
                        var body: [KIRInstruction] = [.beginBlock]

                        if let receiverExpr = currentImplicitReceiverExprID,
                           let receiverSym = currentImplicitReceiverSymbol {
                            body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSym)))
                        }

                        let isSecondary = sema.symbols.symbol(ctorSymbol)?.declSite != classDecl.range

                        if !isSecondary {
                            for initBlock in classDecl.initBlocks {
                                switch initBlock {
                                case .block(let exprIDs, _):
                                    for exprID in exprIDs {
                                        _ = lowerExpr(
                                            exprID,
                                            ast: ast,
                                            sema: sema,
                                            arena: arena,
                                            interner: ctx.interner,
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
                                        interner: ctx.interner,
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
                                            delegationTarget = (sema.symbols.symbol(superclass)?.fqName ?? []) + [ctx.interner.intern("<init>")]
                                        } else {
                                            delegationTarget = []
                                        }
                                    }
                                    if !delegationTarget.isEmpty {
                                        var argIDs: [KIRExprID] = []
                                        if let receiver = currentImplicitReceiverExprID {
                                            argIDs.append(receiver)
                                        }
                                        for arg in delegation.args {
                                            let lowered = lowerExpr(
                                                arg.expr,
                                                ast: ast,
                                                sema: sema,
                                                arena: arena,
                                                interner: ctx.interner,
                                                propertyConstantInitializers: propertyConstantInitializers,
                                                instructions: &body
                                            )
                                            argIDs.append(lowered)
                                        }
                                        let delegationResultID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.unitType)
                                        body.append(.call(
                                            symbol: sema.symbols.lookupAll(fqName: delegationTarget).first,
                                            callee: ctx.interner.intern("<init>"),
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
                                            interner: ctx.interner,
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
                                        interner: ctx.interner,
                                        propertyConstantInitializers: propertyConstantInitializers,
                                        instructions: &body
                                    )
                                case .unit:
                                    break
                                }
                                break
                            }
                        }

                        if let receiver = currentImplicitReceiverExprID {
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
                    }

                case .interfaceDecl:
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                    declIDs.append(kirID)

                case .objectDecl(let objectDecl):
                    let (directMembers, allDecls) = lowerMemberDecls(
                        memberFunctions: objectDecl.memberFunctions,
                        memberProperties: objectDecl.memberProperties,
                        nestedClasses: objectDecl.nestedClasses,
                        nestedObjects: objectDecl.nestedObjects,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: ctx.interner,
                        propertyConstantInitializers: propertyConstantInitializers
                    )
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
                    declIDs.append(kirID)
                    declIDs.append(contentsOf: allDecls)

                case .funDecl(let function):
                    localValuesBySymbol.removeAll(keepingCapacity: true)
                    currentImplicitReceiverExprID = nil
                    currentImplicitReceiverSymbol = nil
                    loopControlStack.removeAll(keepingCapacity: true)
                    nextLoopLabel = 10_000
                    let signature = sema.symbols.functionSignature(for: symbol)
                    var params: [KIRParameter] = []
                    if let signature {
                        if let receiverType = signature.receiverType {
                            let receiverSymbol = syntheticReceiverParameterSymbol(functionSymbol: symbol)
                            params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                            currentImplicitReceiverSymbol = receiverSymbol
                            currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
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
                    if let receiverExpr = currentImplicitReceiverExprID,
                       let receiverSymbol = currentImplicitReceiverSymbol {
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
                                        interner: ctx.interner,
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
                                    interner: ctx.interner,
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
                                interner: ctx.interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &body
                            )
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
                            interner: ctx.interner,
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
                    if let defaults = functionDefaultArgumentsBySymbol[symbol],
                       let sig = signature {
                        let stubID = generateDefaultStubFunction(
                            originalSymbol: symbol,
                            originalName: function.name,
                            signature: sig,
                            defaultExpressions: defaults,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: ctx.interner,
                            propertyConstantInitializers: propertyConstantInitializers
                        )
                        declIDs.append(stubID)
                    }
                    currentImplicitReceiverExprID = nil
                    currentImplicitReceiverSymbol = nil

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

        let module = KIRModule(files: files, arena: arena)
        if module.functionCount == 0 && !ctx.diagnostics.hasError {
            ctx.diagnostics.warning(
                "KSWIFTK-KIR-0001",
                "No function declarations found.",
                range: nil
            )
        }
        ctx.kir = module
    }
}

