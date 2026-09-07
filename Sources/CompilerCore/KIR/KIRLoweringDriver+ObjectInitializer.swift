
extension KIRLoweringDriver {
    /// Synthesise an initializer function for a top-level `object` declaration.
    ///
    /// The generated function emits property initializers and init blocks in
    /// declaration order using `classBodyInitOrder`, matching Kotlin's
    /// guaranteed top-to-bottom initialization semantics.  The function is
    /// registered via `registerCompanionInitializer` so that it is called once
    /// during module initialization (injected into `main`).
    ///
    /// When the object participates in runtime dispatch, this also allocates a
    /// heap object via `kk_object_new`, stores it in the object's global slot,
    /// and registers vtable/itable methods for virtual dispatch.
    func synthesizeObjectInitializer(
        _ objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema

        // Determine whether this object implements any interfaces or has vtable entries.
        let interfaceSupertypes = kirTransitiveInterfaceSupertypes(of: objectSymbol, sema: sema)
        let needsDispatchObject = !interfaceSupertypes.isEmpty
            || !kirVtableImplementations(for: objectSymbol, sema: sema).isEmpty

        guard !objectDecl.memberProperties.isEmpty || !objectDecl.initBlocks.isEmpty || needsDispatchObject else {
            return []
        }

        let arena = shared.arena
        let interner = shared.interner

        let initializerSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let initializerName = interner.intern("__object_init_\(objectSymbol.rawValue)")

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()

        let objectType = sema.types.make(.classType(ClassType(
            classSymbol: objectSymbol, args: [], nullability: .nonNull
        )))
        let objectReceiverExpr = arena.appendExpr(.symbolRef(objectSymbol), type: objectType)
        ctx.setImplicitReceiver(symbol: objectSymbol, exprID: objectReceiverExpr)

        var body: KIRLoweringEmitContext = [.beginBlock]

        // When the object participates in virtual dispatch, allocate a heap object
        // and store it in the global slot so lookup can find the registered methods.
        if needsDispatchObject {
            let intType = sema.types.intType
            let layout = sema.symbols.nominalLayout(for: objectSymbol)
            let slotCount = Int64(max(layout?.instanceSizeWords ?? 1, 1))
            let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
            body.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
            let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: objectSymbol, sema: sema, interner: interner
            )
            let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
            body.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
            let allocatedObj = arena.appendTemporary(type: objectType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_object_new"),
                arguments: [slotCountExpr, classIDExpr],
                result: allocatedObj,
                canThrow: false,
                thrownResult: nil
            ))

            // Store the allocated object pointer in the global slot.
            body.append(.storeGlobal(value: allocatedObj, symbol: objectSymbol))

            var typeEdgeInstructions: [KIRInstruction] = []
            appendNominalSupertypeEdgeRegistrations(
                childSymbol: objectSymbol,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &typeEdgeInstructions
            )
            body.append(contentsOf: typeEdgeInstructions)

            // Register itable methods for each interface.
            if let objectLayout = sema.symbols.nominalLayout(for: objectSymbol) {
                for interfaceSymbol in interfaceSupertypes {
                    guard let interfaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol) else { continue }
                    let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)
                    let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                        symbol: interfaceSymbol,
                        sema: sema,
                        interner: interner
                    )
                    let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: intType)
                    body.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))
                    let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
                    body.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))
                    let registerIfaceResult = arena.appendTemporary(type: intType)
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_object_register_itable_iface"),
                        arguments: [allocatedObj, interfaceTypeExpr, ifaceSlotExpr],
                        result: registerIfaceResult,
                        canThrow: false,
                        thrownResult: nil
                    ))

                    // Walk the interface methods to find each method that needs registration.
                    for (methodSymbol, methodSlotInt) in kirItableMethodEntries(
                        for: interfaceSymbol,
                        interfaceLayout: interfaceLayout,
                        sema: sema,
                        interner: interner
                    ) {
                        let methodSlot = Int64(methodSlotInt)
                        // Find the override in the object's member functions.
                        let implementationSymbol = kirFindOverrideMethod(
                            for: methodSymbol,
                            in: objectSymbol,
                            sema: sema,
                            interner: interner
                        ) ?? methodSymbol
                        let bridgeSymbol = itableBridgeSymbolForMethod(
                            interfaceMethod: methodSymbol,
                            implementation: implementationSymbol,
                            nominalSymbol: objectSymbol,
                            driver: self,
                            arena: arena,
                            sema: sema,
                            interner: interner
                        )
                        let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
                        body.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))
                        let methodFnExpr = arena.appendExpr(.symbolRef(bridgeSymbol), type: intType)
                        body.append(.constValue(result: methodFnExpr, value: .symbolRef(bridgeSymbol)))
                        let registerMethodResult = arena.appendTemporary(type: intType)
                        body.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_object_register_itable_method"),
                            arguments: [allocatedObj, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                            result: registerMethodResult,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }
                }
                // BUG-141: register interface property getters into the itable.
                appendObjectItablePropertyGetterRegistrations(
                    objectValue: allocatedObj,
                    nominalSymbol: objectSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &body.instructions
                )
            }
            appendObjectVtableMethodRegistrations(
                objectValue: allocatedObj,
                nominalSymbol: objectSymbol,
                driver: self,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body.instructions
            )
        } else {
            body.append(.constValue(result: objectReceiverExpr, value: .symbolRef(objectSymbol)))
        }

        emitObjectBodyInitializers(objectDecl, shared: shared, body: &body)

        body.append(.returnUnit)
        body.append(.endBlock)

        let initDeclID = arena.appendDecl(
            .function(KIRFunction(
                symbol: initializerSymbol, name: initializerName,
                params: [], returnType: sema.types.unitType,
                body: body, isSuspend: false, isInline: false,
                sourceRange: objectDecl.range
            ))
        )
        ctx.registerCompanionInitializer(symbol: initializerSymbol, name: initializerName)

        var declIDs: [KIRDeclID] = [initDeclID]
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        ctx.clearImplicitReceiver()
        return declIDs
    }

    private func emitObjectBodyInitializers(
        _ objectDecl: ObjectDecl,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena

        for member in objectDecl.classBodyInitOrder {
            switch member {
            case let .property(index):
                guard index < objectDecl.memberProperties.count else { continue }
                let propertyDeclID = objectDecl.memberProperties[index]
                guard let propertyDecl = ast.arena.decl(propertyDeclID),
                      case let .propertyDecl(property) = propertyDecl,
                      let propertySymbol = sema.bindings.declSymbols[propertyDeclID]
                else { continue }
                if property.delegateExpression != nil { continue }
                guard let initializer = property.initializer else { continue }
                let initializerValue = lowerExpr(initializer, shared: shared, emit: &body)
                let targetSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
                let propertyType = sema.symbols.propertyType(for: targetSymbol) ?? sema.types.anyType
                let targetRef = arena.appendExpr(.symbolRef(targetSymbol), type: propertyType)
                body.append(.constValue(result: targetRef, value: .symbolRef(targetSymbol)))
                body.append(.copy(from: initializerValue, to: targetRef))
            case let .initBlock(index):
                guard index < objectDecl.initBlocks.count else { continue }
                let initBlock = objectDecl.initBlocks[index]
                switch initBlock {
                case let .block(exprIDs, _):
                    for exprID in exprIDs {
                        _ = lowerExpr(exprID, shared: shared, emit: &body)
                    }
                case let .expr(exprID, _):
                    _ = lowerExpr(exprID, shared: shared, emit: &body)
                case .unit:
                    break
                }
            }
        }
    }
}
