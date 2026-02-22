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
            beginCallableLoweringScope()

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
            allDecls.append(contentsOf: drainGeneratedCallableDecls())
            currentImplicitReceiverExprID = nil
            currentImplicitReceiverSymbol = nil
        }

        for declID in memberProperties {
            guard let decl = ast.arena.decl(declID),
                  case .propertyDecl(let propertyDecl) = decl,
                  let symbol = sema.bindings.declSymbols[declID] else {
                continue
            }
            let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
            let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: propType)))
            directMembers.append(kirID)
            allDecls.append(kirID)

            // Emit backing field global for properties with custom accessors.
            if let backingFieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) {
                let backingFieldType = sema.symbols.propertyType(for: backingFieldSymbol) ?? propType
                let backingFieldKirID = arena.appendDecl(
                    .global(KIRGlobal(symbol: backingFieldSymbol, type: backingFieldType))
                )
                allDecls.append(backingFieldKirID)
            }

            // Lower getter body as a KIR accessor function.
            if let getter = propertyDecl.getter, getter.body != .unit {
                lowerAccessorBody(
                    accessorBody: getter.body,
                    propertySymbol: symbol,
                    propertyType: propType,
                    accessorKind: .getter,
                    setterParamName: nil,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    allDecls: &allDecls
                )
            }

            // Lower setter body as a KIR accessor function.
            if let setter = propertyDecl.setter, setter.body != .unit {
                lowerAccessorBody(
                    accessorBody: setter.body,
                    propertySymbol: symbol,
                    propertyType: propType,
                    accessorKind: .setter,
                    setterParamName: setter.parameterName,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    allDecls: &allDecls
                )
            }

            // Lower delegated property storage as an additional global.
            if propertyDecl.delegateExpression != nil {
                let delegateStorageName = interner.intern("$delegate_\(interner.resolve(propertyDecl.name))")
                let delegateStorageFQName = (sema.symbols.symbol(symbol)?.fqName.dropLast() ?? []) + [delegateStorageName]
                let delegateStorageSymbol = sema.symbols.define(
                    kind: .field,
                    name: delegateStorageName,
                    fqName: Array(delegateStorageFQName),
                    declSite: propertyDecl.range,
                    visibility: .private,
                    flags: []
                )
                let delegateType = sema.types.anyType
                let delegateKirID = arena.appendDecl(
                    .global(KIRGlobal(symbol: delegateStorageSymbol, type: delegateType))
                )
                allDecls.append(delegateKirID)
            }
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

    /// Lower a property getter or setter body as a synthetic KIR function.
    ///
    /// Getter signature: `(<receiver>) -> PropertyType`
    /// Setter signature: `(<receiver>, value: PropertyType) -> Unit`
    func lowerAccessorBody(
        accessorBody: FunctionBody,
        propertySymbol: SymbolID,
        propertyType: TypeID,
        accessorKind: PropertyAccessorKind,
        setterParamName: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        allDecls: inout [KIRDeclID]
    ) {
        localValuesBySymbol.removeAll(keepingCapacity: true)
        currentImplicitReceiverExprID = nil
        currentImplicitReceiverSymbol = nil
        loopControlStack.removeAll(keepingCapacity: true)
        nextLoopLabel = 10_000
        beginCallableLoweringScope()

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        var params: [KIRParameter] = []

        // Add receiver parameter if property has an owner class/object.
        if let ownerSymbol,
           let ownerSym = sema.symbols.symbol(ownerSymbol) {
            let ownerType = sema.types.make(
                .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
            )
            let receiverSymbol = syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
            currentImplicitReceiverSymbol = receiverSymbol
            currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
        }

        let returnType: TypeID
        let accessorName: InternedString
        switch accessorKind {
        case .getter:
            returnType = propertyType
            accessorName = interner.intern("get")
        case .setter:
            returnType = sema.types.unitType
            accessorName = interner.intern("set")
            let valueName = setterParamName ?? interner.intern("value")
            let valueParamSymbol = SymbolID(rawValue: -(propertySymbol.rawValue + 30_000))
            params.append(KIRParameter(symbol: valueParamSymbol, type: propertyType))
            let valueExprID = arena.appendExpr(.symbolRef(valueParamSymbol), type: propertyType)
            localValuesBySymbol[valueParamSymbol] = valueExprID
            _ = valueName
        }

        var body: [KIRInstruction] = [.beginBlock]
        if let receiverExpr = currentImplicitReceiverExprID,
           let receiverSym = currentImplicitReceiverSymbol {
            body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSym)))
        }

        switch accessorBody {
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
                if accessorKind == .getter, let lastValue {
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
            if accessorKind == .getter {
                body.append(.returnValue(value))
            } else {
                body.append(.returnUnit)
            }
        case .unit:
            body.append(.returnUnit)
        }
        body.append(.endBlock)

        // Use a synthetic symbol derived from the property symbol for the accessor.
        let accessorSymbolOffset: Int32 = accessorKind == .getter ? -10_000 : -11_000
        let syntheticAccessorSymbol = SymbolID(rawValue: accessorSymbolOffset - propertySymbol.rawValue)

        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: syntheticAccessorSymbol,
                    name: accessorName,
                    params: params,
                    returnType: returnType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: drainGeneratedCallableDecls())
        currentImplicitReceiverExprID = nil
        currentImplicitReceiverSymbol = nil
    }
}
