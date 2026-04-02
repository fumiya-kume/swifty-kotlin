import Foundation

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

        let objectValue = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: objectValueType)
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
        ensureObjectLiteralNominalDecl(exprID: exprID, objectSymbol: objectSymbol, arena: arena)

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

        let objectValue = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: objectValueType)
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
            let unusedResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
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

    private func registerObjectLiteralSupertypes(
        objectSymbol: SymbolID,
        objectValue _: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let intType = sema.types.intType
        let childTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: objectSymbol,
            sema: sema,
            interner: interner
        )
        let childExpr = arena.appendExpr(.intLiteral(childTypeID), type: intType)
        instructions.append(.constValue(result: childExpr, value: .intLiteral(childTypeID)))

        for superSymbol in sema.symbols.directSupertypes(for: objectSymbol) {
            let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: superSymbol,
                sema: sema,
                interner: interner
            )
            let parentExpr = arena.appendExpr(.intLiteral(parentTypeID), type: intType)
            instructions.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
            let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            let superKind = sema.symbols.symbol(superSymbol)?.kind
            let registerCallee: InternedString = if superKind == .interface {
                interner.intern("kk_type_register_iface")
            } else {
                interner.intern("kk_type_register_super")
            }
            instructions.append(.call(
                symbol: nil,
                callee: registerCallee,
                arguments: [childExpr, parentExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }

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

    /// Emits a call to `kk_kclass_register_metadata` to register compile-time
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
        //        bit 6=annotationClass, bit 7=abstract
        var flags: Int64 = 0
        if symbol.flags.contains(.dataType) { flags |= 1 << 0 }
        if symbol.flags.contains(.sealedType) { flags |= 1 << 1 }
        if symbol.flags.contains(.valueType) { flags |= 1 << 2 }
        if symbol.kind == .interface { flags |= 1 << 3 }
        if symbol.kind == .object { flags |= 1 << 4 }
        if symbol.kind == .enumClass { flags |= 1 << 5 }
        if symbol.kind == .annotationClass { flags |= 1 << 6 }
        if symbol.flags.contains(.abstractType) { flags |= 1 << 7 }
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

        // Call kk_kclass_register_metadata.
        let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_kclass_register_metadata"),
            arguments: [typeTokenExpr, fqNameExpr, simpleNameExpr, supertypeNameExpr, flagsExpr, fieldCountExpr, memberCountExpr, constructorCountExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))

        // STDLIB-REFLECT-065: Register annotations for this type.
        emitAnnotationRegistration(
            objectSymbol: objectSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    // MARK: - STDLIB-REFLECT-065: Annotation Registration

    /// Emits calls to register annotation metadata for a nominal type.
    /// Emits one `kk_kclass_register_single_annotation` call per annotation
    /// to avoid requiring runtime list construction at the KIR level.
    private func emitAnnotationRegistration(
        objectSymbol: SymbolID,
        typeTokenExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let annotations = sema.symbols.annotations(for: objectSymbol)
        guard !annotations.isEmpty else { return }

        let intType = sema.types.intType
        let stringType = sema.types.stringType

        for annotation in annotations {
            // Annotation FQ name.
            let nameInterned = interner.intern(annotation.annotationFQName)
            let nameExpr = arena.appendExpr(.stringLiteral(nameInterned), type: stringType)
            instructions.append(.constValue(result: nameExpr, value: .stringLiteral(nameInterned)))

            // Encode arguments as a single pipe-delimited string for simplicity.
            let argsEncoded = annotation.arguments.joined(separator: "|")
            let argsInterned = interner.intern(argsEncoded)
            let argsExpr = arena.appendExpr(.stringLiteral(argsInterned), type: stringType)
            instructions.append(.constValue(result: argsExpr, value: .stringLiteral(argsInterned)))

            // Argument count.
            let argCount = Int64(annotation.arguments.count)
            let argCountExpr = arena.appendExpr(.intLiteral(argCount), type: intType)
            instructions.append(.constValue(result: argCountExpr, value: .intLiteral(argCount)))

            // Call kk_kclass_register_single_annotation(typeToken, fqName, argsEncoded, argCount).
            let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_register_single_annotation"),
                arguments: [typeTokenExpr, nameExpr, argsExpr, argCountExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }

    private func ensureObjectLiteralNominalDecl(
        exprID: ExprID,
        objectSymbol: SymbolID,
        arena: KIRArena
    ) {
        guard driver.ctx.markObjectLiteralEmitted(exprID) else {
            return
        }
        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: objectSymbol)))
        driver.ctx.appendGeneratedCallableDecl(nominalDeclID)
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
        let objectEntityExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: objectValueType)
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
