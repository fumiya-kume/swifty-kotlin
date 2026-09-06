extension LambdaLowerer {
    private enum PropertyReferenceShape {
        case property0
        case mutableProperty0
        case property1
        case mutableProperty1

        var arity: Int {
            switch self {
            case .property0, .mutableProperty0:
                0
            case .property1, .mutableProperty1:
                1
            }
        }

        var isMutable: Bool {
            switch self {
            case .mutableProperty0, .mutableProperty1:
                true
            case .property0, .property1:
                false
            }
        }
    }

    private struct PropertyReferenceAccessor {
        let propertySymbol: SymbolID
        let getterSymbol: SymbolID
        let setterSymbol: SymbolID?
        let propertyType: TypeID
        let ownerType: TypeID?
    }

    /// Lowers the KProperty0/1 family to a heap object with explicit interface
    /// registrations. KProperty2 is intentionally left on the legacy path until
    /// its receiver/capture ABI is specified separately.
    func lowerPropertyReferenceWrapperValue(
        _ exprID: ExprID,
        targetSymbol: SymbolID?,
        memberName: InternedString,
        boundType: TypeID?,
        isUnbound: Bool,
        captureArguments: [KIRExprID],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let boundType,
              case let .classType(referenceType) = sema.types.kind(of: boundType),
              let shape = propertyReferenceShape(
                  interfaceSymbol: referenceType.classSymbol,
                  sema: sema,
                  interner: interner
              ),
              let targetSymbol,
              let accessor = ensurePropertyReferenceAccessor(
                  targetSymbol: targetSymbol,
                  ast: ast,
                  sema: sema,
                  arena: arena,
                  interner: interner,
                  propertyConstantInitializers: propertyConstantInitializers
              )
        else {
            return nil
        }

        let interfaceSymbol = referenceType.classSymbol
        let interfaceSymbols = propertyReferenceInterfaceClosure(
            root: interfaceSymbol,
            sema: sema
        )
        guard !interfaceSymbols.isEmpty else { return nil }

        let wrapperName = interner.intern("kk_kproperty_wrapper_\(exprID.rawValue)")
        let wrapperFQName = [wrapperName]
        let wrapperSymbol = sema.symbols.define(
            kind: .class,
            name: wrapperName,
            fqName: wrapperFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        sema.symbols.setDirectSupertypes([interfaceSymbol], for: wrapperSymbol)
        sema.types.setNominalDirectSupertypes([interfaceSymbol], for: wrapperSymbol)
        sema.symbols.setSupertypeTypeArgs(referenceType.args, for: wrapperSymbol, supertype: interfaceSymbol)
        sema.types.setNominalSupertypeTypeArgs(referenceType.args, for: wrapperSymbol, supertype: interfaceSymbol)

        let wrapperType = sema.types.make(.classType(ClassType(
            classSymbol: wrapperSymbol,
            args: [],
            nullability: .nonNull
        )))

        var fieldOffsets: [SymbolID: Int] = [:]
        var captureFields: [SymbolID] = []
        for (index, capture) in captureArguments.enumerated() {
            let fieldName = interner.intern("$property_capture_\(index)")
            let fieldSymbol = sema.symbols.define(
                kind: .field,
                name: fieldName,
                fqName: wrapperFQName + [fieldName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setParentSymbol(wrapperSymbol, for: fieldSymbol)
            sema.symbols.setPropertyType(
                arena.exprType(capture) ?? sema.types.anyType,
                for: fieldSymbol
            )
            fieldOffsets[fieldSymbol] = index + 2
            captureFields.append(fieldSymbol)
        }

        let getterMethodSymbol = definePropertyReferenceMethod(
            name: "get",
            wrapperSymbol: wrapperSymbol,
            wrapperFQName: wrapperFQName,
            parameterTypes: shape.arity == 0 ? [] : [accessor.ownerType ?? sema.types.anyType],
            returnType: accessor.propertyType,
            sema: sema,
            interner: interner
        )
        let setterMethodSymbol: SymbolID? = shape.isMutable
            ? definePropertyReferenceMethod(
                name: "set",
                wrapperSymbol: wrapperSymbol,
                wrapperFQName: wrapperFQName,
                parameterTypes: (shape.arity == 0 ? [] : [accessor.ownerType ?? sema.types.anyType]) + [accessor.propertyType],
                returnType: sema.types.unitType,
                sema: sema,
                interner: interner
            )
            : nil

        let itableSlots = Dictionary(
            uniqueKeysWithValues: interfaceSymbols.enumerated().map { index, symbol in
                (symbol, index)
            }
        )
        sema.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: captureFields.count,
                instanceSizeWords: max(2 + captureFields.count, 1),
                fieldOffsets: fieldOffsets,
                vtableSlots: [:],
                itableSlots: itableSlots,
                vtableSize: 0,
                itableSize: interfaceSymbols.count,
                superClass: nil
            ),
            for: wrapperSymbol
        )
        driver.ctx.appendGeneratedCallableDecl(
            arena.appendDecl(.nominalType(KIRNominalType(symbol: wrapperSymbol)))
        )

        emitPropertyReferenceGetter(
            methodSymbol: getterMethodSymbol,
            wrapperType: wrapperType,
            shape: shape,
            accessor: accessor,
            captureFields: captureFields,
            fieldOffsets: fieldOffsets,
            sema: sema,
            arena: arena,
            interner: interner
        )
        if let setterMethodSymbol {
            emitPropertyReferenceSetter(
                methodSymbol: setterMethodSymbol,
                wrapperType: wrapperType,
                shape: shape,
                accessor: accessor,
                captureFields: captureFields,
                fieldOffsets: fieldOffsets,
                sema: sema,
                arena: arena,
                interner: interner
            )
        }

        let intType = sema.types.intType
        let slotCount = Int64(max(2 + captureFields.count, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: wrapperSymbol,
            sema: sema,
            interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
        let wrapperValue = arena.appendTemporary(type: boundType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: wrapperValue,
            canThrow: false,
            thrownResult: nil
        ))

        registerPropertyReferenceInterfaces(
            wrapperValue: wrapperValue,
            wrapperSymbol: wrapperSymbol,
            interfaceSymbols: interfaceSymbols,
            getterMethodSymbol: getterMethodSymbol,
            setterMethodSymbol: setterMethodSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        for (index, capture) in captureArguments.enumerated() {
            guard index < captureFields.count,
                  let fieldOffset = fieldOffsets[captureFields[index]]
            else { continue }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let storeResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [wrapperValue, offsetExpr, capture],
                result: storeResult,
                canThrow: true,
                thrownResult: nil
            ))
        }

        let nameExpr = arena.appendExpr(.stringLiteral(memberName), type: sema.types.stringType)
        instructions.append(.constValue(result: nameExpr, value: .stringLiteral(memberName)))
        let returnTypeName = interner.intern(
            sema.types.displayName(of: accessor.propertyType, symbols: sema.symbols, interner: interner)
        )
        let returnTypeExpr = arena.appendExpr(.stringLiteral(returnTypeName), type: sema.types.stringType)
        instructions.append(.constValue(result: returnTypeExpr, value: .stringLiteral(returnTypeName)))
        let arityExpr = arena.appendExpr(.intLiteral(Int64(shape.arity)), type: intType)
        instructions.append(.constValue(result: arityExpr, value: .intLiteral(Int64(shape.arity))))
        let taggedValue = arena.appendTemporary(type: boundType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_callable_ref_tag_kproperty"),
            arguments: [wrapperValue, nameExpr, returnTypeExpr, arityExpr],
            result: taggedValue,
            canThrow: false,
            thrownResult: nil
        ))
        driver.ctx.registerCallableValue(
            taggedValue,
            symbol: getterMethodSymbol,
            callee: interner.intern("get"),
            captureArguments: [wrapperValue],
            hasClosureParam: false
        )
        _ = isUnbound
        return taggedValue
    }

    private func propertyReferenceShape(
        interfaceSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> PropertyReferenceShape? {
        guard let symbol = sema.symbols.symbol(interfaceSymbol) else { return nil }
        switch interner.resolve(symbol.name) {
        case "KProperty0": return .property0
        case "KMutableProperty0": return .mutableProperty0
        case "KProperty1": return .property1
        case "KMutableProperty1": return .mutableProperty1
        default: return nil
        }
    }

    private func propertyReferenceInterfaceClosure(
        root: SymbolID,
        sema: SemaModule
    ) -> [SymbolID] {
        var result: [SymbolID] = []
        var pending = [root]
        var visited: Set<SymbolID> = []
        while let symbol = pending.popLast() {
            guard visited.insert(symbol).inserted else { continue }
            guard sema.symbols.symbol(symbol)?.kind == .interface else { continue }
            result.append(symbol)
            pending.append(contentsOf: sema.symbols.directSupertypes(for: symbol))
        }
        return result.sorted { $0.rawValue < $1.rawValue }
    }

    private func propertySymbol(for targetSymbol: SymbolID, sema: SemaModule) -> SymbolID? {
        if sema.symbols.symbol(targetSymbol)?.kind == .property {
            return targetSymbol
        }
        if let owner = sema.symbols.accessorOwnerProperty(for: targetSymbol) {
            return owner
        }
        return sema.symbols.allSymbols().first { symbol in
            symbol.kind == .property
                && (SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol.id) == targetSymbol
                    || SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol.id) == targetSymbol)
        }?.id
    }

    private func propertyDecl(
        for propertySymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule
    ) -> PropertyDecl? {
        for rawDecl in ast.arena.decls.indices {
            let declID = DeclID(rawValue: Int32(rawDecl))
            guard sema.bindings.declSymbols[declID] == propertySymbol,
                  let decl = ast.arena.decl(declID),
                  case let .propertyDecl(property) = decl
            else { continue }
            return property
        }
        return nil
    }

    private func ensurePropertyReferenceAccessor(
        targetSymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) -> PropertyReferenceAccessor? {
        guard let propertySymbol = propertySymbol(for: targetSymbol, sema: sema),
              let propertyType = sema.symbols.propertyType(for: propertySymbol)
        else { return nil }

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        let ownerKind = ownerSymbol.flatMap { sema.symbols.symbol($0)?.kind }
        // KSP-505: a genuine `.object` owner (companion object or plain
        // `object`) is a singleton — Kotlin guarantees exactly one instance,
        // so the compiler stores such properties in a single module-level
        // global slot rather than a per-instance field (see the matching
        // `pk == .object` branch in ExprLowerer+ControlFlowAndBlocks.swift's
        // ordinary member read path). Passing `ownerType: nil` here routes
        // emitPropertyReferenceAccessor's fallback below (loadGlobal /
        // storeGlobal, no receiver) instead of the field-offset path, which
        // would otherwise read/write through a receiver that is frequently a
        // null placeholder (object singletons that implement no interface
        // and declare no virtual dispatch never allocate a real heap
        // instance) — this used to crash with SIGSEGV.
        //
        // Every other owner kind — including `.class`/`.interface` (real
        // per-instance field storage) and `.enumClass` (per-*entry*
        // instance storage — confirmed by testing that it must NOT be
        // treated like `.object` here, or a per-entry constructor property
        // like `enum class E(val v: Int) { A(1), B(2) }`'s `v` silently
        // reads back `0` for every entry instead of each entry's own value;
        // see isCaptureEligibleInstanceContainerSymbol's doc comment) —
        // keeps the original unconditional ownerType computation, unchanged
        // from before this fix.
        let ownerType: TypeID? = ownerKind == .object
            ? nil
            : ownerSymbol.flatMap { owner in
                sema.symbols.symbol(owner).map {
                    sema.types.make(.classType(ClassType(
                        classSymbol: $0.id,
                        args: [],
                        nullability: .nonNull
                    )))
                }
            }
        let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
            ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
            ?? (sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
                ? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
                : nil)

        if arena.function(for: getterSymbol) == nil {
            emitPropertyReferenceAccessor(
                propertySymbol: propertySymbol,
                accessorSymbol: getterSymbol,
                ownerType: ownerType,
                propertyType: propertyType,
                kind: .getter,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
        }
        if let setterSymbol,
           arena.function(for: setterSymbol) == nil
        {
            emitPropertyReferenceAccessor(
                propertySymbol: propertySymbol,
                accessorSymbol: setterSymbol,
                ownerType: ownerType,
                propertyType: propertyType,
                kind: .setter,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
        }
        return PropertyReferenceAccessor(
            propertySymbol: propertySymbol,
            getterSymbol: getterSymbol,
            setterSymbol: setterSymbol,
            propertyType: propertyType,
            ownerType: ownerType
        )
    }

    private func emitPropertyReferenceAccessor(
        propertySymbol: SymbolID,
        accessorSymbol: SymbolID,
        ownerType: TypeID?,
        propertyType: TypeID,
        kind: PropertyAccessorKind,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) {
        if let property = propertyDecl(for: propertySymbol, ast: ast, sema: sema),
           let body = kind == .getter ? property.getter?.body : property.setter?.body,
           body != .unit
        {
            var decls: [KIRDeclID] = []
            driver.memberLowerer.lowerAccessorBody(
                accessorBody: body,
                propertySymbol: propertySymbol,
                propertyType: propertyType,
                accessorKind: kind,
                setterParamName: property.setter?.parameterName,
                shared: KIRLoweringSharedContext(
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers
                ),
                allDecls: &decls
            )
            for decl in decls {
                driver.ctx.appendGeneratedCallableDecl(decl)
            }
            return
        }

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        let fieldKey = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
        let fieldOffset = ownerSymbol.flatMap {
            sema.symbols.nominalLayout(for: $0)?.fieldOffsets[fieldKey]
        }
        let receiverSymbol = ownerType.map { _ in
            driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: accessorSymbol)
        }
        let valueSymbol: SymbolID? = kind == .setter
            ? sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("value"),
                fqName: [interner.intern("kk_property_accessor_\(accessorSymbol.rawValue)"), interner.intern("value")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            : nil
        if let valueSymbol { sema.symbols.setPropertyType(propertyType, for: valueSymbol) }

        var params: [KIRParameter] = []
        if let receiverSymbol, let ownerType {
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
        }
        if let valueSymbol {
            params.append(KIRParameter(symbol: valueSymbol, type: propertyType))
        }
        let accessorName = interner.intern(kind == .getter ? "get" : "set")
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: kind == .setter ? [propertyType] : [],
                returnType: kind == .getter ? propertyType : sema.types.unitType,
                valueParameterSymbols: valueSymbol.map { [$0] } ?? []
            ),
            for: accessorSymbol
        )

        var body: [KIRInstruction] = [.beginBlock]
        let receiverExpr = receiverSymbol.flatMap { symbol -> KIRExprID? in
            guard let ownerType else { return nil }
            let expr = arena.appendExpr(.symbolRef(symbol), type: ownerType)
            body.append(.constValue(result: expr, value: .symbolRef(symbol)))
            return expr
        }
        if let fieldOffset,
           let receiverExpr
        {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            if kind == .getter {
                let result = arena.appendTemporary(type: propertyType)
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [receiverExpr, offsetExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                body.append(.returnValue(result))
            } else if let valueSymbol {
                let valueExpr = arena.appendExpr(.symbolRef(valueSymbol), type: propertyType)
                body.append(.constValue(result: valueExpr, value: .symbolRef(valueSymbol)))
                let result = arena.appendTemporary(type: sema.types.anyType)
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [receiverExpr, offsetExpr, valueExpr],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                body.append(.returnUnit)
            }
        } else if kind == .getter {
            // KSP-496: an immutable top-level (or object-member) property
            // with a compile-time-constant initializer is never actually
            // written via `.storeGlobal` — every ordinary read inlines the
            // constant directly instead (see the equivalent check in
            // ExprLowerer+ControlFlowAndBlocks.swift). Emitting a bare
            // `.loadGlobal` here read that permanently-unwritten (zero)
            // slot. Mirror the same constant-inlining check before falling
            // back to `.loadGlobal` for genuinely global-backed properties
            // (`var`s, or `val`s with a non-constant initializer).
            let propertyInfo = sema.symbols.symbol(propertySymbol)
            if let constant = propertyConstantInitializers[propertySymbol] ?? sema.symbols.constValueExprKind(for: propertySymbol),
               propertyInfo?.flags.contains(.mutable) != true
            {
                let result = arena.appendExpr(constant, type: propertyType)
                body.append(.constValue(result: result, value: constant))
                body.append(.returnValue(result))
            } else {
                let result = arena.appendTemporary(type: propertyType)
                body.append(.loadGlobal(result: result, symbol: fieldKey))
                body.append(.returnValue(result))
            }
        } else if let valueSymbol {
            let valueExpr = arena.appendExpr(.symbolRef(valueSymbol), type: propertyType)
            body.append(.constValue(result: valueExpr, value: .symbolRef(valueSymbol)))
            body.append(.storeGlobal(value: valueExpr, symbol: fieldKey))
            body.append(.returnUnit)
        } else {
            let result = arena.appendExpr(.null, type: propertyType)
            body.append(.constValue(result: result, value: .null))
            body.append(.returnValue(result))
        }
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: accessorSymbol,
            name: accessorName,
            params: params,
            returnType: kind == .getter ? propertyType : sema.types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
    }

    private func definePropertyReferenceMethod(
        name: String,
        wrapperSymbol: SymbolID,
        wrapperFQName: [InternedString],
        parameterTypes: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID {
        let methodName = interner.intern(name)
        let methodSymbol = sema.symbols.define(
            kind: .function,
            name: methodName,
            fqName: wrapperFQName + [methodName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        sema.symbols.setParentSymbol(wrapperSymbol, for: methodSymbol)
        let parameterSymbols = parameterTypes.enumerated().map { index, type in
            let symbol = sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("$p\(index)"),
                fqName: wrapperFQName + [methodName, interner.intern("$p\(index)")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setPropertyType(type, for: symbol)
            return symbol
        }
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: sema.types.make(.classType(ClassType(
                    classSymbol: wrapperSymbol,
                    args: [],
                    nullability: .nonNull
                ))),
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols
            ),
            for: methodSymbol
        )
        return methodSymbol
    }

    private func emitPropertyReferenceGetter(
        methodSymbol: SymbolID,
        wrapperType: TypeID,
        shape: PropertyReferenceShape,
        accessor: PropertyReferenceAccessor,
        captureFields: [SymbolID],
        fieldOffsets: [SymbolID: Int],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) {
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: methodSymbol)
        let parameterSymbols = sema.symbols.functionSignature(for: methodSymbol)?.valueParameterSymbols ?? []
        let params = [KIRParameter(symbol: receiverSymbol, type: wrapperType)] + parameterSymbols.compactMap { symbol in
            sema.symbols.propertyType(for: symbol).map { KIRParameter(symbol: symbol, type: $0) }
        }
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: wrapperType)
        var body: [KIRInstruction] = [.beginBlock, .constValue(result: receiverExpr, value: .symbolRef(receiverSymbol))]
        var captures: [KIRExprID] = []
        for (index, field) in captureFields.enumerated() {
            guard let offset = fieldOffsets[field] else { continue }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(offset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))
            let captureType = params.dropFirst().first?.type ?? accessor.ownerType ?? sema.types.anyType
            let capture = arena.appendTemporary(type: captureType)
            body.append(.call(symbol: nil, callee: interner.intern("kk_array_get_inbounds"), arguments: [receiverExpr, offsetExpr], result: capture, canThrow: false, thrownResult: nil))
            captures.append(capture)
            _ = index
        }
        var callArgs = captures
        if shape.arity == 1, let parameter = params.dropFirst().first {
            let parameterExpr = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: parameterExpr, value: .symbolRef(parameter.symbol)))
            callArgs.append(parameterExpr)
        }
        let result = arena.appendTemporary(type: accessor.propertyType)
        body.append(.call(symbol: accessor.getterSymbol, callee: interner.intern("get"), arguments: callArgs, result: result, canThrow: false, thrownResult: nil))
        body.append(.returnValue(result))
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: methodSymbol,
            name: interner.intern("get"),
            params: params,
            returnType: accessor.propertyType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
    }

    private func emitPropertyReferenceSetter(
        methodSymbol: SymbolID,
        wrapperType: TypeID,
        shape: PropertyReferenceShape,
        accessor: PropertyReferenceAccessor,
        captureFields: [SymbolID],
        fieldOffsets: [SymbolID: Int],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) {
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: methodSymbol)
        let parameterSymbols = sema.symbols.functionSignature(for: methodSymbol)?.valueParameterSymbols ?? []
        let params = [KIRParameter(symbol: receiverSymbol, type: wrapperType)] + parameterSymbols.compactMap { symbol in
            sema.symbols.propertyType(for: symbol).map { KIRParameter(symbol: symbol, type: $0) }
        }
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: wrapperType)
        var body: [KIRInstruction] = [.beginBlock, .constValue(result: receiverExpr, value: .symbolRef(receiverSymbol))]
        var captures: [KIRExprID] = []
        for field in captureFields {
            guard let offset = fieldOffsets[field] else { continue }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(offset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))
            let captureType = accessor.ownerType ?? sema.types.anyType
            let capture = arena.appendTemporary(type: captureType)
            body.append(.call(symbol: nil, callee: interner.intern("kk_array_get_inbounds"), arguments: [receiverExpr, offsetExpr], result: capture, canThrow: false, thrownResult: nil))
            captures.append(capture)
        }
        var callArgs = captures
        if shape.arity == 1, let parameter = params.dropFirst().first {
            let parameterExpr = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: parameterExpr, value: .symbolRef(parameter.symbol)))
            callArgs.append(parameterExpr)
        }
        if let valueParameter = params.dropFirst().last {
            let valueExpr = arena.appendExpr(.symbolRef(valueParameter.symbol), type: valueParameter.type)
            body.append(.constValue(result: valueExpr, value: .symbolRef(valueParameter.symbol)))
            callArgs.append(valueExpr)
        }
        let result = arena.appendTemporary(type: sema.types.unitType)
        body.append(.call(symbol: accessor.setterSymbol, callee: interner.intern("set"), arguments: callArgs, result: result, canThrow: false, thrownResult: nil))
        body.append(.returnUnit)
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: methodSymbol,
            name: interner.intern("set"),
            params: params,
            returnType: sema.types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
    }

    private func registerPropertyReferenceInterfaces(
        wrapperValue: KIRExprID,
        wrapperSymbol: SymbolID,
        interfaceSymbols: [SymbolID],
        getterMethodSymbol: SymbolID,
        setterMethodSymbol: SymbolID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let intType = sema.types.intType
        let classID = RuntimeTypeCheckToken.stableNominalTypeID(symbol: wrapperSymbol, sema: sema, interner: interner)
        let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
        let layout = sema.symbols.nominalLayout(for: wrapperSymbol)
        for interfaceSymbol in interfaceSymbols {
            let interfaceID = RuntimeTypeCheckToken.stableNominalTypeID(symbol: interfaceSymbol, sema: sema, interner: interner)
            let interfaceExpr = arena.appendExpr(.intLiteral(interfaceID), type: intType)
            instructions.append(.constValue(result: interfaceExpr, value: .intLiteral(interfaceID)))
            let edgeResult = arena.appendTemporary(type: intType)
            instructions.append(.call(symbol: nil, callee: interner.intern("kk_type_register_iface"), arguments: [classIDExpr, interfaceExpr], result: edgeResult, canThrow: false, thrownResult: nil))

            guard let ifaceSlot = layout?.itableSlots[interfaceSymbol] else { continue }
            let ifaceSlotExpr = arena.appendExpr(.intLiteral(Int64(ifaceSlot)), type: intType)
            instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(Int64(ifaceSlot))))
            let registerIfaceResult = arena.appendTemporary(type: intType)
            instructions.append(.call(symbol: nil, callee: interner.intern("kk_object_register_itable_iface"), arguments: [wrapperValue, interfaceExpr, ifaceSlotExpr], result: registerIfaceResult, canThrow: false, thrownResult: nil))

            guard let ifaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol) else { continue }
            for (methodSymbol, methodSlot) in ifaceLayout.vtableSlots {
                guard let methodInfo = sema.symbols.symbol(methodSymbol) else { continue }
                let implementation: SymbolID?
                switch interner.resolve(methodInfo.name) {
                case "get", "invoke": implementation = getterMethodSymbol
                case "set": implementation = setterMethodSymbol
                default: implementation = nil
                }
                guard let implementation else { continue }
                let methodSlotExpr = arena.appendExpr(.intLiteral(Int64(methodSlot)), type: intType)
                instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(Int64(methodSlot))))
                let registeredImplementation = propertyReferenceStringReturnBridge(
                    interfaceMethod: methodSymbol,
                    implementation: implementation,
                    driver: driver,
                    arena: arena,
                    sema: sema,
                    interner: interner
                ) ?? itableBridgeSymbolForMethod(
                    interfaceMethod: methodSymbol,
                    implementation: implementation,
                    nominalSymbol: wrapperSymbol,
                    driver: driver,
                    arena: arena,
                    sema: sema,
                    interner: interner
                )
                let methodFnExpr = arena.appendExpr(.symbolRef(registeredImplementation), type: intType)
                instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(registeredImplementation)))
                let registerMethodResult = arena.appendTemporary(type: intType)
                instructions.append(.call(symbol: nil, callee: interner.intern("kk_object_register_itable_method"), arguments: [wrapperValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr], result: registerMethodResult, canThrow: false, thrownResult: nil))
            }
        }
    }

    /// Generic KProperty interfaces use the raw Kotlin handle ABI at an
    /// itable boundary even when their substituted type is String. The wrapper
    /// getter intentionally returns the native String aggregate, so provide an
    /// erased bridge for get/invoke before registering the function pointer.
    private func propertyReferenceStringReturnBridge(
        interfaceMethod: SymbolID,
        implementation: SymbolID,
        driver: KIRLoweringDriver,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        guard let methodInfo = sema.symbols.symbol(interfaceMethod),
              (interner.resolve(methodInfo.name) == "get" || interner.resolve(methodInfo.name) == "invoke"),
              let implementationFunction = arena.function(for: implementation),
              case .stringStruct = sema.types.kind(of: implementationFunction.returnType),
              let interfaceSignature = sema.symbols.functionSignature(for: interfaceMethod)
        else {
            return nil
        }

        let bridgeSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let bridgeName = interner.intern(
            "kk_kproperty_string_bridge_"
                + String(interfaceMethod.rawValue)
                + "_"
                + String(implementation.rawValue)
                + "_"
                + String(bridgeSymbol.rawValue)
        )
        var bridgeParams: [KIRParameter] = []
        if let receiverType = interfaceSignature.receiverType {
            bridgeParams.append(KIRParameter(
                symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
                type: receiverType
            ))
        }
        bridgeParams.append(contentsOf: interfaceSignature.parameterTypes.map { type in
            KIRParameter(symbol: driver.ctx.allocateSyntheticGeneratedSymbol(), type: type)
        })

        var body: [KIRInstruction] = [.beginBlock]
        var args: [KIRExprID] = []
        for parameter in bridgeParams {
            let expr = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: expr, value: .symbolRef(parameter.symbol)))
            args.append(expr)
        }
        let result = arena.appendTemporary(type: implementationFunction.returnType)
        body.append(.call(
            symbol: implementation,
            callee: interner.intern("__kk_kproperty_impl_" + String(implementation.rawValue)),
            arguments: args,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(result))
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: bridgeSymbol,
            name: bridgeName,
            params: bridgeParams,
            returnType: sema.types.anyType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
        return bridgeSymbol
    }
}
