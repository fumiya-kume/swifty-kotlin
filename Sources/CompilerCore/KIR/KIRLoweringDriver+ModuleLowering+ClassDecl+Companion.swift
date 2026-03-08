import Foundation

extension KIRLoweringDriver {
    func synthesizeCompanionInitializerIfNeeded(
        companionDeclID: DeclID?,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        guard let companionDeclID,
              let decl = shared.ast.arena.decl(companionDeclID),
              case let .objectDecl(companionDecl) = decl,
              let companionSymbol = shared.sema.bindings.declSymbols[companionDeclID]
        else {
            return []
        }

        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        let initializerSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let initializerName = interner.intern("__companion_init_\(ownerSymbol.rawValue)_\(companionSymbol.rawValue)")

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()

        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let companionReceiverExpr = arena.appendExpr(.symbolRef(companionSymbol), type: companionType)
        ctx.currentImplicitReceiverSymbol = companionSymbol
        ctx.currentImplicitReceiverExprID = companionReceiverExpr

        var body: KIRLoweringEmitContext = [.beginBlock]
        body.append(.constValue(result: companionReceiverExpr, value: .symbolRef(companionSymbol)))

        // Property initializers run before init blocks, in declaration order.
        for propertyDeclID in companionDecl.memberProperties {
            guard let propertyDecl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(property) = propertyDecl,
                  let propertySymbol = sema.bindings.declSymbols[propertyDeclID]
            else {
                continue
            }
            // Delegate-specific initialization is handled separately.
            if property.delegateExpression != nil {
                continue
            }
            guard let initializer = property.initializer else {
                continue
            }
            let initializerValue = lowerExpr(
                initializer,
                shared: shared,
                emit: &body
            )
            let targetSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            let propertyType = sema.symbols.propertyType(for: targetSymbol) ?? sema.types.anyType
            let targetRef = arena.appendExpr(.symbolRef(targetSymbol), type: propertyType)
            body.append(.constValue(result: targetRef, value: .symbolRef(targetSymbol)))
            body.append(.copy(from: initializerValue, to: targetRef))
        }

        for initBlock in companionDecl.initBlocks {
            switch initBlock {
            case let .block(exprIDs, _):
                for exprID in exprIDs {
                    _ = lowerExpr(
                        exprID,
                        shared: shared,
                        emit: &body
                    )
                }
            case let .expr(exprID, _):
                _ = lowerExpr(
                    exprID,
                    shared: shared,
                    emit: &body
                )
            case .unit:
                break
            }
        }

        body.append(.returnUnit)
        body.append(.endBlock)

        let initDeclID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: initializerSymbol,
                    name: initializerName,
                    params: [],
                    returnType: sema.types.unitType,
                    body: body,
                    isSuspend: false,
                    isInline: false,
                    sourceRange: companionDecl.range
                )
            )
        )
        ctx.registerCompanionInitializer(symbol: initializerSymbol, name: initializerName)

        var declIDs: [KIRDeclID] = [initDeclID]
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        ctx.currentImplicitReceiverExprID = nil
        ctx.currentImplicitReceiverSymbol = nil
        return declIDs
    }
}
