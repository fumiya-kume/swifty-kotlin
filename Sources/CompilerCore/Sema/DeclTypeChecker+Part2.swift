import Foundation

// Handles declaration-level type checking (functions, properties, classes, objects).
// Derived from TypeCheckSemaPhase.swift (second extension) and TypeCheckSemaPhase+DeclTypeCheck.swift.

extension DeclTypeChecker {
    func typeCheckBoundPropertyDecl(
        _ property: PropertyDecl,
        declID: DeclID,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        typeCheckPropertyDecl(
            property,
            symbol: symbol,
            ctx: ctx,
            solver: solver,
            diagnostics: diagnostics
        )
        let expr = ExprID(rawValue: declID.rawValue)
        sema.bindings.bindIdentifier(expr, symbol: symbol)
        let propertyType = sema.symbols.propertyType(for: symbol) ?? sema.types.nullableAnyType
        sema.bindings.bindExprType(expr, type: propertyType)
    }

    func typeCheckClassDecl(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        var allNestedObjects = classDecl.nestedObjects
        if let companionDeclID = classDecl.companionObject {
            allNestedObjects.append(companionDeclID)
        }
        let classType = sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
        let classScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: classType,
            memberFunctions: classDecl.memberFunctions,
            memberProperties: classDecl.memberProperties,
            nestedClasses: classDecl.nestedClasses,
            nestedObjects: allNestedObjects,
            ctx: ctx
        )
        let classLabel = sema.symbols.symbol(symbol)?.name ?? ctx.interner.intern("")
        let classCtx = ctx
            .withOuterReceiver(label: classLabel, type: classType)
            .copying(scope: classScope, implicitReceiverType: classType)

