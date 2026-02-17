import Foundation

extension BuildKIRPhase {
    func lowerMemberDecls(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) -> (directMembers: [KIRDeclID], allDecls: [KIRDeclID]) {
        var directMembers: [KIRDeclID] = []
        var allDecls: [KIRDeclID] = []

        for declID in memberFunctions {
            guard let decl = ast.arena.decl(declID),
                  case .funDecl(let function) = decl,
                  let symbol = sema.bindings.declSymbols[declID] else {
                continue
            }
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
                                interner: interner,
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
                        interner: interner,
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
                    interner: interner,
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
            directMembers.append(kirID)
            allDecls.append(kirID)
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
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers
                )
                allDecls.append(stubID)
            }
            currentImplicitReceiverExprID = nil
            currentImplicitReceiverSymbol = nil
        }

        for declID in memberProperties {
            guard let symbol = sema.bindings.declSymbols[declID] else {
                continue
            }
            let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
            let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: propType)))
            directMembers.append(kirID)
            allDecls.append(kirID)
        }

        for declID in nestedClasses {
            guard let decl = ast.arena.decl(declID),
                  let symbol = sema.bindings.declSymbols[declID] else {
                continue
            }
            switch decl {
            case .classDecl(let nested):
                let (nestedDirect, nestedAll) = lowerMemberDecls(
                    memberFunctions: nested.memberFunctions,
                    memberProperties: nested.memberProperties,
                    nestedClasses: nested.nestedClasses,
                    nestedObjects: nested.nestedObjects,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers
                )
                let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: nestedDirect)))
                directMembers.append(kirID)
                allDecls.append(kirID)
                allDecls.append(contentsOf: nestedAll)
            case .interfaceDecl:
                let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                directMembers.append(kirID)
                allDecls.append(kirID)
            default:
                continue
            }
        }

        for declID in nestedObjects {
            guard let decl = ast.arena.decl(declID),
                  case .objectDecl(let nested) = decl,
                  let symbol = sema.bindings.declSymbols[declID] else {
                continue
            }
            let (nestedDirect, nestedAll) = lowerMemberDecls(
                memberFunctions: nested.memberFunctions,
                memberProperties: nested.memberProperties,
                nestedClasses: nested.nestedClasses,
                nestedObjects: nested.nestedObjects,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
            let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: nestedDirect)))
            directMembers.append(kirID)
            allDecls.append(kirID)
            allDecls.append(contentsOf: nestedAll)
        }

        return (directMembers, allDecls)
    }
}
