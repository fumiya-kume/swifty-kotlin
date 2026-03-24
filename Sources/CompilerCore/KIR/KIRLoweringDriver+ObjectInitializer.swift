import Foundation

extension KIRLoweringDriver {
    /// Synthesise an initializer function for a top-level `object` declaration.
    ///
    /// The generated function emits property initializers and init blocks in
    /// declaration order using `classBodyInitOrder`, matching Kotlin's
    /// guaranteed top-to-bottom initialization semantics.  The function is
    /// registered via `registerCompanionInitializer` so that it is called once
    /// during module initialization (injected into `main`).
    ///
    /// When the object implements interfaces, this also allocates a heap object
    /// via `kk_object_new`, stores it in the object's global slot, and registers
    /// itable methods so that interface-typed virtual dispatch works at runtime.
    func synthesizeObjectInitializer(
        _ objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema

        // Determine whether this object implements any interfaces.
        let interfaceSupertypes = sema.symbols.directSupertypes(for: objectSymbol).filter { superSym in
            sema.symbols.symbol(superSym)?.kind == .interface
        }

        guard !objectDecl.memberProperties.isEmpty || !objectDecl.initBlocks.isEmpty || !interfaceSupertypes.isEmpty else {
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

        // When the object implements interfaces, allocate a heap object and
        // store it in the global slot so that interface-typed virtual dispatch
        // can look up the itable at runtime.
        if !interfaceSupertypes.isEmpty {
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
            let allocatedObj = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: objectType)
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

            // Register supertype relationships (interfaces).
            let childTypeExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
            body.append(.constValue(result: childTypeExpr, value: .intLiteral(classIDValue)))
            for superSymbol in sema.symbols.directSupertypes(for: objectSymbol) {
                let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: superSymbol, sema: sema, interner: interner
                )
                let parentExpr = arena.appendExpr(.intLiteral(parentTypeID), type: intType)
                body.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
                let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                let superKind = sema.symbols.symbol(superSymbol)?.kind
                let registerCallee: InternedString = if superKind == .interface {
                    interner.intern("kk_type_register_iface")
                } else {
                    interner.intern("kk_type_register_super")
                }
                body.append(.call(
                    symbol: nil,
                    callee: registerCallee,
                    arguments: [childTypeExpr, parentExpr],
                    result: registerResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }

            // Register itable methods for each interface.
            if let objectLayout = sema.symbols.nominalLayout(for: objectSymbol) {
                for interfaceSymbol in interfaceSupertypes {
                    guard let interfaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol) else { continue }
                    let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)

                    // Walk the interface's vtableSlots to find each method that needs registration.
                    for (methodSymbol, methodSlotInt) in interfaceLayout.vtableSlots {
                        let methodSlot = Int64(methodSlotInt)
                        // Find the override in the object's member functions.
                        let implementationSymbol = findOverrideMethod(
                            for: methodSymbol,
                            in: objectSymbol,
                            sema: sema,
                            interner: interner
                        ) ?? methodSymbol

                        let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
                        body.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))
                        let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
                        body.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))
                        let methodFnExpr = arena.appendExpr(.symbolRef(implementationSymbol), type: intType)
                        body.append(.constValue(result: methodFnExpr, value: .symbolRef(implementationSymbol)))
                        let registerMethodResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
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
            }
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

    /// Find an override method in the given nominal type for a method declared
    /// in an interface.
    private func findOverrideMethod(
        for interfaceMethod: SymbolID,
        in nominalSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        guard let methodSym = sema.symbols.symbol(interfaceMethod) else { return nil }
        let methodName = methodSym.name
        guard let ownerSym = sema.symbols.symbol(nominalSymbol) else { return nil }
        let overrideFQName = ownerSym.fqName + [methodName]
        for candidate in sema.symbols.lookupAll(fqName: overrideFQName) {
            guard let candidateSym = sema.symbols.symbol(candidate),
                  candidateSym.kind == .function,
                  sema.symbols.parentSymbol(for: candidate) == nominalSymbol
            else { continue }
            return candidate
        }
        return nil
    }

    // MARK: - Helpers

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