        typeCheckInitBlocks(classDecl.initBlocks, ctx: classCtx)
        typeCheckSecondaryConstructors(classDecl.secondaryConstructors, ctx: classCtx, ownerSymbol: symbol, hasPrimaryConstructor: classDecl.hasPrimaryConstructorSyntax)
        typeCheckClassDelegation(classDecl, symbol: symbol, ctx: classCtx, solver: solver, diagnostics: diagnostics)
        typeCheckClassLikeMembers(
            memberFunctions: classDecl.memberFunctions,
            memberProperties: classDecl.memberProperties,
            nestedClasses: classDecl.nestedClasses,
            nestedObjects: allNestedObjects,
            ctx: classCtx,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    func typeCheckClassDelegation(
        _ classDecl: ClassDecl,
        symbol _: SymbolID,
        ctx: TypeInferenceContext,
        solver _: ConstraintSolver,
        diagnostics _: DiagnosticEngine
    ) {
        let sema = ctx.sema
        let delegatedEntries = classDecl.superTypeEntries.filter { $0.delegateExpression != nil }
        guard !delegatedEntries.isEmpty else { return }

        var delegationCtx = ctx
        let ctorSymbols = sema.symbols.symbols(atDeclSite: classDecl.range)
            .compactMap { sema.symbols.symbol($0) }
            .filter { $0.kind == .constructor }

        if let ctorSymbol = ctorSymbols.first,
           let signature = sema.symbols.functionSignature(for: ctorSymbol.id)
        {
            let ctorScope = BaseScope(parent: ctx.scope, symbols: sema.symbols)
            for paramSym in signature.valueParameterSymbols {
                ctorScope.insert(paramSym)
            }
            delegationCtx = ctx.copying(scope: ctorScope)
        }

        for delegation in delegatedEntries {
            guard let expr = delegation.delegateExpression else { continue }
            var locals: LocalBindings = [:]
            _ = driver.inferExpr(
                expr,
                ctx: delegationCtx,
                locals: &locals,
                expectedType: nil
            )
        }
    }

    func typeCheckObjectDecl(
        _ objectDecl: ObjectDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        let objectType = sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
        let objectScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: objectType,
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: objectDecl.memberProperties,
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            ctx: ctx
        )
        let objectLabel = sema.symbols.symbol(symbol)?.name ?? ctx.interner.intern("")
        let objectCtx = ctx
            .withOuterReceiver(label: objectLabel, type: objectType)
            .copying(scope: objectScope, implicitReceiverType: objectType)

        typeCheckInitBlocks(objectDecl.initBlocks, ctx: objectCtx)
        typeCheckClassLikeMembers(
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: objectDecl.memberProperties,
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            ctx: objectCtx,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    func typeCheckInterfaceDecl(
        _ interfaceDecl: InterfaceDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        var allNestedObjects = interfaceDecl.nestedObjects
        if let companionDeclID = interfaceDecl.companionObject {
            allNestedObjects.append(companionDeclID)
        }
        let interfaceType = sema.types.make(.classType(ClassType(
            classSymbol: symbol, args: [], nullability: .nonNull
        )))
        let interfaceScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: interfaceType,
            memberFunctions: interfaceDecl.memberFunctions,
            memberProperties: interfaceDecl.memberProperties,
            nestedClasses: interfaceDecl.nestedClasses,
            nestedObjects: allNestedObjects,
            ctx: ctx
        )
        let label = sema.symbols.symbol(symbol)?.name ?? ctx.interner.intern("")
        let interfaceCtx = ctx
            .withOuterReceiver(label: label, type: interfaceType)
            .copying(scope: interfaceScope, implicitReceiverType: interfaceType)

        typeCheckClassLikeMembers(
            memberFunctions: interfaceDecl.memberFunctions,
            memberProperties: interfaceDecl.memberProperties,
            nestedClasses: interfaceDecl.nestedClasses,
            nestedObjects: allNestedObjects,
            ctx: interfaceCtx,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    func typeCheckClassLikeMembers(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let ast = ctx.ast
        let sema = ctx.sema

        for declID in memberFunctions {
            guard let decl = ast.arena.decl(declID),
                  case let .funDecl(function) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            typeCheckFunctionDecl(
                function,
                symbol: symbol,
                ctx: ctx,
                solver: solver,
                diagnostics: diagnostics
            )
        }

        for declID in memberProperties {
            guard let decl = ast.arena.decl(declID),
                  case let .propertyDecl(property) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            typeCheckBoundPropertyDecl(
                property,
                declID: declID,
                symbol: symbol,
                ctx: ctx,
                solver: solver,
                diagnostics: diagnostics
            )
        }

        for declID in nestedClasses {
            guard let decl = ast.arena.decl(declID),
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            switch decl {
            case let .classDecl(classDecl):
                // Inner classes inherit outer receiver context (can use this@Outer).
                // Non-inner nested classes are effectively static: clear outer receivers.
                let nestedCtx: TypeInferenceContext = if classDecl.isInner {
                    ctx
                } else {
                    ctx.copying(outerReceiverTypes: [])
                }
                typeCheckClassDecl(
                    classDecl,
                    symbol: symbol,
                    ctx: nestedCtx,
                    solver: solver,
                    diagnostics: diagnostics
                )
            case let .interfaceDecl(nestedInterface):
                let nestedCtx = ctx.copying(outerReceiverTypes: [])
                typeCheckInterfaceDecl(
                    nestedInterface,
                    symbol: symbol,
                    ctx: nestedCtx,
                    solver: solver,
                    diagnostics: diagnostics
                )
            default:
                continue
            }
        }

        for declID in nestedObjects {
            guard let decl = ast.arena.decl(declID),
                  case let .objectDecl(objectDecl) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            typeCheckObjectDecl(
                objectDecl,
                symbol: symbol,
                ctx: ctx,
                solver: solver,
                diagnostics: diagnostics
            )
        }
    }

    // MARK: - Class Member Scope Building

    func buildClassMemberScope(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ctx: TypeInferenceContext
    ) -> ClassMemberScope {
        let sema = ctx.sema
        let classScope = ClassMemberScope(
            parent: ctx.scope,
            symbols: sema.symbols,
            ownerSymbol: ownerSymbol,
            thisType: ownerType
        )

        for declID in memberFunctions + memberProperties + nestedClasses + nestedObjects {
            if let symbol = sema.bindings.declSymbols[declID] {
                classScope.insert(symbol)
            }
        }

        // Make companion properties available as unqualified names inside the
        // owning class/interface scope (e.g. `MAX_COUNT` instead of
        // `Companion.MAX_COUNT`).
        if let companionSymbol = sema.symbols.companionObjectSymbol(for: ownerSymbol),
           let companion = sema.symbols.symbol(companionSymbol)
        {
            for memberSymbol in sema.symbols.children(ofFQName: companion.fqName) {
                guard let member = sema.symbols.symbol(memberSymbol),
                      member.kind == .property || member.kind == .field
                else {
                    continue
                }
                classScope.insert(memberSymbol)
            }
        }

        return classScope
    }
}
