final class ObjectLiteralLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func lowerObjectLiteralExpr(
        _ exprID: ExprID,
        superTypes: [TypeRefID],
        declID: DeclID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let objectValueType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        if let declID,
           let decl = ast.arena.decl(declID),
           case let .objectDecl(objectDecl) = decl,
           case let .classType(classType) = sema.types.kind(of: objectValueType)
        {
            return lowerStoredObjectLiteralExpr(
                exprID,
                objectDecl: objectDecl,
                objectSymbol: classType.classSymbol,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        let symbols = syntheticObjectLiteralSymbols(for: exprID, interner: interner)
        ensureObjectLiteralGeneratedDecls(
            exprID: exprID,
            superTypeCount: superTypes.count,
            objectValueType: objectValueType,
            symbols: symbols,
            sema: sema,
            arena: arena,
            interner: interner
        )

        let objectValue = arena.appendTemporary(type: objectValueType)
        instructions.append(.call(
            symbol: symbols.constructorSymbol,
            callee: symbols.constructorName,
            arguments: [],
            result: objectValue,
            canThrow: false,
            thrownResult: nil
        ))
        return objectValue
    }

    private func lowerStoredObjectLiteralExpr(
        _ exprID: ExprID,
        objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let objectValueType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let emittedNominal = ensureObjectLiteralNominalDecl(exprID: exprID, objectSymbol: objectSymbol, arena: arena)
        if emittedNominal {
            lowerObjectLiteralMemberFunctions(
                objectDecl,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
            // BUG-141: object-literal member properties are not lowered through
            // MemberLowerer above (memberProperties: []), so synthesize a getter
            // accessor for each property that overrides an interface property.
            // appendObjectItableMethodRegistrations registers these getters into
            // the interface itable so an interface-typed receiver can read them.
            lowerObjectLiteralPropertyGetters(
                objectDecl,
                objectSymbol: objectSymbol,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
        }

        let intType = sema.types.intType
        let layout = sema.symbols.nominalLayout(for: objectSymbol)
        let slotCount = Int64(max(layout?.instanceSizeWords ?? 1, 1))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: objectSymbol,
            sema: sema,
            interner: interner
        )

        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))

        let objectValue = arena.appendTemporary(type: objectValueType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: objectValue,
            canThrow: false,
            thrownResult: nil
        ))

        registerObjectLiteralSupertypes(
            objectSymbol: objectSymbol,
            objectValue: objectValue,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        appendObjectItableMethodRegistrations(
            objectValue: objectValue,
            nominalSymbol: objectSymbol,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        appendObjectVtableMethodRegistrations(
            objectValue: objectValue,
            nominalSymbol: objectSymbol,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        emitObjectLiteralSuperConstructorCall(
            objectDecl,
            objectSymbol: objectSymbol,
            objectValue: objectValue,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // KSP-CAP-001: materialize outer locals/parameters captured by this
        // object literal's member functions into instance fields, while the
        // *enclosing* function's implicit receiver and locals are still
        // active (needed so `captureValueExpr` can resolve a captured outer
        // `this` correctly) -- i.e. before `setImplicitReceiver` below
        // switches the active receiver over to this object literal itself.
        let capturedSymbols = sema.bindings.objectLiteralCaptureSymbols(for: objectSymbol)
        for capturedSymbol in capturedSymbols {
            guard let fieldOffset = layout?.fieldOffsets[capturedSymbol],
                  let captureValue = driver.lambdaLowerer.captureValueExpr(
                      for: capturedSymbol,
                      sema: sema,
                      arena: arena,
                      interner: interner,
                      instructions: &instructions
                  )
            else {
                continue
            }
            let captureOffsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
            instructions.append(.constValue(result: captureOffsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let captureSetResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [objectValue, captureOffsetExpr, captureValue],
                result: captureSetResult,
                canThrow: true,
                thrownResult: nil
            ))
        }

        let savedReceiverExprID = driver.ctx.activeImplicitReceiverExprID()
        let savedReceiverSymbol = driver.ctx.activeImplicitReceiverSymbol()
        driver.ctx.setImplicitReceiver(symbol: objectSymbol, exprID: objectValue)
        defer {
            driver.ctx.restoreImplicitReceiver(symbol: savedReceiverSymbol, exprID: savedReceiverExprID)
        }

        for propertyDeclID in objectDecl.memberProperties {
            guard let propertySymbol = sema.bindings.declSymbols[propertyDeclID],
                  let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl,
                  let initializer = propertyDecl.initializer,
                  let fieldOffset = layout?.fieldOffsets[sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol]
            else {
                continue
            }
            let initializerValue = driver.lowerExpr(
                initializer,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let unusedResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [objectValue, offsetExpr, initializerValue],
                result: unusedResult,
                canThrow: true,
                thrownResult: nil
            ))
        }

        return objectValue
    }

    /// KSP-CAP-018: emits the implicit `super(...)` call of an object
    /// literal's superclass, e.g. `object : Base(x) { ... }`. Kotlin runs the
    /// superclass constructor before the object literal's own initializers,
    /// so the superclass's property initializers and `init` blocks — which
    /// write into the same instance at the layout offsets the object literal
    /// inherits — must execute here. Without this call an object literal
    /// instance keeps the zeroed defaults for every inherited property (same
    /// root cause as BUG-155/PR #5506's `emitSuperConstructorDelegation` for
    /// named classes; object literals never went through that fix since they
    /// have no user-written constructor of their own).
    private func emitObjectLiteralSuperConstructorCall(
        _ objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        objectValue: KIRExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) {
        guard let superclassSymbol = sema.symbols.directSupertypes(for: objectSymbol).first(where: {
            let kind = sema.symbols.symbol($0)?.kind
            return kind == .class || kind == .enumClass
        }),
        let superclassInfo = sema.symbols.symbol(superclassSymbol)
        else {
            return
        }
        let candidates = sema.symbols.lookupAll(fqName: superclassInfo.fqName + [interner.intern("<init>")])
        guard let superCtorSymbol = resolveObjectLiteralSuperConstructor(
            candidates: candidates,
            argExprs: objectDecl.superTypeConstructorArgs.map(\.expr),
            sema: sema
        ),
        sema.symbols.externalLinkName(for: superCtorSymbol)?.isEmpty ?? true
        else {
            return
        }
        if sema.symbols.symbol(superCtorSymbol)?.flags.contains(.synthetic) == true,
           sema.symbols.parentSymbol(for: superCtorSymbol) == sema.types.anyClassSymbol
        {
            // Any's compiler-provided constructor has no body to delegate to.
            return
        }

        var argIDs: [KIRExprID] = [objectValue]
        for arg in objectDecl.superTypeConstructorArgs {
            argIDs.append(driver.lowerExpr(
                arg.expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            ))
        }

        let resultID = arena.appendTemporary(type: sema.types.unitType)
        instructions.append(.call(
            symbol: superCtorSymbol,
            callee: interner.intern("<init>"),
            arguments: argIDs,
            result: resultID,
            canThrow: false,
            thrownResult: nil
        ))
    }

    /// Picks which of the superclass's `<init>` overloads `argExprs` (the
    /// object literal's `object : Base(args) { ... }` header) actually calls.
    /// A single candidate is used as-is; multiple candidates are first
    /// narrowed by arity, then — if more than one still matches — by
    /// parameter type (using each argument's Sema-resolved expression type,
    /// with a type-parameter position treated as a wildcard, mirroring
    /// `resolveOverriddenVtableSlot` in `VtableOverrideMatching.swift`).
    /// Falls back to the first candidate when nothing narrows cleanly (e.g.
    /// a defaulted trailing parameter omitted at the call site) rather than
    /// emitting no super call at all — the same residual gap
    /// `emitSuperConstructorDelegation` has for named classes, since neither
    /// path expands omitted default arguments.
    private func resolveObjectLiteralSuperConstructor(
        candidates: [SymbolID],
        argExprs: [ExprID],
        sema: SemaModule
    ) -> SymbolID? {
        guard candidates.count > 1 else {
            return candidates.first
        }
        let arityMatches = candidates.filter {
            sema.symbols.functionSignature(for: $0)?.parameterTypes.count == argExprs.count
        }
        guard arityMatches.count > 1 else {
            return arityMatches.first ?? candidates.first
        }
        let argTypes = argExprs.map { sema.bindings.exprTypes[$0] }
        let typeMatches = arityMatches.filter { candidate in
            guard let parameterTypes = sema.symbols.functionSignature(for: candidate)?.parameterTypes else {
                return false
            }
            for (paramType, argType) in zip(parameterTypes, argTypes) {
                guard let argType else { continue }
                if case .typeParam = sema.types.kind(of: paramType) { continue }
                if paramType != argType { return false }
            }
            return true
        }
        return typeMatches.count == 1 ? typeMatches[0] : arityMatches[0]
    }

    /// KSP-CAP-001: re-establishes an object literal's captured outer
    /// locals/parameters inside one of its own member functions.
    ///
    /// Member functions are lowered as independent top-level KIR functions
    /// (`MemberLowerer.lowerSingleMemberFunction` resets `driver.ctx`'s
    /// scope per function, the same way `LambdaLowerer` does per lambda), so
    /// a captured symbol's KIR value from the enclosing function is not
    /// visible here on its own -- it must be read back from the instance
    /// field it was stored into at construction time (see the capture loop
    /// in `lowerStoredObjectLiteralExpr` above), then re-registered with
    /// `driver.ctx` so ordinary `nameRef` lowering finds it exactly as if it
    /// were a plain local.
    func restoreObjectLiteralCaptures(
        forMemberFunction functionSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard let ownerSymbol = sema.symbols.parentSymbol(for: functionSymbol) else {
            return
        }
        let capturedSymbols = sema.bindings.objectLiteralCaptureSymbols(for: ownerSymbol)
        guard !capturedSymbols.isEmpty,
              let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
              let layout = sema.symbols.nominalLayout(for: ownerSymbol)
        else {
            return
        }

        let intType = sema.types.intType
        for capturedSymbol in capturedSymbols {
            guard let fieldOffset = layout.fieldOffsets[capturedSymbol] else {
                continue
            }
            let isMutableLocal = sema.symbols.symbol(capturedSymbol).map {
                $0.kind == .local && $0.flags.contains(.mutable)
            } ?? false
            // A mutable capture's field holds the boxed cell itself (see
            // `LambdaLowerer.captureValueExpr`), not the logical value, so
            // the load must be typed generically; only the box's contents
            // are typed `logicalType`, once unwrapped on actual reads/writes.
            let logicalType = sema.bindings.capturedLocalType(for: capturedSymbol)
                ?? driver.lambdaLowerer.typeForSymbolReference(capturedSymbol, sema: sema)
            let loadedType = isMutableLocal ? sema.types.anyType : logicalType

            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let loadedExpr = arena.appendTemporary(type: loadedType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverExprID, offsetExpr],
                result: loadedExpr,
                canThrow: false,
                thrownResult: nil
            ))
            if isMutableLocal {
                driver.ctx.setMutableCaptureCell(loadedExpr, for: capturedSymbol)
            } else {
                driver.ctx.setLocalValue(loadedExpr, for: capturedSymbol)
            }
            driver.ctx.setLocalDeclaredType(logicalType, for: capturedSymbol)
        }
    }

    private func registerObjectLiteralSupertypes(
        objectSymbol: SymbolID,
        objectValue _: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let childTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: objectSymbol,
            sema: sema,
            interner: interner
        )
        appendNominalSupertypeEdgeRegistrations(
            childSymbol: objectSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        // REFL-004: Register KClass binary metadata for this type.
        registerKClassMetadata(
            objectSymbol: objectSymbol,
            typeID: childTypeID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    // MARK: - REFL-004: KClass Binary Metadata Registration

    /// Emits a call to `__kk_kclass_register_metadata` to register compile-time
    /// metadata for a nominal type so that `KClass` instances can query it at runtime.
    private func registerKClassMetadata(
        objectSymbol: SymbolID,
        typeID: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard let symbol = sema.symbols.symbol(objectSymbol) else { return }

        let intType = sema.types.intType

        // Compute the full type token (nominalBase + payload).
        let typeToken = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.nominalBase,
            nullable: false,
            payload: typeID
        )
        let typeTokenExpr = arena.appendExpr(.intLiteral(typeToken), type: intType)
        instructions.append(.constValue(result: typeTokenExpr, value: .intLiteral(typeToken)))

        // Qualified name (FQ name).
        let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
        let fqNameInterned = interner.intern(fqName)
        let fqNameExpr = arena.appendExpr(.stringLiteral(fqNameInterned), type: intType)
        instructions.append(.constValue(result: fqNameExpr, value: .stringLiteral(fqNameInterned)))

        // Simple name.
        let simpleName = interner.resolve(symbol.name)
        let simpleNameInterned = interner.intern(simpleName)
        let simpleNameExpr = arena.appendExpr(.stringLiteral(simpleNameInterned), type: intType)
        instructions.append(.constValue(result: simpleNameExpr, value: .stringLiteral(simpleNameInterned)))

        // Supertype name.
        let supertypeNameExpr: KIRExprID
        let supertypes = sema.symbols.directSupertypes(for: objectSymbol)
        let superClassSymbol = supertypes.first(where: { sid in
            sema.symbols.symbol(sid)?.kind == .class
        })
        if let superClassSymbol,
           let superSymbol = sema.symbols.symbol(superClassSymbol)
        {
            let superFqName = superSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            let superInterned = interner.intern(superFqName)
            supertypeNameExpr = arena.appendExpr(.stringLiteral(superInterned), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .stringLiteral(superInterned)))
        } else {
            supertypeNameExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .intLiteral(0)))
        }

        // Flags: bit 0=dataClass, bit 1=sealedClass, bit 2=valueClass,
        //        bit 3=interface, bit 4=object, bit 5=enumClass,
        //        bit 6=annotationClass, bit 7=abstract,
        //        bit 10=inner, bit 11=companion, bit 12=funInterface. (STDLIB-REFLECT-067)
        var flags: Int64 = 0
        if symbol.flags.contains(.dataType) { flags |= 1 << 0 }
        if symbol.flags.contains(.sealedType) { flags |= 1 << 1 }
        if symbol.flags.contains(.valueType) { flags |= 1 << 2 }
        if symbol.kind == .interface { flags |= 1 << 3 }
        if symbol.kind == .object { flags |= 1 << 4 }
        if symbol.kind == .enumClass { flags |= 1 << 5 }
        if symbol.kind == .annotationClass { flags |= 1 << 6 }
        if symbol.flags.contains(.abstractType) { flags |= 1 << 7 }
        if symbol.flags.contains(.innerClass) { flags |= 1 << 10 }
        if symbol.flags.contains(.funInterface) { flags |= 1 << 12 }
        if symbol.kind == .object {
            let parentFQName = Array(symbol.fqName.dropLast())
            if let parentSymbol = sema.symbols.lookup(fqName: parentFQName),
               sema.symbols.companionObjectSymbol(for: parentSymbol) == objectSymbol {
                flags |= 1 << 11
            }
        }
        let flagsExpr = arena.appendExpr(.intLiteral(flags), type: intType)
        instructions.append(.constValue(result: flagsExpr, value: .intLiteral(flags)))

        // Field count.
        let fieldCount: Int64
        if let layout = sema.symbols.nominalLayout(for: objectSymbol) {
            fieldCount = Int64(layout.instanceFieldCount)
        } else {
            fieldCount = -1
        }
        let fieldCountExpr = arena.appendExpr(.intLiteral(fieldCount), type: intType)
        instructions.append(.constValue(result: fieldCountExpr, value: .intLiteral(fieldCount)))

        // Member count: fields + methods.
        let memberCount: Int64
        if let layout = sema.symbols.nominalLayout(for: objectSymbol) {
            memberCount = Int64(layout.instanceFieldCount + layout.vtableSize)
        } else {
            memberCount = -1
        }
        let memberCountExpr = arena.appendExpr(.intLiteral(memberCount), type: intType)
        instructions.append(.constValue(result: memberCountExpr, value: .intLiteral(memberCount)))

        let constructorCount = Int64(sema.symbols.children(ofFQName: symbol.fqName).filter { child in
            sema.symbols.symbol(child)?.kind == .constructor
        }.count)
        let constructorCountExpr = arena.appendExpr(.intLiteral(constructorCount), type: intType)
        instructions.append(.constValue(result: constructorCountExpr, value: .intLiteral(constructorCount)))

        // Call __kk_kclass_register_metadata.
        let registerResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_kclass_register_metadata"),
            arguments: [typeTokenExpr, fqNameExpr, simpleNameExpr, supertypeNameExpr, flagsExpr, fieldCountExpr, memberCountExpr, constructorCountExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))

        // STDLIB-REFLECT-065: Register annotations for this type.
        emitKClassAnnotationRegistration(
            objectSymbol: objectSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    private func ensureObjectLiteralNominalDecl(
        exprID: ExprID,
        objectSymbol: SymbolID,
        arena: KIRArena
    ) -> Bool {
        guard driver.ctx.markObjectLiteralEmitted(exprID) else {
            return false
        }
        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: objectSymbol)))
        driver.ctx.appendGeneratedCallableDecl(nominalDeclID)
        return true
    }

    private func lowerObjectLiteralMemberFunctions(
        _ objectDecl: ObjectDecl,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) {
        guard !objectDecl.memberFunctions.isEmpty else {
            return
        }
        let (_, allDecls) = driver.memberLowerer.lowerMemberDecls(
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: [],
            nestedClasses: [],
            nestedObjects: [],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
        for declID in allDecls {
            driver.ctx.appendGeneratedCallableDecl(declID)
        }
    }

    /// BUG-141: emit getter accessor functions for object-literal member
    /// properties that override an interface property, so they can be dispatched
    /// through the interface itable. Stored properties get a field-reading
    /// getter; custom-getter properties reuse their explicit getter body.
    private func lowerObjectLiteralPropertyGetters(
        _ objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) {
        guard !objectDecl.memberProperties.isEmpty else {
            return
        }
        var allDecls: [KIRDeclID] = []
        for propertyDeclID in objectDecl.memberProperties {
            guard let propertySymbol = sema.bindings.declSymbols[propertyDeclID],
                  let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            // Object-literal member properties are not flagged `.overrideMember`
            // in Sema, so every non-delegated property gets a getter accessor;
            // the itable registration only wires up the ones that match an
            // interface property, and any extra getter is simply unused.
            guard propertyDecl.delegateExpression == nil else {
                continue
            }
            let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
            if let getter = propertyDecl.getter, getter.body != .unit {
                driver.memberLowerer.lowerAccessorBody(
                    accessorBody: getter.body,
                    propertySymbol: propertySymbol,
                    propertyType: propertyType,
                    accessorKind: .getter,
                    setterParamName: nil,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    allDecls: &allDecls
                )
            } else {
                driver.memberLowerer.synthesizeStoredPropertyGetterAccessor(
                    propertySymbol: propertySymbol,
                    ownerSymbol: objectSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    allDecls: &allDecls
                )
            }
        }
        for declID in allDecls {
            driver.ctx.appendGeneratedCallableDecl(declID)
        }
    }

    private func syntheticObjectLiteralSymbols(
        for exprID: ExprID,
        interner: StringInterner
    ) -> (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString) {
        if let existing = driver.ctx.syntheticObjectLiteralSymbols(for: exprID) {
            return existing
        }
        let nominalSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let constructorSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let constructorName = interner.intern("kk_object_literal_\(exprID.rawValue)")
        let generated = (
            nominalSymbol: nominalSymbol,
            constructorSymbol: constructorSymbol,
            constructorName: constructorName
        )
        driver.ctx.registerSyntheticObjectLiteralSymbols(generated, for: exprID)
        return generated
    }

    private func ensureObjectLiteralGeneratedDecls(
        exprID: ExprID,
        superTypeCount: Int,
        objectValueType: TypeID,
        symbols: (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString),
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) {
        guard driver.ctx.markObjectLiteralEmitted(exprID) else {
            return
        }

        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbols.nominalSymbol)))
        driver.ctx.appendGeneratedCallableDecl(nominalDeclID)

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let storageSlotCount = max(1, superTypeCount)
        let slotCountExpr = arena.appendExpr(.intLiteral(Int64(storageSlotCount)), type: intType)
        let classIDExpr = arena.appendExpr(.intLiteral(0), type: intType)
        let objectEntityExpr = arena.appendTemporary(type: objectValueType)
        var body: [KIRInstruction] = [.beginBlock]
        body.append(.constValue(result: slotCountExpr, value: .intLiteral(Int64(storageSlotCount))))
        body.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: objectEntityExpr,
            canThrow: false,
            thrownResult: nil
        ))
        appendObjectVtableMethodRegistrations(
            objectValue: objectEntityExpr,
            nominalSymbol: symbols.nominalSymbol,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        )
        body.append(.returnValue(objectEntityExpr))
        body.append(.endBlock)

        let constructorDeclID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: symbols.constructorSymbol,
                    name: symbols.constructorName,
                    params: [],
                    returnType: objectValueType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(constructorDeclID)
    }
}
