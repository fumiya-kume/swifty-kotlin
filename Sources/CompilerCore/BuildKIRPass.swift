import Foundation

public final class BuildKIRPhase: CompilerPhase {
    public static let name = "BuildKIR"
    private var functionDefaultArgumentsBySymbol: [SymbolID: [ExprID?]] = [:]
    private var localValuesBySymbol: [SymbolID: KIRExprID] = [:]
    private var currentImplicitReceiverExprID: KIRExprID?
    private var currentImplicitReceiverSymbol: SymbolID?
    private var loopControlStack: [(continueLabel: Int32, breakLabel: Int32)] = []
    private var nextLoopLabel: Int32 = 10_000

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
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                    declIDs.append(kirID)

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

                        let params = zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                            KIRParameter(symbol: pair.0, type: pair.1)
                        }
                        let returnType = signature.returnType
                        var body: [KIRInstruction] = [.beginBlock]

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

                        body.append(.returnUnit)
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

                case .interfaceDecl, .objectDecl:
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                    declIDs.append(kirID)

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

    private func lowerExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        guard let expr = ast.arena.expr(exprID) else {
            let temp = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.errorType)
            instructions.append(.constValue(result: temp, value: .unit))
            return temp
        }
        let stringType = sema.types.make(.primitive(.string, .nonNull))

        switch expr {
        case .intLiteral(let value, _):
            let id = arena.appendExpr(.intLiteral(value), type: boundType ?? intType)
            instructions.append(.constValue(result: id, value: .intLiteral(value)))
            return id

        case .boolLiteral(let value, _):
            let id = arena.appendExpr(.boolLiteral(value), type: boundType ?? boolType)
            instructions.append(.constValue(result: id, value: .boolLiteral(value)))
            return id

        case .stringLiteral(let value, _):
            let id = arena.appendExpr(.stringLiteral(value), type: boundType ?? stringType)
            instructions.append(.constValue(result: id, value: .stringLiteral(value)))
            return id

        case .nameRef(let name, _):
            if interner.resolve(name) == "null" {
                let id = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
                instructions.append(.constValue(result: id, value: .null))
                return id
            }
            if interner.resolve(name) == "this",
               let currentImplicitReceiverExprID {
                return currentImplicitReceiverExprID
            }
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                if let localValue = localValuesBySymbol[symbol] {
                    return localValue
                }
                if let constant = propertyConstantInitializers[symbol] {
                    let id = arena.appendExpr(constant, type: boundType)
                    instructions.append(.constValue(result: id, value: constant))
                    return id
                }
                let id = arena.appendExpr(.symbolRef(symbol), type: boundType)
                instructions.append(.constValue(result: id, value: .symbolRef(symbol)))
                return id
            }
            let id = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: id, value: .unit))
            return id

        case .forExpr(_, let iterableExpr, let bodyExpr, _):
            let iterableID = lowerExpr(
                iterableExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let iteratorID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("iterator"),
                arguments: [iterableID],
                result: iteratorID,
                canThrow: false,
                thrownResult: nil
            ))

            let continueLabel = makeLoopLabel()
            let breakLabel = makeLoopLabel()
            instructions.append(.label(continueLabel))

            let hasNextID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("hasNext"),
                arguments: [iteratorID],
                result: hasNextID,
                canThrow: false,
                thrownResult: nil
            ))
            let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
            instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
            instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

            let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
            let previousLoopValue = loopVariableSymbol.flatMap { localValuesBySymbol[$0] }
            let nextValueID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("next"),
                arguments: [iteratorID],
                result: nextValueID,
                canThrow: false,
                thrownResult: nil
            ))
            if let loopVariableSymbol {
                localValuesBySymbol[loopVariableSymbol] = nextValueID
            }

            loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel))
            _ = lowerExpr(
                bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            _ = loopControlStack.popLast()
            instructions.append(.jump(continueLabel))
            instructions.append(.label(breakLabel))

            if let loopVariableSymbol {
                if let previousLoopValue {
                    localValuesBySymbol[loopVariableSymbol] = previousLoopValue
                } else {
                    localValuesBySymbol.removeValue(forKey: loopVariableSymbol)
                }
            }

            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .whileExpr(let conditionExpr, let bodyExpr, _):
            let continueLabel = makeLoopLabel()
            let breakLabel = makeLoopLabel()
            instructions.append(.label(continueLabel))

            let conditionID = lowerExpr(
                conditionExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
            instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
            instructions.append(.jumpIfEqual(lhs: conditionID, rhs: falseID, target: breakLabel))

            loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel))
            _ = lowerExpr(
                bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            _ = loopControlStack.popLast()
            instructions.append(.jump(continueLabel))
            instructions.append(.label(breakLabel))

            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .doWhileExpr(let bodyExpr, let conditionExpr, _):
            let bodyLabel = makeLoopLabel()
            let continueLabel = makeLoopLabel()
            let breakLabel = makeLoopLabel()
            instructions.append(.label(bodyLabel))

            loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel))
            _ = lowerExpr(
                bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            _ = loopControlStack.popLast()

            instructions.append(.label(continueLabel))
            let conditionID = lowerExpr(
                conditionExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
            instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
            instructions.append(.jumpIfEqual(lhs: conditionID, rhs: falseID, target: breakLabel))
            instructions.append(.jump(bodyLabel))
            instructions.append(.label(breakLabel))

            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .breakExpr:
            if let breakLabel = loopControlStack.last?.breakLabel {
                instructions.append(.jump(breakLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .continueExpr:
            if let continueLabel = loopControlStack.last?.continueLabel {
                instructions.append(.jump(continueLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .localDecl(_, _, let initializer, _):
            let initializerID = lowerExpr(
                initializer,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                localValuesBySymbol[symbol] = initializerID
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .localAssign(_, let valueExpr, _):
            let valueID = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                localValuesBySymbol[symbol] = valueID
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .arrayAccess(let arrayExpr, let indexExpr, _):
            let arrayID = lowerExpr(
                arrayExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let indexID = lowerExpr(
                indexExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get"),
                arguments: [arrayID, indexID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .arrayAssign(let arrayExpr, let indexExpr, let valueExpr, _):
            let arrayID = lowerExpr(
                arrayExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let indexID = lowerExpr(
                indexExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let valueID = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [arrayID, indexID, valueID],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .returnExpr(let value, _):
            if let value {
                return lowerExpr(
                    value,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            let conditionID = lowerExpr(
                condition,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let thenID = lowerExpr(
                thenExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let elseID: KIRExprID
            if let elseExpr {
                elseID = lowerExpr(
                    elseExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                elseID = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: elseID, value: .unit))
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
            instructions.append(.select(
                condition: conditionID,
                thenValue: thenID,
                elseValue: elseID,
                result: result
            ))
            return result

        case .tryExpr(let bodyExpr, let catchClauses, let finallyExpr, _):
            let exceptionSlot = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
            let zeroInit = arena.appendExpr(.intLiteral(0), type: sema.types.anyType)
            instructions.append(.constValue(result: zeroInit, value: .intLiteral(0)))
            instructions.append(.copy(from: zeroInit, to: exceptionSlot))

            let tryResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)

            let catchDispatchLabel = makeLoopLabel()
            let finallyLabel = makeLoopLabel()
            let rethrowLabel = makeLoopLabel()
            let endLabel = makeLoopLabel()

            var clauseLabels: [Int32] = []
            for _ in catchClauses {
                clauseLabels.append(makeLoopLabel())
            }

            var bodyInstructions: [KIRInstruction] = []
            let bodyResultID = lowerExpr(
                bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &bodyInstructions
            )

            for instruction in bodyInstructions {
                if case .call(let symbol, let callee, let arguments, let result, _, let existingThrownResult) = instruction,
                   existingThrownResult == nil {
                    instructions.append(.call(
                        symbol: symbol,
                        callee: callee,
                        arguments: arguments,
                        result: result,
                        canThrow: true,
                        thrownResult: exceptionSlot
                    ))
                    instructions.append(.jumpIfNotNull(value: exceptionSlot, target: catchDispatchLabel))
                } else if case .rethrow(let value) = instruction {
                    instructions.append(.copy(from: value, to: exceptionSlot))
                    instructions.append(.jump(catchDispatchLabel))
                } else {
                    instructions.append(instruction)
                }
            }

            instructions.append(.copy(from: bodyResultID, to: tryResult))
            instructions.append(.jump(finallyLabel))

            instructions.append(.label(catchDispatchLabel))
            if !catchClauses.isEmpty {
                instructions.append(.jump(clauseLabels[0]))

                for (index, clause) in catchClauses.enumerated() {
                    instructions.append(.label(clauseLabels[index]))

                    if clause.paramName != nil {
                        let paramID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
                        instructions.append(.copy(from: exceptionSlot, to: paramID))
                        if let catchParamSymbol = sema.bindings.identifierSymbols[clause.body] {
                            localValuesBySymbol[catchParamSymbol] = paramID
                        }
                    }

                    let catchBodyResult = lowerExpr(
                        clause.body,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )

                    instructions.append(.copy(from: catchBodyResult, to: tryResult))

                    let clearVal = arena.appendExpr(.intLiteral(0), type: sema.types.anyType)
                    instructions.append(.constValue(result: clearVal, value: .intLiteral(0)))
                    instructions.append(.copy(from: clearVal, to: exceptionSlot))

                    instructions.append(.jump(finallyLabel))
                }
            } else {
                instructions.append(.jump(finallyLabel))
            }

            instructions.append(.label(finallyLabel))
            if let finallyExpr {
                _ = lowerExpr(
                    finallyExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            instructions.append(.jumpIfNotNull(value: exceptionSlot, target: rethrowLabel))
            instructions.append(.jump(endLabel))

            instructions.append(.label(rethrowLabel))
            instructions.append(.rethrow(value: exceptionSlot))

            instructions.append(.label(endLabel))
            return tryResult



        case .binary(let op, let lhs, let rhs, _):
            let lhsID = lowerExpr(
                lhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let rhsID = lowerExpr(
                rhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
            if let callBinding = sema.bindings.callBindings[exprID],
               let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
               signature.receiverType != nil {
                var finalArguments = normalizedCallArguments(
                    providedArguments: [rhsID],
                    callBinding: callBinding,
                    chosenCallee: callBinding.chosenCallee,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                finalArguments.insert(lhsID, at: 0)
                let loweredCalleeName: InternedString
                if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                   !externalLinkName.isEmpty {
                    loweredCalleeName = interner.intern(externalLinkName)
                } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                    loweredCalleeName = symbol.name
                } else {
                    loweredCalleeName = binaryOperatorFunctionName(for: op, interner: interner)
                }
                instructions.append(.call(
                    symbol: callBinding.chosenCallee,
                    callee: loweredCalleeName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if case .add = op, sema.bindings.exprTypes[exprID] == stringType {
                instructions.append(
                    .call(
                        symbol: nil,
                        callee: interner.intern("kk_string_concat"),
                        arguments: [lhsID, rhsID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    )
                )
                return result
            }
            if let runtimeCallee = builtinBinaryRuntimeCallee(for: op, interner: interner) {
                instructions.append(
                    .call(
                        symbol: nil,
                        callee: runtimeCallee,
                        arguments: [lhsID, rhsID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    )
                )
                return result
            }
            let kirOp: KIRBinaryOp
            switch op {
            case .add:
                kirOp = .add
            case .subtract:
                kirOp = .subtract
            case .multiply:
                kirOp = .multiply
            case .divide:
                kirOp = .divide
            case .modulo:
                kirOp = .modulo
            case .equal:
                kirOp = .equal
            case .notEqual:
                kirOp = .notEqual
            case .lessThan:
                kirOp = .lessThan
            case .lessOrEqual:
                kirOp = .lessOrEqual
            case .greaterThan:
                kirOp = .greaterThan
            case .greaterOrEqual:
                kirOp = .greaterOrEqual
            case .logicalAnd:
                kirOp = .logicalAnd
            case .logicalOr:
                kirOp = .logicalOr
            case .elvis:
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_elvis"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            case .rangeTo:
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_rangeTo"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            instructions.append(.binary(op: kirOp, lhs: lhsID, rhs: rhsID, result: result))
            return result

        case .call(let calleeExpr, let args, _):
            let calleeName: InternedString
            if let callee = ast.arena.expr(calleeExpr), case .nameRef(let name, _) = callee {
                calleeName = name
            } else {
                calleeName = sema.symbols.allSymbols().first?.name ?? InternedString()
            }
            let loweredArgIDs = args.map { argument in
                lowerExpr(
                    argument.expr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            let callBinding = sema.bindings.callBindings[exprID]
            let chosen = callBinding?.chosenCallee
            var finalArgIDs = normalizedCallArguments(
                providedArguments: loweredArgIDs,
                callBinding: callBinding,
                chosenCallee: chosen,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let callBinding, let chosen,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    finalArgIDs.append(tokenExpr)
                }
            }
            let loweredCalleeName: InternedString
            if let chosen,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               !externalLinkName.isEmpty {
                loweredCalleeName = interner.intern(externalLinkName)
            } else if chosen == nil {
                loweredCalleeName = loweredRuntimeBuiltinCallee(
                    for: calleeName,
                    argumentCount: finalArgIDs.count,
                    interner: interner
                ) ?? calleeName
            } else {
                loweredCalleeName = calleeName
            }
            instructions.append(.call(
                symbol: chosen,
                callee: loweredCalleeName,
                arguments: finalArgIDs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .memberCall(let receiverExpr, let calleeName, let args, _):
            let loweredReceiverID = lowerExpr(
                receiverExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let loweredArgIDs = args.map { argument in
                lowerExpr(
                    argument.expr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            let callBinding = sema.bindings.callBindings[exprID]
            let chosen = callBinding?.chosenCallee
            let normalizedArgs = normalizedCallArguments(
                providedArguments: loweredArgIDs,
                callBinding: callBinding,
                chosenCallee: chosen,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            var finalArguments = normalizedArgs
            if let chosen,
               let signature = sema.symbols.functionSignature(for: chosen),
               signature.receiverType != nil {
                finalArguments.insert(loweredReceiverID, at: 0)
            }
            if let callBinding, let chosen,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    finalArguments.append(tokenExpr)
                }
            }
            let loweredMemberCalleeName: InternedString
            if let chosen,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               !externalLinkName.isEmpty {
                loweredMemberCalleeName = interner.intern(externalLinkName)
            } else {
                loweredMemberCalleeName = calleeName
            }
            instructions.append(.call(
                symbol: chosen,
                callee: loweredMemberCalleeName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .unaryExpr(let op, let operandExpr, _):
            let operandID = lowerExpr(
                operandExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            switch op {
            case .unaryPlus:
                return operandID
            case .unaryMinus:
                let zero = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: zero, value: .intLiteral(0)))
                let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? intType)
                instructions.append(.binary(op: .subtract, lhs: zero, rhs: operandID, result: result))
                return result
            case .not:
                let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
                instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
                let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
                instructions.append(.binary(op: .equal, lhs: operandID, rhs: falseValue, result: result))
                return result
            }

        case .isCheck(let exprToCheck, _, _, _):
            let operandID = lowerExpr(
                exprToCheck,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [operandID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .asCast(let exprToCast, _, _, _):
            let operandID = lowerExpr(
                exprToCast,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_cast"),
                arguments: [operandID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .nullAssert(let innerExpr, _):
            let operandID = lowerExpr(
                innerExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.nullAssert(operand: operandID, result: result))
            return result

        case .safeMemberCall(let receiverExpr, let calleeName, let args, _):
            let loweredReceiverID = lowerExpr(
                receiverExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let loweredArgIDs = args.map { argument in
                lowerExpr(
                    argument.expr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            let callBinding = sema.bindings.callBindings[exprID]
            let chosen = callBinding?.chosenCallee
            let normalizedArgs = normalizedCallArguments(
                providedArguments: loweredArgIDs,
                callBinding: callBinding,
                chosenCallee: chosen,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            var finalArguments = normalizedArgs
            if let chosen,
               let signature = sema.symbols.functionSignature(for: chosen),
               signature.receiverType != nil {
                finalArguments.insert(loweredReceiverID, at: 0)
            }
            let loweredMemberCalleeName: InternedString
            if let chosen,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               !externalLinkName.isEmpty {
                loweredMemberCalleeName = interner.intern(externalLinkName)
            } else {
                loweredMemberCalleeName = calleeName
            }
            instructions.append(.call(
                symbol: chosen,
                callee: loweredMemberCalleeName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .compoundAssign(_, _, let valueExpr, _):
            let valueID = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                localValuesBySymbol[symbol] = valueID
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .whenExpr(let subject, let branches, let elseExpr, _):
            let subjectID = lowerExpr(
                subject,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let fallbackID: KIRExprID
            if let elseExpr {
                fallbackID = lowerExpr(
                    elseExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                fallbackID = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: fallbackID, value: .unit))
            }

            var selectedID = fallbackID
            for branch in branches.reversed() {
                let bodyID = lowerExpr(
                    branch.body,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                guard let conditionExprID = branch.condition else {
                    selectedID = bodyID
                    continue
                }

                let conditionValueID = lowerExpr(
                    conditionExprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )

                let matchesID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
                instructions.append(.binary(
                    op: .equal,
                    lhs: subjectID,
                    rhs: conditionValueID,
                    result: matchesID
                ))

                let nextSelectedID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
                instructions.append(.select(
                    condition: matchesID,
                    thenValue: bodyID,
                    elseValue: selectedID,
                    result: nextSelectedID
                ))
                selectedID = nextSelectedID
            }
            return selectedID
        }
    }

    private func collectPropertyConstantInitializers(
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        sourceByFileID: [Int32: String]
    ) -> [SymbolID: KIRExprKind] {
        var mapping: [SymbolID: KIRExprKind] = [:]
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case .propertyDecl(let property) = decl,
                      let symbol = sema.bindings.declSymbols[declID] else {
                    continue
                }
                let constant =
                    literalConstantExpr(property: property, ast: ast) ??
                    inlineGetterConstantExpr(
                        propertyName: interner.resolve(property.name),
                        source: sourceByFileID[file.fileID.rawValue] ?? "",
                        interner: interner
                    )
                guard let constant else {
                    continue
                }
                mapping[symbol] = constant
                if let propertySymbol = sema.symbols.symbol(symbol) {
                    let related = sema.symbols.lookupAll(fqName: propertySymbol.fqName)
                    for relatedID in related {
                        guard let relatedSymbol = sema.symbols.symbol(relatedID) else {
                            continue
                        }
                        if relatedSymbol.kind == .property || relatedSymbol.kind == .field {
                            mapping[relatedID] = constant
                        }
                    }
                }
            }
        }
        return mapping
    }

    private func collectFunctionDefaultArgumentExpressions(
        ast: ASTModule,
        sema: SemaModule
    ) -> [SymbolID: [ExprID?]] {
        var mapping: [SymbolID: [ExprID?]] = [:]
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case .funDecl(let function) = decl,
                      let symbol = sema.bindings.declSymbols[declID] else {
                    continue
                }
                let defaults = function.valueParams.map(\.defaultValue)
                if defaults.contains(where: { $0 != nil }) {
                    mapping[symbol] = defaults
                }
            }
        }
        return mapping
    }

    private func normalizedCallArguments(
        providedArguments: [KIRExprID],
        callBinding: CallBinding?,
        chosenCallee: SymbolID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard let callBinding,
              let chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosenCallee) else {
            return providedArguments
        }

        let parameterCount = signature.parameterTypes.count
        guard parameterCount > 0 else {
            return providedArguments
        }

        var argIndicesByParameter: [Int: [Int]] = [:]
        for (argIndex, paramIndex) in callBinding.parameterMapping {
            guard argIndex >= 0, argIndex < providedArguments.count else {
                continue
            }
            argIndicesByParameter[paramIndex, default: []].append(argIndex)
        }
        for key in Array(argIndicesByParameter.keys) {
            argIndicesByParameter[key]?.sort()
        }

        let hasOutOfRangeMapping = argIndicesByParameter.keys.contains(where: { $0 < 0 || $0 >= parameterCount })
        let hasMergedParameterMapping = argIndicesByParameter.values.contains(where: { $0.count > 1 })
        if hasOutOfRangeMapping || hasMergedParameterMapping {
            return providedArguments
        }

        let defaultExpressions = functionDefaultArgumentsBySymbol[chosenCallee] ?? []
        var normalized: [KIRExprID] = []
        normalized.reserveCapacity(parameterCount)

        for paramIndex in 0..<parameterCount {
            if let argIndex = argIndicesByParameter[paramIndex]?.first {
                normalized.append(providedArguments[argIndex])
                continue
            }
            guard paramIndex < defaultExpressions.count,
                  let defaultExprID = defaultExpressions[paramIndex] else {
                return providedArguments
            }
            let loweredDefault = lowerExpr(
                defaultExprID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            normalized.append(loweredDefault)
        }
        return normalized
    }

    private func syntheticReceiverParameterSymbol(functionSymbol: SymbolID) -> SymbolID {
        SymbolID(rawValue: -10_000 - functionSymbol.rawValue)
    }

    private func loweredRuntimeBuiltinCallee(
        for callee: InternedString,
        argumentCount: Int,
        interner: StringInterner
    ) -> InternedString? {
        switch interner.resolve(callee) {
        case "IntArray":
            guard argumentCount == 1 else {
                return nil
            }
            return interner.intern("kk_array_new")
        default:
            return nil
        }
    }

    private func builtinBinaryRuntimeCallee(for op: BinaryOp, interner: StringInterner) -> InternedString? {
        switch op {
        case .notEqual:
            return interner.intern("kk_op_ne")
        case .lessThan:
            return interner.intern("kk_op_lt")
        case .lessOrEqual:
            return interner.intern("kk_op_le")
        case .greaterThan:
            return interner.intern("kk_op_gt")
        case .greaterOrEqual:
            return interner.intern("kk_op_ge")
        case .logicalAnd:
            return interner.intern("kk_op_and")
        case .logicalOr:
            return interner.intern("kk_op_or")
        default:
            return nil
        }
    }

    private func binaryOperatorFunctionName(for op: BinaryOp, interner: StringInterner) -> InternedString {
        switch op {
        case .add:
            return interner.intern("plus")
        case .subtract:
            return interner.intern("minus")
        case .multiply:
            return interner.intern("times")
        case .divide:
            return interner.intern("div")
        case .modulo:
            return interner.intern("rem")
        case .equal:
            return interner.intern("equals")
        case .notEqual:
            return interner.intern("equals")
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            return interner.intern("compareTo")
        case .logicalAnd:
            return interner.intern("and")
        case .logicalOr:
            return interner.intern("or")
        case .elvis:
            return interner.intern("elvis")
        case .rangeTo:
            return interner.intern("rangeTo")
        }
    }

    private func inlineGetterConstantExpr(
        propertyName: String,
        source: String,
        interner: StringInterner
    ) -> KIRExprKind? {
        guard !propertyName.isEmpty else {
            return nil
        }
        let escapedPropertyName = NSRegularExpression.escapedPattern(for: propertyName)
        let pattern = #"(?m)^\s*(?:val|var)\s+\#(escapedPropertyName)\b[^\n]*\n\s*get\s*\(\s*\)\s*=\s*([^\n;]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: source,
                range: NSRange(source.startIndex..<source.endIndex, in: source)
              ),
              match.numberOfRanges >= 2,
              let bodyRange = Range(match.range(at: 1), in: source) else {
            return nil
        }
        let rawBody = source[bodyRange].trimmingCharacters(in: .whitespacesAndNewlines)
        if rawBody == "true" {
            return .boolLiteral(true)
        }
        if rawBody == "false" {
            return .boolLiteral(false)
        }
        let normalized = rawBody.replacingOccurrences(of: "_", with: "")
        if let intValue = Int64(normalized) {
            return .intLiteral(intValue)
        }
        if rawBody.hasPrefix("\""), rawBody.hasSuffix("\""), rawBody.count >= 2 {
            let start = rawBody.index(after: rawBody.startIndex)
            let end = rawBody.index(before: rawBody.endIndex)
            return .stringLiteral(interner.intern(String(rawBody[start..<end])))
        }
        return nil
    }

    private func literalConstantExpr(property: PropertyDecl, ast: ASTModule) -> KIRExprKind? {
        if let initializer = property.initializer,
           let literal = literalConstantExpr(initializer, ast: ast) {
            return literal
        }
        if let getter = property.getter {
            return literalConstantExpr(getterBody: getter.body, ast: ast)
        }
        return nil
    }

    private func literalConstantExpr(getterBody: FunctionBody, ast: ASTModule) -> KIRExprKind? {
        switch getterBody {
        case .expr(let exprID, _):
            return literalConstantExpr(exprID, ast: ast)
        case .block(let exprIDs, _):
            guard let lastExprID = exprIDs.last,
                  let lastExpr = ast.arena.expr(lastExprID) else {
                return nil
            }
            if case .returnExpr(let valueExprID, _) = lastExpr,
               let valueExprID {
                return literalConstantExpr(valueExprID, ast: ast)
            }
            return literalConstantExpr(lastExprID, ast: ast)
        case .unit:
            return nil
        }
    }

    private func literalConstantExpr(_ exprID: ExprID, ast: ASTModule) -> KIRExprKind? {
        guard let expr = ast.arena.expr(exprID) else {
            return nil
        }
        switch expr {
        case .intLiteral(let value, _):
            return .intLiteral(value)
        case .boolLiteral(let value, _):
            return .boolLiteral(value)
        case .stringLiteral(let value, _):
            return .stringLiteral(value)
        default:
            return nil
        }
    }

    private func makeLoopLabel() -> Int32 {
        let label = nextLoopLabel
        nextLoopLabel += 1
        return label
    }
}
