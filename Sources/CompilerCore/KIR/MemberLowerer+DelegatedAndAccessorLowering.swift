import Foundation

extension MemberLowerer {
    func lowerMemberDecls(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        shared: KIRLoweringSharedContext
    ) -> (directMembers: [KIRDeclID], allDecls: [KIRDeclID]) {
        lowerMemberDecls(
            memberFunctions: memberFunctions,
            memberProperties: memberProperties,
            nestedClasses: nestedClasses,
            nestedObjects: nestedObjects,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers
        )
    }

    func lowerDelegateAccessor(
        propertySymbol: SymbolID,
        propertyType: TypeID,
        delegateStorageSymbol: SymbolID,
        delegateKind: StdlibDelegateKind,
        accessorKind: PropertyAccessorKind,
        shared: KIRLoweringSharedContext,
        allDecls: inout [KIRDeclID]
    ) {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        var params: [KIRParameter] = []

        // Add receiver parameter if property has an owner class/object.
        if let ownerSymbol,
           let ownerSym = sema.symbols.symbol(ownerSymbol)
        {
            let ownerType = sema.types.make(
                .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
            )
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
            driver.ctx.setImplicitReceiver(
                symbol: receiverSymbol,
                exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
            )
        }

        let returnType: TypeID
        let accessorName: InternedString
        let customGetValueSymbol = sema.symbols.delegateGetValueSymbol(for: propertySymbol)
        let customSetValueSymbol = sema.symbols.delegateSetValueSymbol(for: propertySymbol)
        let getValueName: InternedString = switch delegateKind {
        case .lazy:
            interner.intern("kk_lazy_get_value")
        case .observable:
            interner.intern("kk_observable_get_value")
        case .vetoable:
            interner.intern("kk_vetoable_get_value")
        case .custom:
            interner.intern("getValue")
        }
        let setValueName: InternedString = switch delegateKind {
        case .lazy:
            interner.intern("setValue")
        case .observable:
            interner.intern("kk_observable_set_value")
        case .vetoable:
            interner.intern("kk_vetoable_set_value")
        case .custom:
            interner.intern("setValue")
        }

        var body: KIRLoweringEmitContext = [.beginBlock]
        if let receiverBinding = driver.ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
        }

