import Foundation

/// Handles declaration-level type checking (functions, properties, classes, objects).
/// Derived from TypeCheckSemaPass.swift (second extension) and TypeCheckSemaPass+DeclTypeCheck.swift.
final class DeclTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    // MARK: - Function Body Type Inference (from +DeclTypeCheck.swift)

    func inferFunctionBodyType(
        _ body: FunctionBody,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        switch body {
        case .unit:
            return ctx.sema.types.unitType

        case .expr(let exprID, _):
            return driver.inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .block(let exprIDs, _):
            var last = ctx.sema.types.unitType
            for (index, exprID) in exprIDs.enumerated() {
                let expectedTypeForExpr = index == exprIDs.count - 1 ? expectedType : nil
                last = driver.inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: expectedTypeForExpr)
            }
            return last
        }
    }

    // MARK: - Property Type Checking (from +DeclTypeCheck.swift)

    func typeCheckPropertyDecl(
        _ property: PropertyDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        let interner = ctx.interner
        var inferredPropertyType: TypeID? = property.type != nil ? sema.symbols.propertyType(for: symbol) : nil

        if let initializer = property.initializer {
            var locals: LocalBindings = [:]
            let initializerType = driver.inferExpr(
                initializer, ctx: ctx, locals: &locals,
                expectedType: inferredPropertyType
            )
            if let declaredType = inferredPropertyType {
                driver.emitSubtypeConstraint(
                    left: initializerType, right: declaredType,
                    range: property.range, solver: solver,
                    sema: sema, diagnostics: diagnostics
                )
            } else {
                inferredPropertyType = initializerType
            }
        }

        if let getter = property.getter {
            var getterLocals: LocalBindings = [:]
            if let fieldType = inferredPropertyType {
                let fieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                getterLocals[interner.intern("field")] = (fieldType, fieldSymbol, true, true)
            }
            let getterType = inferFunctionBodyType(
                getter.body, ctx: ctx, locals: &getterLocals,
                expectedType: inferredPropertyType
            )
            if let declaredType = inferredPropertyType {
                driver.emitSubtypeConstraint(
                    left: getterType, right: declaredType,
                    range: getter.range, solver: solver,
                    sema: sema, diagnostics: diagnostics
                )
            } else {
                inferredPropertyType = getterType
            }
        }

        if let delegateExpr = property.delegateExpression {
            var delegateLocals: LocalBindings = [:]
            let delegateType = driver.inferExpr(
                delegateExpr, ctx: ctx, locals: &delegateLocals,
                expectedType: nil
            )

            // Resolve getValue operator on the delegate type to infer the
            // property type from its return type (Kotlin spec J12).
            let getValueName = interner.intern("getValue")
            let getValueCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: getValueName,
                receiverType: delegateType,
                sema: sema
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID) else { return false }
                return sym.flags.contains(.operatorFunction)
            }
            if let getValueSymbol = getValueCandidates.first,
               let getValueSig = sema.symbols.functionSignature(for: getValueSymbol) {
                // Use getValue return type to infer the property type when
                // no explicit type annotation is provided.
                if inferredPropertyType == nil {
                    inferredPropertyType = getValueSig.returnType
                }
            }

            // For var properties, also check that setValue operator exists.
            if property.isVar {
                let setValueName = interner.intern("setValue")
                let setValueCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: setValueName,
                    receiverType: delegateType,
                    sema: sema
                ).filter { candidateID in
                    guard let sym = sema.symbols.symbol(candidateID) else { return false }
                    return sym.flags.contains(.operatorFunction)
                }
                _ = setValueCandidates  // Validate existence; diagnostic emitted elsewhere if needed.
            }

            // Check for provideDelegate operator on the delegate type.
            let provideDelegateName = interner.intern("provideDelegate")
            let provideDelegateCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: provideDelegateName,
                receiverType: delegateType,
                sema: sema
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID) else { return false }
                return sym.flags.contains(.operatorFunction)
            }
            _ = provideDelegateCandidates  // Track for KIR lowering provideDelegate insertion.
        }

        let finalPropertyType = inferredPropertyType ?? sema.types.nullableAnyType
        sema.symbols.setPropertyType(finalPropertyType, for: symbol)

        if let setter = property.setter {
            if !property.isVar {
                diagnostics.error(
                    "KSWIFTK-SEMA-0005",
                    "Setter is not allowed for read-only property.",
                    range: setter.range
                )
            }
            var setterLocals: LocalBindings = [:]
            let fieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
            setterLocals[interner.intern("field")] = (finalPropertyType, fieldSymbol, true, true)
            let parameterName = setter.parameterName ?? interner.intern("value")
            let setterValueSymbol = SymbolID(rawValue: -(symbol.rawValue + 40_000))
            setterLocals[parameterName] = (finalPropertyType, setterValueSymbol, true, true)
            let setterType = inferFunctionBodyType(
                setter.body, ctx: ctx, locals: &setterLocals,
                expectedType: sema.types.unitType
            )
            driver.emitSubtypeConstraint(
                left: setterType, right: sema.types.unitType,
                range: setter.range, solver: solver,
                sema: sema, diagnostics: diagnostics
            )
        }
    }

    // MARK: - Init Block & Secondary Constructor Type Checking (from +DeclTypeCheck.swift)

    func typeCheckInitBlocks(
        _ blocks: [FunctionBody],
        ctx: TypeInferenceContext
    ) {
        for block in blocks {
            var locals: LocalBindings = [:]
            _ = inferFunctionBodyType(block, ctx: ctx, locals: &locals, expectedType: nil)
        }
    }

    func typeCheckSecondaryConstructors(
        _ constructors: [ConstructorDecl],
        ctx: TypeInferenceContext,
        ownerSymbol: SymbolID? = nil,
        hasPrimaryConstructor: Bool = true
    ) {
        let sema = ctx.sema
        for ctor in constructors {
            var locals: LocalBindings = [:]
            let ctorSymbols = sema.symbols.symbols(atDeclSite: ctor.range).compactMap { sema.symbols.symbol($0) }.filter { $0.kind == .constructor }
            let currentCtorSymbolID = ctorSymbols.first?.id
            if let ctorSymbol = ctorSymbols.first,
               let signature = sema.symbols.functionSignature(for: ctorSymbol.id) {
                for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
                    guard let param = sema.symbols.symbol(paramSymbol) else { continue }
                    let type = index < signature.parameterTypes.count ? signature.parameterTypes[index] : sema.types.anyType
                    locals[param.name] = (type, paramSymbol, false, true)
                }
            }

            if ctor.delegationCall == nil && hasPrimaryConstructor {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0054",
                    "Secondary constructor must delegate to another constructor via this() or super().",
                    range: ctor.range
                )
            }

            if let delegation = ctor.delegationCall {
                var argTypes: [CallArg] = []
                for arg in delegation.args {
                    let argType = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: nil)
                    argTypes.append(CallArg(label: arg.label, isSpread: arg.isSpread, type: argType))
                }

                let delegationTargetFQName: [InternedString]
                switch delegation.kind {
                case .this:
                    if let owner = ownerSymbol,
                       let ownerSym = sema.symbols.symbol(owner) {
                        delegationTargetFQName = ownerSym.fqName + [ctx.interner.intern("<init>")]
                    } else {
                        delegationTargetFQName = []
                    }
                case .super_:
                    if let owner = ownerSymbol {
                        let supertypes = sema.symbols.directSupertypes(for: owner)
                        let classSupertypes = supertypes.filter {
                            let kind = sema.symbols.symbol($0)?.kind
                            return kind == .class || kind == .enumClass
                        }
                        if let superclass = classSupertypes.first,
                           let superSym = sema.symbols.symbol(superclass) {
                            delegationTargetFQName = superSym.fqName + [ctx.interner.intern("<init>")]
                        } else {
                            delegationTargetFQName = []
                        }
                    } else {
                        delegationTargetFQName = []
                    }
                }

                if !delegationTargetFQName.isEmpty {
                    let candidates = sema.symbols.lookupAll(fqName: delegationTargetFQName)
                        .filter { candidate in
                            guard let symbol = sema.symbols.symbol(candidate) else { return false }
                            return symbol.kind == .constructor && candidate != currentCtorSymbolID
                        }

                    if candidates.isEmpty {
                        let targetKind = delegation.kind == .this ? "this" : "super"
                        sema.diagnostics.error(
                            "KSWIFTK-SEMA-0055",
                            "Unresolved \(targetKind)() delegation target: no matching constructor found.",
                            range: delegation.range
                        )
                    } else {
                        let callExpr = CallExpr(
                            range: delegation.range,
                            calleeName: ctx.interner.intern("<init>"),
                            args: argTypes
                        )
                        let resolved = ctx.resolver.resolveCall(
                            candidates: candidates,
                            call: callExpr,
                            expectedType: nil,
                            ctx: sema
                        )
                        if let diagnostic = resolved.diagnostic {
                            sema.diagnostics.emit(diagnostic)
                        }
                    }
                } else if ownerSymbol != nil {
                    let targetKind = delegation.kind == .this ? "this" : "super"
                    sema.diagnostics.error(
                        "KSWIFTK-SEMA-0055",
                        "Unresolved \(targetKind)() delegation target: no matching constructor found.",
                        range: delegation.range
                    )
                }
            }
            _ = inferFunctionBodyType(ctor.body, ctx: ctx, locals: &locals, expectedType: nil)
        }
    }

    // MARK: - Top-Level Decl Type Checking (from TypeCheckSemaPass.swift second extension)

    func typeCheckFunctionDecl(
        _ function: FunDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        guard let signature = sema.symbols.functionSignature(for: symbol) else {
            return
        }

        var locals: LocalBindings = [:]
        for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
            guard let param = sema.symbols.symbol(paramSymbol) else {
                continue
            }
            let type = index < signature.parameterTypes.count
                ? signature.parameterTypes[index]
                : sema.types.anyType
            locals[param.name] = (type, paramSymbol, false, true)
        }

        let functionCtx = ctx.copying(implicitReceiverType: signature.receiverType)
        let bodyType = inferFunctionBodyType(
            function.body,
            ctx: functionCtx,
            locals: &locals,
            expectedType: signature.returnType
        )
        driver.emitSubtypeConstraint(
            left: bodyType,
            right: signature.returnType,
            range: function.range,
            solver: solver,
            sema: sema,
            diagnostics: diagnostics
        )

        if function.returnType == nil && bodyType != sema.types.errorType {
            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: signature.receiverType,
                    parameterTypes: signature.parameterTypes,
                    returnType: bodyType,
                    isSuspend: signature.isSuspend,
                    valueParameterSymbols: signature.valueParameterSymbols,
                    valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                    valueParameterIsVararg: signature.valueParameterIsVararg,
                    typeParameterSymbols: signature.typeParameterSymbols,
                    reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices
                ),
                for: symbol
            )
        }
    }

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
        let classType = sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
        let classScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: classType,
            memberFunctions: classDecl.memberFunctions,
            memberProperties: classDecl.memberProperties,
            nestedClasses: classDecl.nestedClasses,
            nestedObjects: classDecl.nestedObjects,
            ctx: ctx
        )
        let classLabel = sema.symbols.symbol(symbol)?.name ?? ctx.interner.intern("")
        let classCtx = ctx
            .withOuterReceiver(label: classLabel, type: classType)
            .copying(scope: classScope, implicitReceiverType: classType)

        typeCheckInitBlocks(classDecl.initBlocks, ctx: classCtx)
        typeCheckSecondaryConstructors(classDecl.secondaryConstructors, ctx: classCtx, ownerSymbol: symbol, hasPrimaryConstructor: classDecl.hasPrimaryConstructorSyntax)
        typeCheckClassLikeMembers(
            memberFunctions: classDecl.memberFunctions,
            memberProperties: classDecl.memberProperties,
            nestedClasses: classDecl.nestedClasses,
            nestedObjects: classDecl.nestedObjects,
            ctx: classCtx,
            solver: solver,
            diagnostics: diagnostics
        )
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
                  case .funDecl(let function) = decl,
                  let symbol = sema.bindings.declSymbols[declID] else {
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
                  case .propertyDecl(let property) = decl,
                  let symbol = sema.bindings.declSymbols[declID] else {
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
                  let symbol = sema.bindings.declSymbols[declID] else {
                continue
            }
            switch decl {
            case .classDecl(let classDecl):
                // Inner classes inherit outer receiver context (can use this@Outer).
                // Non-inner nested classes are effectively static: clear outer receivers.
                let nestedCtx: TypeInferenceContext
                if classDecl.isInner {
                    nestedCtx = ctx
                } else {
                    nestedCtx = ctx.copying(outerReceiverTypes: [])
                }
                typeCheckClassDecl(
                    classDecl,
                    symbol: symbol,
                    ctx: nestedCtx,
                    solver: solver,
                    diagnostics: diagnostics
                )
            case .interfaceDecl:
                continue
            default:
                continue
            }
        }

        for declID in nestedObjects {
            guard let decl = ast.arena.decl(declID),
                  case .objectDecl(let objectDecl) = decl,
                  let symbol = sema.bindings.declSymbols[declID] else {
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
        return classScope
    }
}
