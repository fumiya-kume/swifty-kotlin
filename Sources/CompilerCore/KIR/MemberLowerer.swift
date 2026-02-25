import Foundation

/// Delegate class for KIR lowering: MemberLowerer.
/// Holds an unowned reference to the driver for mutual recursion.
final class MemberLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

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
            driver.ctx.resetScopeForFunction()
            driver.ctx.beginCallableLoweringScope()

            let signature = sema.symbols.functionSignature(for: symbol)
            var params: [KIRParameter] = []
            if let signature {
                if let receiverType = signature.receiverType {
                    let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: symbol)
                    params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                    driver.ctx.currentImplicitReceiverSymbol = receiverSymbol
                    driver.ctx.currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
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
            if let receiverExpr = driver.ctx.currentImplicitReceiverExprID,
               let receiverSymbol = driver.ctx.currentImplicitReceiverSymbol {
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
                            let lowered = driver.lowerExpr(
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
                    lastValue = driver.lowerExpr(
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
                let value = driver.lowerExpr(
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
            if let defaults = driver.ctx.functionDefaultArgumentsBySymbol[symbol],
               let sig = signature {
                let stubID = driver.callSupportLowerer.generateDefaultStubFunction(
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
            allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
            driver.ctx.currentImplicitReceiverExprID = nil
            driver.ctx.currentImplicitReceiverSymbol = nil
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

            // Lower delegated property: emit delegate storage global and
            // synthesise getter (and setter for var) that call getValue/setValue
            // on the delegate instance.
            if propertyDecl.delegateExpression != nil {
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
                }
                let delegateType = sema.types.anyType
                let delegateKirID = arena.appendDecl(
                    .global(KIRGlobal(symbol: delegateStorageSymbol, type: delegateType))
                )
                allDecls.append(delegateKirID)

                // Synthesise getter: calls getValue on the delegate storage.
                lowerDelegateAccessor(
                    propertySymbol: symbol,
                    propertyType: propType,
                    delegateStorageSymbol: delegateStorageSymbol,
                    accessorKind: .getter,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    allDecls: &allDecls
                )

                // Synthesise setter for var properties: calls setValue on the delegate.
                if propertyDecl.isVar {
                    lowerDelegateAccessor(
                        propertySymbol: symbol,
                        propertyType: propType,
                        delegateStorageSymbol: delegateStorageSymbol,
                        accessorKind: .setter,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        allDecls: &allDecls
                    )
                }
            }
        }

        for declID in nestedClasses {
            guard let decl = ast.arena.decl(declID),
                  let symbol = sema.bindings.declSymbols[declID] else {
                continue
            }
            switch decl {
            case .classDecl(let nested):
                var nestedAllObjects = nested.nestedObjects
                if let companionDeclID = nested.companionObject {
                    nestedAllObjects.append(companionDeclID)
                }
                let (nestedDirect, nestedAll) = lowerMemberDecls(
                    memberFunctions: nested.memberFunctions,
                    memberProperties: nested.memberProperties,
                    nestedClasses: nested.nestedClasses,
                    nestedObjects: nestedAllObjects,
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
            case .interfaceDecl(let nestedInterface):
                // Interface properties have no backing storage; pass empty list.
                var nestedInterfaceAllObjects = nestedInterface.nestedObjects
                if let companionDeclID = nestedInterface.companionObject {
                    nestedInterfaceAllObjects.append(companionDeclID)
                }
                let (nestedDirect, nestedAll) = lowerMemberDecls(
                    memberFunctions: nestedInterface.memberFunctions,
                    memberProperties: [],
                    nestedClasses: nestedInterface.nestedClasses,
                    nestedObjects: nestedInterfaceAllObjects,
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

    /// Synthesise a getter or setter function for a delegated property.
    ///
    /// Getter emits: `return $delegate_x.getValue(thisRef, KProperty("x"))`
    /// Setter emits: `$delegate_x.setValue(thisRef, KProperty("x"), value)`
    ///
    /// The actual `getValue`/`setValue` calls use the delegate storage symbol
    /// so that `PropertyLoweringPass` can later rewrite them to
    /// `kk_property_access`.
    func lowerDelegateAccessor(
        propertySymbol: SymbolID,
        propertyType: TypeID,
        delegateStorageSymbol: SymbolID,
        accessorKind: PropertyAccessorKind,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        allDecls: inout [KIRDeclID]
    ) {
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        var params: [KIRParameter] = []

        // Add receiver parameter if property has an owner class/object.
        if let ownerSymbol,
           let ownerSym = sema.symbols.symbol(ownerSymbol) {
            let ownerType = sema.types.make(
                .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
            )
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
            driver.ctx.currentImplicitReceiverSymbol = receiverSymbol
            driver.ctx.currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
        }

        let returnType: TypeID
        let accessorName: InternedString
        let getValueName = interner.intern("getValue")
        let setValueName = interner.intern("setValue")

        var body: [KIRInstruction] = [.beginBlock]
        if let receiverExpr = driver.ctx.currentImplicitReceiverExprID,
           let receiverSym = driver.ctx.currentImplicitReceiverSymbol {
            body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSym)))
        }

        // Build the thisRef argument (receiver or null for top-level).
        let thisRefExprID: KIRExprID
        if let receiver = driver.ctx.currentImplicitReceiverExprID {
            thisRefExprID = receiver
        } else {
            thisRefExprID = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            body.append(.constValue(result: thisRefExprID, value: .null))
        }

        // Build a KProperty metadata argument (string name of the property).
        let propertyName = sema.symbols.symbol(propertySymbol)?.name ?? interner.intern("")
        let kPropertyExprID = arena.appendExpr(
            .stringLiteral(propertyName),
            type: sema.types.make(.primitive(.string, .nonNull))
        )
        body.append(.constValue(result: kPropertyExprID, value: .stringLiteral(propertyName)))

        switch accessorKind {
        case .getter:
            returnType = propertyType
            accessorName = interner.intern("get")

            // call: $delegate_x.getValue(thisRef, kProperty) -> PropertyType
            let resultExprID = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: propertyType
            )
            body.append(
                .call(
                    symbol: delegateStorageSymbol,
                    callee: getValueName,
                    arguments: [thisRefExprID, kPropertyExprID],
                    result: resultExprID,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            body.append(.returnValue(resultExprID))

        case .setter:
            returnType = sema.types.unitType
            accessorName = interner.intern("set")

            let valueParamSymbol = SymbolID(rawValue: -(propertySymbol.rawValue + 30_000))
            params.append(KIRParameter(symbol: valueParamSymbol, type: propertyType))

            // call: $delegate_x.setValue(thisRef, kProperty, value)
            let valueExprID = arena.appendExpr(.symbolRef(valueParamSymbol), type: propertyType)
            body.append(.constValue(result: valueExprID, value: .symbolRef(valueParamSymbol)))
            let resultExprID = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.unitType
            )
            body.append(
                .call(
                    symbol: delegateStorageSymbol,
                    callee: setValueName,
                    arguments: [thisRefExprID, kPropertyExprID, valueExprID],
                    result: resultExprID,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            body.append(.returnUnit)
        }
        body.append(.endBlock)

        let accessorSymbolOffset: Int32 = accessorKind == .getter ? -12_000 : -13_000
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
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
        driver.ctx.currentImplicitReceiverExprID = nil
        driver.ctx.currentImplicitReceiverSymbol = nil
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
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        var params: [KIRParameter] = []

        // Add receiver parameter if property has an owner class/object.
        if let ownerSymbol,
           let ownerSym = sema.symbols.symbol(ownerSymbol) {
            let ownerType = sema.types.make(
                .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
            )
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
            driver.ctx.currentImplicitReceiverSymbol = receiverSymbol
            driver.ctx.currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
        }

        let returnType: TypeID
        let accessorName: InternedString
        switch accessorKind {
        case .getter:
            returnType = propertyType
            accessorName = interner.intern("get")
            // Map the backing field symbol so `field` references in the getter
            // resolve to a backing field access expression.
            if let backingFieldSym = sema.symbols.backingFieldSymbol(for: propertySymbol) {
                let bfExprID = arena.appendExpr(.symbolRef(backingFieldSym), type: propertyType)
                driver.ctx.localValuesBySymbol[backingFieldSym] = bfExprID
            }
        case .setter:
            returnType = sema.types.unitType
            accessorName = interner.intern("set")
            let valueParamSymbol = SymbolID(rawValue: -(propertySymbol.rawValue + 30_000))
            params.append(KIRParameter(symbol: valueParamSymbol, type: propertyType))
            let valueExprID = arena.appendExpr(.symbolRef(valueParamSymbol), type: propertyType)
            driver.ctx.localValuesBySymbol[valueParamSymbol] = valueExprID
            // Sema binds the setter parameter name to a synthetic setter-value
            // symbol (offset -40_000) distinct from both the property symbol
            // and the backing field symbol.
            let semaSetterValueSymbol = SymbolID(rawValue: -(propertySymbol.rawValue + 40_000))
            driver.ctx.localValuesBySymbol[semaSetterValueSymbol] = valueExprID
            // Map the backing field symbol so `field` references in the setter
            // resolve to backing field storage, not the value parameter.
            if let backingFieldSym = sema.symbols.backingFieldSymbol(for: propertySymbol) {
                let bfExprID = arena.appendExpr(.symbolRef(backingFieldSym), type: propertyType)
                driver.ctx.localValuesBySymbol[backingFieldSym] = bfExprID
            }
        }

        var body: [KIRInstruction] = [.beginBlock]
        if let receiverExpr = driver.ctx.currentImplicitReceiverExprID,
           let receiverSym = driver.ctx.currentImplicitReceiverSymbol {
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
                        let lowered = driver.lowerExpr(
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
                lastValue = driver.lowerExpr(
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
            let value = driver.lowerExpr(
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
        // Offsets -12_000 / -13_000 avoid collision with receiver parameter symbols
        // which use -10_000 (see syntheticReceiverParameterSymbol).
        let accessorSymbolOffset: Int32 = accessorKind == .getter ? -12_000 : -13_000
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
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
        driver.ctx.currentImplicitReceiverExprID = nil
        driver.ctx.currentImplicitReceiverSymbol = nil
    }
}
