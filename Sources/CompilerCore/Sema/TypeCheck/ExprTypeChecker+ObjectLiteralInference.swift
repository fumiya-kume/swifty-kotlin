
extension ExprTypeChecker {
    func inferObjectLiteralExpr(
        _ id: ExprID,
        superTypes: [TypeRefID],
        declID: DeclID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        guard let declID,
              let decl = ast.arena.decl(declID),
              case let .objectDecl(objectDecl) = decl
        else {
            if let firstSuperType = superTypes.first {
                let resolved = driver.helpers.resolveTypeRef(
                    firstSuperType,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                sema.bindings.bindExprType(id, type: resolved)
                return resolved
            }
            // No superTypes and no declID → malformed object literal;
            // upstream parser already emitted an error.
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        let objectSymbol = ensureObjectLiteralSymbol(
            declID: declID,
            objectDecl: objectDecl,
            superTypes: superTypes,
            ctx: ctx,
            locals: &locals
        )
        let objectType = sema.types.make(.classType(ClassType(
            classSymbol: objectSymbol,
            args: [],
            nullability: .nonNull
        )))
        sema.bindings.bindExprType(id, type: objectType)
        return objectType
    }

    private func ensureObjectLiteralSymbol(
        declID: DeclID,
        objectDecl: ObjectDecl,
        superTypes: [TypeRefID],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> SymbolID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        if let existing = sema.bindings.declSymbols[declID] {
            return existing
        }

        // KSP-CAP-001: snapshot the enclosing scope's local bindings before
        // this object literal (or its member type-checking below) adds
        // anything of its own, so member function bodies can be seeded with
        // exactly what was visible at the point the object literal appears —
        // mirroring how lambda bodies capture outer locals.
        let outerLocalsSnapshot = locals
        let outerSymbols = Set(outerLocalsSnapshot.values.map(\.symbol))

        let objectSymbol = sema.symbols.define(
            kind: .class,
            name: objectDecl.name,
            fqName: [objectDecl.name],
            declSite: objectDecl.range,
            visibility: .private,
            flags: [.synthetic]
        )
        sema.bindings.bindDecl(declID, symbol: objectSymbol)
        sema.symbols.setSourceFileID(ctx.currentFileID, for: objectSymbol)

        var directSuperSymbols: [SymbolID] = []
        directSuperSymbols.reserveCapacity(superTypes.count)
        var directSuperTypeArgs: [SymbolID: [TypeArg]] = [:]
        for superTypeRef in superTypes {
            let resolved = driver.helpers.resolveTypeRef(
                superTypeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.semaCtx.diagnostics
            )
            if case let .classType(classType) = sema.types.kind(of: resolved),
               !directSuperSymbols.contains(classType.classSymbol)
            {
                directSuperSymbols.append(classType.classSymbol)
                directSuperTypeArgs[classType.classSymbol] = classType.args
            }
        }
        let concreteClassSupers = directSuperSymbols.filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID) else {
                return false
            }
            switch symbol.kind {
            case .class, .enumClass, .object, .annotationClass:
                return true
            default:
                return false
            }
        }
        if concreteClassSupers.count > 1 {
            let classNames = concreteClassSupers.compactMap { sema.symbols.symbol($0)?.fqName.last }
                .map { interner.resolve($0) }
                .joined(separator: ", ")
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0170",
                "Object literal '\(interner.resolve(objectDecl.name))' cannot inherit from more than one class. Found: \(classNames).",
                range: objectDecl.range
            )
        }
        sema.symbols.setDirectSupertypes(directSuperSymbols, for: objectSymbol)
        sema.types.setNominalDirectSupertypes(directSuperSymbols, for: objectSymbol)
        for (superSymbol, args) in directSuperTypeArgs {
            sema.symbols.setSupertypeTypeArgs(args, for: objectSymbol, supertype: superSymbol)
            sema.types.setNominalSupertypeTypeArgs(args, for: objectSymbol, supertype: superSymbol)
        }