        switch accessorKind {
        case .getter:
            returnType = propertyType
            accessorName = interner.intern("get")

            let delegateHandleExprID = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.anyType
            )
            body.append(.loadGlobal(result: delegateHandleExprID, symbol: delegateStorageSymbol))
            // call: $delegate_x.getValue(thisRef, kProperty) -> PropertyType
            let resultExprID = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: propertyType
            )
            body.append(
                .call(
                    symbol: delegateKind == .custom ? customGetValueSymbol : delegateStorageSymbol,
                    callee: getValueName,
                    arguments: delegateKind == .custom ? [delegateHandleExprID] + buildCustomDelegateGetterArgs(
                        propertySymbol: propertySymbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        body: &body
                    ) : [],
                    result: resultExprID,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            body.append(.returnValue(resultExprID))

        case .setter:
            returnType = sema.types.unitType
            accessorName = interner.intern("set")

            let valueParamSymbol = SyntheticSymbolScheme.setterValueParameterSymbol(for: propertySymbol)
            params.append(KIRParameter(symbol: valueParamSymbol, type: propertyType))

            // call: $delegate_x.setValue(thisRef, kProperty, value)
            let valueExprID = arena.appendExpr(.symbolRef(valueParamSymbol), type: propertyType)
            body.append(.constValue(result: valueExprID, value: .symbolRef(valueParamSymbol)))
            let delegateHandleExprID = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.anyType
            )
            body.append(.loadGlobal(result: delegateHandleExprID, symbol: delegateStorageSymbol))
            let resultExprID = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.unitType
            )
            body.append(
                .call(
                    symbol: delegateKind == .custom ? customSetValueSymbol : delegateStorageSymbol,
                    callee: setValueName,
                    arguments: delegateKind == .custom ? [delegateHandleExprID] + buildCustomDelegateSetterArgs(
                        propertySymbol: propertySymbol,
                        valueExprID: valueExprID,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        body: &body
                    ) : [valueExprID],
                    result: resultExprID,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            body.append(.returnUnit)
        }
        body.append(.endBlock)

        let syntheticAccessorSymbol = SyntheticSymbolScheme.propertyAccessorSymbol(
            for: propertySymbol,
            kind: accessorKind
        )

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
        driver.ctx.clearImplicitReceiver()
    }

    private func buildCustomDelegateGetterArgs(
        propertySymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        let thisRefExprID: KIRExprID
        if let receiver = driver.ctx.activeImplicitReceiverExprID() {
            thisRefExprID = receiver
        } else {
            thisRefExprID = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            body.append(.constValue(result: thisRefExprID, value: .null))
        }
        let kPropertyExprID = buildKPropertyStub(
            propertySymbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        )
        return [thisRefExprID, kPropertyExprID]
    }

    private func buildCustomDelegateSetterArgs(
        propertySymbol: SymbolID,
        valueExprID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        buildCustomDelegateGetterArgs(
            propertySymbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        ) + [valueExprID]
    }

    private func buildKPropertyStub(
        propertySymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let propertyName = sema.symbols.symbol(propertySymbol)?.name ?? interner.intern("")
        let propertyNameExprID = arena.appendExpr(
            .stringLiteral(propertyName),
            type: sema.types.make(.primitive(.string, .nonNull))
        )
        body.append(.constValue(result: propertyNameExprID, value: .stringLiteral(propertyName)))
        let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
        let returnTypeSig = interner.intern(sema.types.renderType(propertyType))
        let returnTypeExprID = arena.appendExpr(
            .stringLiteral(returnTypeSig),
            type: sema.types.make(.primitive(.string, .nonNull))
        )
        body.append(.constValue(result: returnTypeExprID, value: .stringLiteral(returnTypeSig)))
        let kPropertyExprID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        body.append(
            .call(
                symbol: nil,
                callee: interner.intern("kk_kproperty_stub_create"),
                arguments: [propertyNameExprID, returnTypeExprID],
                result: kPropertyExprID,
                canThrow: false,
                thrownResult: nil
            )
        )
        return kPropertyExprID
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
        setterParamName _: InternedString?,
        shared: KIRLoweringSharedContext,
        allDecls: inout [KIRDeclID]
    ) {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        let extensionReceiverType = sema.symbols.extensionPropertyReceiverType(for: propertySymbol)
        var params: [KIRParameter] = []

        // Add receiver parameter for extension properties or member properties.
        if let receiverType = extensionReceiverType {
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
            driver.ctx.setImplicitReceiver(
                symbol: receiverSymbol,
                exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
            )
        } else if let ownerSymbol,
                  let ownerSym = sema.symbols.symbol(ownerSymbol)
        {
            let ownerType = sema.types.make(
                .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
            )
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
            driver.ctx.setImplicitReceiver(
                symbol: receiverSymbol,
                exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
            )
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
                driver.ctx.setLocalValue(bfExprID, for: backingFieldSym)
            }
        case .setter:
            returnType = sema.types.unitType
            accessorName = interner.intern("set")
            let valueParamSymbol = SyntheticSymbolScheme.setterValueParameterSymbol(for: propertySymbol)
            params.append(KIRParameter(symbol: valueParamSymbol, type: propertyType))
            let valueExprID = arena.appendExpr(.symbolRef(valueParamSymbol), type: propertyType)
            driver.ctx.setLocalValue(valueExprID, for: valueParamSymbol)
            // Sema binds the setter parameter name to a synthetic setter-value
            // symbol (offset -40_000) distinct from both the property symbol
            // and the backing field symbol.
            let semaSetterValueSymbol = SyntheticSymbolScheme.semaSetterValueSymbol(for: propertySymbol)
            driver.ctx.setLocalValue(valueExprID, for: semaSetterValueSymbol)
            // Map the backing field symbol so `field` references in the setter
            // resolve to backing field storage, not the value parameter.
            if let backingFieldSym = sema.symbols.backingFieldSymbol(for: propertySymbol) {
                let bfExprID = arena.appendExpr(.symbolRef(backingFieldSym), type: propertyType)
                driver.ctx.setLocalValue(bfExprID, for: backingFieldSym)
            }
        }

        var body: KIRLoweringEmitContext = [.beginBlock]
        if let receiverBinding = driver.ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
        }

        switch accessorBody {
        case let .block(exprIDs, _):
            var lastValue: KIRExprID?
            var terminatedByReturn = false
            for exprID in exprIDs {
                if let expr = ast.arena.expr(exprID),
                   case let .returnExpr(value, _, _) = expr
                {
                    if let value {
                        let lowered = driver.lowerExpr(
                            value,
                            shared: shared,
                            emit: &body
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
                    shared: shared,
                    emit: &body
                )
            }
            if !terminatedByReturn {
                if accessorKind == .getter, let lastValue {
                    body.append(.returnValue(lastValue))
                } else {
                    body.append(.returnUnit)
                }
            }
        case let .expr(exprID, _):
            let value = driver.lowerExpr(
                exprID,
                shared: shared,
                emit: &body
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
        // Offsets are centralized in SyntheticSymbolScheme.
        let syntheticAccessorSymbol: SymbolID = switch accessorKind {
        case .getter:
            sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        case .setter:
            sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
        }

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
        driver.ctx.clearImplicitReceiver()
    }
}
