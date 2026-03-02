import Foundation

extension KIRLoweringDriver {
    /// Synthesise an initializer function for a top-level `object` declaration.
    ///
    /// The generated function runs property initializers first (in declaration order),
    /// then init blocks -- matching Kotlin's guaranteed initialization order for object
    /// singletons.  The function is registered via `registerCompanionInitializer` so
    /// that it is called once during module initialization (injected into `main`).
    func synthesizeObjectInitializer(
        _ objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        guard !objectDecl.memberProperties.isEmpty || !objectDecl.initBlocks.isEmpty else {
            return []
        }

        let sema = shared.sema
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
        ctx.currentImplicitReceiverSymbol = objectSymbol
        ctx.currentImplicitReceiverExprID = objectReceiverExpr

        var body: KIRLoweringEmitContext = [.beginBlock]
        body.append(.constValue(result: objectReceiverExpr, value: .symbolRef(objectSymbol)))

        emitObjectPropertyInitializers(objectDecl, shared: shared, body: &body)
        emitObjectInitBlocks(objectDecl, shared: shared, body: &body)

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
        ctx.currentImplicitReceiverExprID = nil
        ctx.currentImplicitReceiverSymbol = nil
        return declIDs
    }

    // MARK: - Helpers

    private func emitObjectPropertyInitializers(
        _ objectDecl: ObjectDecl,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena

        for propertyDeclID in objectDecl.memberProperties {
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
        }
    }

    private func emitObjectInitBlocks(
        _ objectDecl: ObjectDecl,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        for initBlock in objectDecl.initBlocks {
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