        // KSP-CAP-018: the superclass constructor call's arguments
        // (`object : Base(x) { ... }`) are evaluated in the *enclosing*
        // scope — same as a class header's `: Base(x)` — so they are
        // type-checked against the outer `ctx`/`locals`, not `objectScope`
        // below. Without this, `arg.expr` reaches KIR lowering with no type
        // binding or resolved symbol reference and lowers to a stray value.
        for arg in objectDecl.superTypeConstructorArgs {
            _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: nil)
        }

        var propertySymbolsByDecl: [DeclID: SymbolID] = [:]
        for propertyDeclID in objectDecl.memberProperties {
            guard let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            var propertyFlags: SymbolFlags = [.synthetic]
            if propertyDecl.isVar {
                propertyFlags.insert(.mutable)
            }
            let propertySymbol = sema.symbols.define(
                kind: .property,
                name: propertyDecl.name,
                fqName: [objectDecl.name, propertyDecl.name],
                declSite: propertyDecl.range,
                visibility: .public,
                flags: propertyFlags
            )
            sema.bindings.bindDecl(propertyDeclID, symbol: propertySymbol)
            sema.bindings.markObjectLiteralPropertySymbol(propertySymbol)
            sema.symbols.setParentSymbol(objectSymbol, for: propertySymbol)
            sema.symbols.setSourceFileID(ctx.currentFileID, for: propertySymbol)

            let declaredType = propertyDecl.type.map {
                driver.helpers.resolveTypeRef(
                    $0,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: ctx.scope,
                    diagnostics: ctx.semaCtx.diagnostics,
                    inferenceContext: ctx,
                    usageRange: propertyDecl.range
                )
            } ?? sema.types.anyType
            sema.symbols.setPropertyType(declaredType, for: propertySymbol)
            propertySymbolsByDecl[propertyDeclID] = propertySymbol
        }

        let objectType = sema.types.make(.classType(ClassType(
            classSymbol: objectSymbol,
            args: [],
            nullability: .nonNull
        )))
        let objectScope = ClassMemberScope(
            parent: ctx.scope,
            symbols: sema.symbols,
            ownerSymbol: objectSymbol,
            thisType: objectType
        )
        for propertySymbol in propertySymbolsByDecl.values {
            objectScope.insert(propertySymbol)
        }
        let memberFunctionSymbolsByDecl = collectObjectLiteralMemberFunctions(
            objectDecl.memberFunctions,
            objectDecl: objectDecl,
            objectSymbol: objectSymbol,
            objectType: objectType,
            objectScope: objectScope,
            ctx: ctx
        )
        let objectCtx = ctx.copying(
            scope: objectScope,
            implicitReceiverType: objectType,
            enclosingClassSymbol: objectSymbol
        )

        for propertyDeclID in objectDecl.memberProperties {
            guard let propertySymbol = propertySymbolsByDecl[propertyDeclID],
                  let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }

            let declaredType = propertyDecl.type.map {
                driver.helpers.resolveTypeRef(
                    $0,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: objectScope,
                    diagnostics: ctx.semaCtx.diagnostics,
                    inferenceContext: objectCtx,
                    usageRange: propertyDecl.range
                )
            }

            let inferredType: TypeID?
            if let initializer = propertyDecl.initializer {
                let type = driver.inferExpr(
                    initializer,
                    ctx: objectCtx,
                    locals: &locals,
                    expectedType: declaredType
                )
                if let declaredType {
                    driver.emitSubtypeConstraint(
                        left: type,
                        right: declaredType,
                        range: propertyDecl.range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                }
                inferredType = type
            } else {
                inferredType = nil
            }

            let finalType: TypeID
            if let declaredType {
                finalType = declaredType
            } else if let inferredType {
                finalType = inferredType
            } else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0101",
                    "Property '\(interner.resolve(propertyDecl.name))' in object literal must have a type annotation or initializer.",
                    range: propertyDecl.range
                )
                finalType = sema.types.errorType
            }
            sema.symbols.setPropertyType(finalType, for: propertySymbol)
        }

        // KSP-CAP-001: member function bodies resolve outer locals the same
        // way lambda bodies do — seeded via `locals`, which `inferNameRefExpr`
        // always checks before the class member scope chain. Verified against
        // kotlinc: an outer local shadows an object literal's own member of
        // the same name (not the other way around) — a bare reference inside
        // the member function binds to the captured outer local, and the
        // object's own member is only reachable via explicit `this.member`.
        var capturedSymbols: Set<SymbolID> = []
        for functionDeclID in objectDecl.memberFunctions {
            guard let functionSymbol = memberFunctionSymbolsByDecl[functionDeclID],
                  let decl = ast.arena.decl(functionDeclID),
                  case let .funDecl(functionDecl) = decl
            else {
                continue
            }
            driver.declChecker.typeCheckFunctionDecl(
                functionDecl,
                symbol: functionSymbol,
                ctx: objectCtx.with(currentDeclSymbol: functionSymbol),
                solver: driver.solver,
                diagnostics: ctx.semaCtx.diagnostics,
                baseLocals: outerLocalsSnapshot
            )
            capturedSymbols.formUnion(driver.captureAnalyzer.collectCapturedOuterSymbols(
                inBody: functionDecl.body,
                ast: ast,
                sema: sema,
                outerSymbols: outerSymbols
            ))
        }
        if !capturedSymbols.isEmpty {
            var typesBySymbol: [SymbolID: TypeID] = [:]
            for binding in outerLocalsSnapshot.values {
                typesBySymbol[binding.symbol] = binding.type
            }
            for capturedSymbol in capturedSymbols {
                if let type = typesBySymbol[capturedSymbol] {
                    sema.bindings.bindCapturedLocalType(capturedSymbol, type: type)
                }
            }
            sema.bindings.bindObjectLiteralCaptureSymbols(
                objectSymbol,
                symbols: capturedSymbols.sorted(by: { $0.rawValue < $1.rawValue })
            )
        }

        let superClass = directSuperSymbols.first { superSymbol in
            guard let symbol = sema.symbols.symbol(superSymbol) else {
                return false
            }
            return symbol.kind != .interface
        }
        let inheritedLayout = superClass.flatMap { sema.symbols.nominalLayout(for: $0) }
        var fieldOffsets = inheritedLayout?.fieldOffsets ?? [:]
        let objectHeaderWords = inheritedLayout?.objectHeaderWords ?? 2
        var nextFieldOffset = (fieldOffsets.values.max() ?? (objectHeaderWords - 1)) + 1
        for propertyDeclID in objectDecl.memberProperties {
            guard let propertySymbol = propertySymbolsByDecl[propertyDeclID],
                  fieldOffsets[propertySymbol] == nil
            else {
                continue
            }
            fieldOffsets[propertySymbol] = nextFieldOffset
            nextFieldOffset += 1
        }
        // KSP-CAP-001: give each captured outer local/parameter its own
        // instance field so member functions (lowered as independent KIR
        // functions, unlike inlined property initializers) can read the
        // captured value back through `this` regardless of which method
        // originally referenced it.
        for capturedSymbol in capturedSymbols.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard fieldOffsets[capturedSymbol] == nil else {
                continue
            }
            fieldOffsets[capturedSymbol] = nextFieldOffset
            nextFieldOffset += 1
        }

        let inheritedFieldCount = inheritedLayout?.instanceFieldCount ?? 0
        let instanceFieldCount = inheritedFieldCount + propertySymbolsByDecl.count + capturedSymbols.count
        let inheritedInstanceSizeWords = inheritedLayout?.instanceSizeWords ?? 0
        let instanceSizeWords = max(objectHeaderWords + instanceFieldCount, inheritedInstanceSizeWords)
        let inheritedVtableSlots = inheritedLayout?.vtableSlots ?? [:]
        let inheritedItableSlots = inheritedLayout?.itableSlots ?? [:]
        let inheritedVtableSize = inheritedLayout?.vtableSize
        let inheritedItableSize = inheritedLayout?.itableSize

        // An object literal's own members are only known once the enclosing
        // function body is type-checked, well after `synthesizeNominalLayouts`
        // has already assigned vtable slots for every named class/object/interface
        // (see `runValidationPasses` vs. `runBodyAnalysis` in Phase.swift). So
        // unlike a named `class`/`object`, this nominal never goes through that
        // pass — without this, `vtableSlots` would stay a bare copy of the
        // superclass's own slots and an `override fun` here would leave its
        // inherited slot pointing at the base class's implementation (the base
        // method would keep running instead of the override, silently).
        var vtableSlots = inheritedVtableSlots
        let inheritedCandidatesByKey = vtableInheritedCandidatesByKey(
            inheritedVtableSlots: inheritedVtableSlots, symbols: sema.symbols
        )
        for memberSymbolID in memberFunctionSymbolsByDecl.values.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let method = sema.symbols.symbol(memberSymbolID),
                  method.flags.contains(.overrideMember),
                  let candidates = inheritedCandidatesByKey[vtableMethodDispatchKey(for: method, symbols: sema.symbols)]
            else { continue }
            let parameterTypes = sema.symbols.functionSignature(for: method.id)?.parameterTypes ?? []
            if let matchedSlot = resolveOverriddenVtableSlot(parameterTypes: parameterTypes, candidates: candidates, types: sema.types) {
                vtableSlots[method.id] = matchedSlot
            }
        }

        // BUG-239: an object literal that implements an interface directly
        // (no superclass to inherit itable slots from — e.g. `object :
        // MutableIterator<Int> { ... }`) previously kept `inheritedItableSlots`
        // verbatim, which is empty in that case. `appendObjectItableMethodRegistrations`
        // then fell back to slot 0 for every interface it registers, so two
        // interfaces (e.g. `Iterator` and `MutableIterator`) collided into the
        // same itable slot and the later registration silently overwrote the
        // earlier interface's method table. Mirror the named-class path
        // (`LayoutSynthesis.synthesizeLayoutForNominal`) by walking this
        // literal's own transitive interface supertypes and assigning each one
        // not already covered by inheritance a fresh slot.
        var itableSlots = inheritedItableSlots
        var nextItableSlot = max(inheritedItableSize ?? 0, (itableSlots.values.max() ?? -1) + 1)
        for interfaceID in kirTransitiveInterfaceSupertypes(of: objectSymbol, sema: sema)
            where itableSlots[interfaceID] == nil
        {
            itableSlots[interfaceID] = nextItableSlot
            nextItableSlot += 1
        }

        sema.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: objectHeaderWords,
                instanceFieldCount: instanceFieldCount,
                instanceSizeWords: instanceSizeWords,
                fieldOffsets: fieldOffsets,
                vtableSlots: vtableSlots,
                itableSlots: itableSlots,
                vtableSize: inheritedVtableSize,
                itableSize: nextItableSlot,
                superClass: superClass
            ),
            for: objectSymbol
        )
        return objectSymbol
    }

    private func collectObjectLiteralMemberFunctions(
        _ memberFunctions: [DeclID],
        objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        objectType: TypeID,
        objectScope: ClassMemberScope,
        ctx: TypeInferenceContext
    ) -> [DeclID: SymbolID] {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        var result: [DeclID: SymbolID] = [:]

        for functionDeclID in memberFunctions {
            guard let decl = ast.arena.decl(functionDeclID),
                  case let .funDecl(functionDecl) = decl
            else {
                continue
            }

            let memberSymbol = sema.symbols.define(
                kind: .function,
                name: functionDecl.name,
                fqName: [objectDecl.name, functionDecl.name],
                declSite: functionDecl.range,
                visibility: objectLiteralVisibility(from: functionDecl.modifiers),
                flags: objectLiteralFunctionFlags(
                    from: functionDecl,
                    objectSymbol: objectSymbol,
                    sema: sema,
                    interner: interner
                )
            )
            sema.bindings.bindDecl(functionDeclID, symbol: memberSymbol)
            sema.symbols.setParentSymbol(objectSymbol, for: memberSymbol)
            sema.symbols.setSourceFileID(ctx.currentFileID, for: memberSymbol)
            objectScope.insert(memberSymbol)

            var parameterTypes: [TypeID] = []
            var parameterSymbols: [SymbolID] = []
            for param in functionDecl.valueParams {
                let paramType: TypeID = if let typeRefID = param.type {
                    driver.helpers.resolveTypeRef(
                        typeRefID,
                        ast: ast,
                        sema: sema,
                        interner: interner,
                        scope: objectScope,
                        diagnostics: ctx.semaCtx.diagnostics,
                        inferenceContext: ctx,
                        usageRange: functionDecl.range
                    )
                } else {
                    sema.types.anyType
                }
                parameterTypes.append(paramType)

                let paramSymbol = sema.symbols.define(
                    kind: .valueParameter,
                    name: param.name,
                    fqName: [objectDecl.name, functionDecl.name, param.name],
                    declSite: functionDecl.range,
                    visibility: .private,
                    flags: []
                )
                sema.symbols.setParentSymbol(memberSymbol, for: paramSymbol)
                sema.symbols.setPropertyType(paramType, for: paramSymbol)
                parameterSymbols.append(paramSymbol)
            }

            let returnType: TypeID
            if let returnTypeRef = functionDecl.returnType {
                returnType = driver.helpers.resolveTypeRef(
                    returnTypeRef,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: objectScope,
                    diagnostics: ctx.semaCtx.diagnostics,
                    inferenceContext: ctx
                )
            } else {
                switch functionDecl.body {
                case .unit, .block:
                    returnType = sema.types.unitType
                case .expr:
                    returnType = sema.types.anyType
                }
            }

            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: objectType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    isSuspend: functionDecl.isSuspend,
                    valueParameterSymbols: parameterSymbols,
                    valueParameterHasDefaultValues: functionDecl.valueParams.map(\.hasDefaultValue),
                    valueParameterIsVararg: functionDecl.valueParams.map(\.isVararg)
                ),
                for: memberSymbol
            )
            result[functionDeclID] = memberSymbol
        }

        return result
    }

    private func objectLiteralVisibility(from modifiers: Modifiers) -> Visibility {
        if modifiers.contains(.private) { return .private }
        if modifiers.contains(.internal) { return .internal }
        if modifiers.contains(.protected) { return .protected }
        return .public
    }

    private func objectLiteralFunctionFlags(
        from functionDecl: FunDecl,
        objectSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolFlags {
        var flags: SymbolFlags = [.synthetic]
        if functionDecl.isSuspend { flags.insert(.suspendFunction) }
        if functionDecl.isInline { flags.insert(.inlineFunction) }
        if functionDecl.modifiers.contains(.operator) { flags.insert(.operatorFunction) }
        if functionDecl.modifiers.contains(.override) { flags.insert(.overrideMember) }
        if functionDecl.modifiers.contains(.abstract) { flags.insert(.abstractType) }
        if functionDecl.modifiers.contains(.open) { flags.insert(.openType) }
        if functionDecl.modifiers.contains(.final) { flags.insert(.finalMember) }

        // KSP-441: Object literal overrides of operator functions (e.g. Sequence.iterator,
        // Iterator.hasNext/next) must carry the operator flag so for-in lowering can
        // resolve them without an explicit `operator` keyword on the override.
        if !flags.contains(.operatorFunction),
           flags.contains(.overrideMember),
           functionHasOperatorBase(
               name: functionDecl.name,
               parameterCount: functionDecl.valueParams.count,
               ownerSymbol: objectSymbol,
               sema: sema,
               interner: interner
           )
        {
            flags.insert(.operatorFunction)
        }
        return flags
    }

    private func functionHasOperatorBase(
        name: InternedString,
        parameterCount: Int,
        ownerSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        var stack = sema.symbols.directSupertypes(for: ownerSymbol)
        var visited: Set<SymbolID> = []
        while let current = stack.popLast() {
            guard visited.insert(current).inserted else { continue }
            guard let currentSymbol = sema.symbols.symbol(current) else { continue }
            let candidateFQName = currentSymbol.fqName + [name]
            for candidate in sema.symbols.lookupAll(fqName: candidateFQName) {
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      symbol.flags.contains(.operatorFunction),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == parameterCount,
                      sema.symbols.parentSymbol(for: candidate) == current
                else { continue }
                return true
            }
            stack.append(contentsOf: sema.symbols.directSupertypes(for: current))
        }
        return false
    }
}
