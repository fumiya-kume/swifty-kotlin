// swiftlint:disable file_length

/// Data-class synthesis methods (`copy`, `equals`, `hashCode`,
/// `toString`) for both data classes and data objects.
///
/// Split out from `DataEnumSealedSynthesisPass.swift`.
extension DataEnumSealedSynthesisPass {
    func appendSyntheticDataCopyIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        existingSymbol: SymbolID?,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner,
        diagnostics: DiagnosticEngine
    ) {
        guard (owner.kind == .class || owner.kind == .enumClass || owner.kind == .object),
              let functionSymbol = existingSymbol
        else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let selfParamName = interner.intern("$self")
        let fqName = owner.fqName + [name]
        let selfParamSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: selfParamName,
            fqName: fqName + [selfParamName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let selfParam = KIRParameter(symbol: selfParamSymbol, type: receiverType)

        // Look up the constructor used for copy() synthesis.
        // Prefer the declared constructor symbol by FQName to stay aligned with
        // the lowered constructor body that codegen will emit.
        let initName = interner.intern("<init>")
        let ctorFQName = owner.fqName + [initName]
        let ctorSymbol = sema.symbols.lookupAll(fqName: ctorFQName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .constructor
        }

        // Guard: if no constructor is found, emit a simple self-returning copy()
        // to avoid generating an invalid .call instruction with nil symbol.
        guard let resolvedCtorSymbol = ctorSymbol,
              let ctorSignature = sema.symbols.functionSignature(for: resolvedCtorSymbol)
        else {
            let ownerName = interner.resolve(owner.name)
            diagnostics.warning(
                "KSWIFTK-DATA-0001",
                "data class '\(ownerName)' has no primary constructor; copy() returns self unchanged",
                range: owner.declSite
            )
            let resultExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: receiverType
            )
            let body: [KIRInstruction] = [
                .constValue(result: resultExpr, value: .symbolRef(selfParamSymbol)),
                .returnValue(resultExpr),
            ]
            let signature = FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: receiverType,
                isSuspend: false
            )
            appendSyntheticFunctionWithSymbol(
                functionSymbol: functionSymbol,
                name: name,
                module: module,
                sema: sema,
                signature: signature,
                params: [selfParam],
                body: body
            )
            return
        }

        // Collect constructor value parameters (excluding receiver).
        // The constructor signature stores symbols in valueParameterSymbols and
        // types in parameterTypes. When a receiver type is prepended to
        // parameterTypes (but not to valueParameterSymbols), we strip the leading
        // receiver entry from parameterTypes so that both arrays align 1-to-1.
        // We check both the locally-constructed receiverType and the signature's
        // own receiverType so that generic data classes (whose receiver type
        // may carry type arguments) are handled correctly.
        let ctorParamSymbols = ctorSignature.valueParameterSymbols
        var ctorParamTypes = ctorSignature.parameterTypes
        if ctorParamTypes.count > ctorParamSymbols.count,
           ctorParamTypes.first == receiverType || ctorParamTypes.first == ctorSignature.receiverType {
            ctorParamTypes.removeFirst()
        }

        // Pair up symbols and types, truncating to the shorter array for safety.
        let pairCount = min(ctorParamSymbols.count, ctorParamTypes.count)
        if ctorParamSymbols.count != ctorParamTypes.count {
            let ownerName = interner.resolve(owner.name)
            diagnostics.warning(
                "KSWIFTK-DATA-0002",
                "data class '\(ownerName)' constructor signature mismatch: \(ctorParamSymbols.count) parameter symbols vs \(ctorParamTypes.count) parameter types; copy() uses first \(pairCount)",
                range: owner.declSite
            )
        }
        let propertyParams: [(symbol: SymbolID, type: TypeID)] = (0..<pairCount).map { i in
            (ctorParamSymbols[i], ctorParamTypes[i])
        }

        // Build KIR parameters and body for copy().
        // Each copy parameter mirrors the corresponding constructor parameter name
        // (e.g. name, age) so diagnostics and dumps reflect Kotlin's copy(name=..., age=...).
        var allParams: [KIRParameter] = [selfParam]
        var allParamSymbols: [SymbolID] = [selfParamSymbol]
        var allParamTypes: [TypeID] = [receiverType]
        var allParamHasDefault: [Bool] = [false]
        var allParamIsVararg: [Bool] = [false]
        var copyParamSymbols: [SymbolID] = []

        for (ctorSym, paramType) in propertyParams {
            // Reuse the constructor parameter's name for the copy() parameter.
            let ctorParamName = sema.symbols.symbol(ctorSym)?.name ?? interner.intern("$copy_\(allParams.count)")
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: ctorParamName,
                fqName: fqName + [ctorParamName],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            )
            allParams.append(KIRParameter(symbol: paramSymbol, type: paramType))
            allParamSymbols.append(paramSymbol)
            allParamTypes.append(paramType)
            allParamHasDefault.append(true)
            allParamIsVararg.append(false)
            copyParamSymbols.append(paramSymbol)
        }

        var body: [KIRInstruction] = []
        let intType = sema.types.intType

        // Load each copy parameter.
        var ctorArgExprs: [KIRExprID] = []
        for (index, paramSymbol) in copyParamSymbols.enumerated() {
            let paramType = propertyParams[index].type
            let paramExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: paramType
            )
            body.append(.constValue(result: paramExpr, value: .symbolRef(paramSymbol)))
            ctorArgExprs.append(paramExpr)
        }

        // Allocate a fresh instance and pass it as the constructor receiver.
        let slotCount = Int64(max(sema.symbols.nominalLayout(for: owner.id)?.instanceSizeWords ?? 1, 1))
        let slotCountExpr = module.arena.appendExpr(.intLiteral(slotCount), type: intType)
        body.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: owner.id,
            sema: sema,
            interner: interner
        )
        let classIDExpr = module.arena.appendExpr(.intLiteral(classIDValue), type: intType)
        body.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let allocatedObjectExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: receiverType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: allocatedObjectExpr,
            canThrow: false,
            thrownResult: nil
        ))

        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: receiverType
        )
        body.append(.call(
            symbol: resolvedCtorSymbol,
            callee: initName,
            arguments: [allocatedObjectExpr] + ctorArgExprs,
            result: resultExpr,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(resultExpr))

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: propertyParams.map(\.type),
            returnType: receiverType,
            isSuspend: false,
            valueParameterSymbols: copyParamSymbols,
            valueParameterHasDefaultValues: Array(repeating: true, count: copyParamSymbols.count),
            valueParameterIsVararg: Array(repeating: false, count: copyParamSymbols.count)
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: name,
            module: module,
            sema: sema,
            signature: signature,
            params: allParams,
            body: body
        )
        appendSyntheticDataCopyDefaultStubIfNeeded(
            functionSymbol: functionSymbol,
            name: name,
            owner: owner,
            receiverType: receiverType,
            propertyParams: propertyParams,
            module: module,
            sema: sema,
            interner: interner
        )
    }

    func appendSyntheticDataCopyDefaultStubIfNeeded(
        functionSymbol: SymbolID,
        name: InternedString,
        owner: SemanticSymbol,
        receiverType: TypeID,
        propertyParams: [(symbol: SymbolID, type: TypeID)],
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) {
        let intType = sema.types.intType
        let fqName = owner.fqName + [name]
        let selfParamName = interner.intern("$self")
        let selfParamSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: selfParamName,
            fqName: fqName + [interner.intern("$default")] + [selfParamName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        var params: [KIRParameter] = [KIRParameter(symbol: selfParamSymbol, type: receiverType)]
        var valueParamSymbols: [SymbolID] = []
        for (index, propertyParam) in propertyParams.enumerated() {
            let paramName = sema.symbols.symbol(propertyParam.symbol)?.name ?? interner.intern("$copy_\(index)")
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: fqName + [interner.intern("$default")] + [paramName],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            )
            params.append(KIRParameter(symbol: paramSymbol, type: propertyParam.type))
            valueParamSymbols.append(paramSymbol)
        }
        let maskSymbol = SyntheticSymbolScheme.defaultMaskSymbol(for: functionSymbol)
        params.append(KIRParameter(symbol: maskSymbol, type: intType))

        let defaultStubName = interner.intern("\(interner.resolve(name))$default")
        let defaultStubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: functionSymbol)
        let selfRef = module.arena.appendExpr(.symbolRef(selfParamSymbol), type: receiverType)
        let maskRef = module.arena.appendExpr(.symbolRef(maskSymbol), type: intType)
        var body: [KIRInstruction] = [
            .constValue(result: selfRef, value: .symbolRef(selfParamSymbol)),
            .constValue(result: maskRef, value: .symbolRef(maskSymbol)),
        ]

        let layout = sema.symbols.nominalLayout(for: owner.id)
        let propertySymbols = primaryConstructorPropertySymbols(owner: owner, sema: sema)
        var resolvedArgs: [KIRExprID] = []

        for (index, propertyParam) in propertyParams.enumerated() {
            let providedExpr = module.arena.appendExpr(.symbolRef(valueParamSymbols[index]), type: propertyParam.type)
            body.append(.constValue(result: providedExpr, value: .symbolRef(valueParamSymbols[index])))

            let bitValue = Int64(1) << index
            let bitExpr = module.arena.appendExpr(.intLiteral(bitValue), type: intType)
            body.append(.constValue(result: bitExpr, value: .intLiteral(bitValue)))

            let dividedExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: intType
            )
            body.append(.binary(op: .divide, lhs: maskRef, rhs: bitExpr, result: dividedExpr))

            let twoExpr = module.arena.appendExpr(.intLiteral(2), type: intType)
            body.append(.constValue(result: twoExpr, value: .intLiteral(2)))
            let maskedExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: intType
            )
            body.append(.binary(op: .modulo, lhs: dividedExpr, rhs: twoExpr, result: maskedExpr))

            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: intType)
            body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))

            let resolvedExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: propertyParam.type
            )
            let useProvidedLabel = Int32(20000 + index * 2)
            let afterLabel = Int32(20001 + index * 2)
            body.append(.jumpIfEqual(lhs: maskedExpr, rhs: zeroExpr, target: useProvidedLabel))

            if let layout,
               index < propertySymbols.count,
               let propertySymbol = propertySymbols[index]
            {
                let backingField = sema.symbols.backingFieldSymbol(for: propertySymbol.id) ?? propertySymbol.id
                if let fieldOffset = layout.fieldOffsets[backingField] ?? layout.fieldOffsets[propertySymbol.id] {
                    let offsetExpr = module.arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
                    body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [selfRef, offsetExpr],
                        result: resolvedExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    body.append(.copy(from: providedExpr, to: resolvedExpr))
                }
            } else {
                body.append(.copy(from: providedExpr, to: resolvedExpr))
            }

            body.append(.jump(afterLabel))
            body.append(.label(useProvidedLabel))
            body.append(.copy(from: providedExpr, to: resolvedExpr))
            body.append(.label(afterLabel))
            resolvedArgs.append(resolvedExpr)
        }

        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: receiverType
        )
        body.append(.call(
            symbol: functionSymbol,
            callee: name,
            arguments: [selfRef] + resolvedArgs,
            result: resultExpr,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(resultExpr))

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: propertyParams.map(\.type) + [intType],
            returnType: receiverType,
            isSuspend: false,
            valueParameterSymbols: valueParamSymbols + [maskSymbol],
            valueParameterHasDefaultValues: Array(repeating: false, count: propertyParams.count + 1),
            valueParameterIsVararg: Array(repeating: false, count: propertyParams.count + 1)
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: defaultStubSymbol,
            name: defaultStubName,
            module: module,
            sema: sema,
            signature: signature,
            params: params,
            body: body
        )
    }

    /// Synthesizes `toString(): String` for data object, returning the object name.
    /// Uses existingSymbol when provided (from Sema) so call resolution matches the KIR function.
    func appendSyntheticDataObjectToStringIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        objectName: InternedString,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .object, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let parameterName = interner.intern("$self")
        let fqName = owner.fqName + [name]
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: receiverType)
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: stringType
        )
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .stringLiteral(objectName)),
            .returnValue(resultExpr),
        ]
        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: stringType,
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: [],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: name,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body
        )
    }

    /// Synthesizes `equals(other: Any?): Boolean` for data object (identity comparison via kk_op_eq).
    func appendSyntheticDataObjectEqualsIfNeeded(
        owner: SemanticSymbol,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .object, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = sema.types.nullableAnyType
        let equalsName = interner.intern("equals")
        let paramName = interner.intern("other")
        let fqName = owner.fqName + [equalsName]
        let paramSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: fqName + [paramName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverParam = KIRParameter(
            symbol: sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("$self"),
                fqName: fqName + [interner.intern("$self")],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            ),
            type: receiverType
        )
        let otherParam = KIRParameter(symbol: paramSymbol, type: nullableAnyType)
        let receiverRef = module.arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
        let otherRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: nullableAnyType)
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: boolType
        )
        let body: [KIRInstruction] = [
            .constValue(result: receiverRef, value: .symbolRef(receiverParam.symbol)),
            .constValue(result: otherRef, value: .symbolRef(paramSymbol)),
            .call(
                symbol: nil,
                callee: interner.intern("kk_op_eq"),
                arguments: [receiverRef, otherRef],
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ),
            .returnValue(resultExpr),
        ]
        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [nullableAnyType],
            returnType: boolType,
            isSuspend: false,
            valueParameterSymbols: [paramSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: equalsName,
            module: module,
            sema: sema,
            signature: signature,
            params: [receiverParam, otherParam],
            body: body
        )
    }

    /// Synthesizes `hashCode(): Int` for data class.
    /// Computes hash from all constructor properties using the standard Kotlin algorithm:
    ///   var result = property1.hashCode()
    ///   result = 31 * result + property2.hashCode()
    ///   ...
    ///   return result
    /// Each property hash is obtained via `kk_any_hashCode`, and the accumulation
    /// uses `kk_op_mul` (31 * result) and `kk_op_add` (+ propertyHash).
    func appendSyntheticDataClassHashCodeIfNeeded(
        owner: SemanticSymbol,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let hashCodeName = interner.intern("hashCode")
        let fqName = owner.fqName + [hashCodeName]

        let receiverParamSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: interner.intern("$self"),
            fqName: fqName + [interner.intern("$self")],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverParam = KIRParameter(symbol: receiverParamSymbol, type: receiverType)

        let propertySymbols = sema.symbols.children(ofFQName: owner.fqName)
            .compactMap { sema.symbols.symbol($0) }
            .filter { $0.kind == .property }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })

        var body: [KIRInstruction] = []

        let receiverRef = module.arena.appendExpr(.symbolRef(receiverParamSymbol), type: receiverType)
        body.append(.constValue(result: receiverRef, value: .symbolRef(receiverParamSymbol)))

        let hashCodeCallee = interner.intern("kk_any_hashCode")
        let mulCallee = interner.intern("kk_op_mul")
        let addCallee = interner.intern("kk_op_add")

        if propertySymbols.isEmpty {
            let zeroExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: intType
            )
            body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            body.append(.returnValue(zeroExpr))
        } else {
            var resultExpr: KIRExprID!
            for (index, propSym) in propertySymbols.enumerated() {
                let fieldOffsetValue: Int64
                if let layout = sema.symbols.nominalLayout(for: owner.id),
                   let offset = layout.fieldOffsets[propSym.id] {
                    fieldOffsetValue = Int64(offset)
                } else {
                    fieldOffsetValue = Int64(index)
                }

                let fieldOffsetExpr = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: intType
                )
                body.append(.constValue(result: fieldOffsetExpr, value: .intLiteral(fieldOffsetValue)))

                let propHashExpr = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: intType
                )
                body.append(.call(
                    symbol: nil,
                    callee: hashCodeCallee,
                    arguments: [receiverRef, fieldOffsetExpr],
                    result: propHashExpr,
                    canThrow: false,
                    thrownResult: nil
                ))

                if index == 0 {
                    resultExpr = propHashExpr
                } else {
                    let thirtyOneExpr = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: intType
                    )
                    body.append(.constValue(result: thirtyOneExpr, value: .intLiteral(31)))

                    let mulExpr = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: intType
                    )
                    body.append(.call(
                        symbol: nil,
                        callee: mulCallee,
                        arguments: [thirtyOneExpr, resultExpr],
                        result: mulExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))

                    let addExpr = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: intType
                    )
                    body.append(.call(
                        symbol: nil,
                        callee: addCallee,
                        arguments: [mulExpr, propHashExpr],
                        result: addExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))

                    resultExpr = addExpr
                }
            }
            body.append(.returnValue(resultExpr))
        }

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: intType,
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: [],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: hashCodeName,
            module: module,
            sema: sema,
            signature: signature,
            params: [receiverParam],
            body: body
        )
    }

    /// Synthesizes `toString(): String` for data class with properties.
    /// Output format: "ClassName(prop1=val1, prop2=val2)"
    /// Each property value is converted to string via `kk_any_to_string` and concatenated.
    func dataClassExplicitSuperclass(
        owner: SemanticSymbol,
        sema: SemaModule,
        interner: StringInterner
    ) -> SemanticSymbol? {
        let kotlinAnyFQName = [interner.intern("kotlin"), interner.intern("Any")]
        return sema.symbols.directSupertypes(for: owner.id)
            .compactMap { sema.symbols.symbol($0) }
            .first(where: { symbol in
                symbol.kind == .class && symbol.fqName != kotlinAnyFQName
            })
    }

    func appendSyntheticDataClassToStringIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        properties: [SemanticSymbol],
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let builderType = sema.types.anyType
        let layout = sema.symbols.nominalLayout(for: owner.id)
        let fqName = owner.fqName + [name]
        let parameterName = interner.intern("$self")
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: receiverType)

        var body: [KIRInstruction] = []

        // STDLIB-DATA-014: If data class inherits from another class, start with super.toString()
        let explicitSuperclass = dataClassExplicitSuperclass(owner: owner, sema: sema, interner: interner)
        var builderExpr: KIRExprID
        if let superSymbol = explicitSuperclass {
            let receiverRef = module.arena.appendExpr(.symbolRef(parameterSymbol), type: receiverType)
            body.append(.constValue(result: receiverRef, value: .symbolRef(parameterSymbol)))
            
            let superToStringResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: stringType
            )
            
            // Find super.toString() method symbol
            let toStringName = interner.intern("toString")
            let superToStringFQName = superSymbol.fqName + [toStringName]
            let superToStringSymbol = sema.symbols.lookupAll(fqName: superToStringFQName).first
            
            // Call super.toString() if it exists, otherwise use default
            if let superToStringSymbol = superToStringSymbol {
                body.append(.call(
                    symbol: superToStringSymbol,
                    callee: interner.intern("toString"),
                    arguments: [receiverRef],
                    result: superToStringResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // Fallback: use simple class name representation
                let className = interner.resolve(superSymbol.name)
                let fallbackStr = interner.intern("\(className)")
                body.append(.constValue(result: superToStringResult, value: .stringLiteral(fallbackStr)))
            }
            
            // Create string builder from super.toString()
            builderExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: builderType
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_string_builder_new_from_string"),
                arguments: [superToStringResult],
                result: builderExpr,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            // Start with "ClassName(" for data class with no inheritance
            let className = interner.resolve(owner.name)
            let prefixStr = interner.intern("\(className)(")
            let prefixExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: stringType
            )
            body.append(.constValue(result: prefixExpr, value: .stringLiteral(prefixStr)))
            builderExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: builderType
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_string_builder_new_from_string"),
                arguments: [prefixExpr],
                result: builderExpr,
                canThrow: false,
                thrownResult: nil
            ))
        }

        for (index, property) in properties.enumerated() {
            let propName = interner.resolve(property.name)
            // Append "propName=" (or ", propName=" for subsequent properties)
            let labelStr: String = index == 0 ? "\(propName)=" : ", \(propName)="
            let labelInterned = interner.intern(labelStr)
            let labelExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: stringType
            )
            body.append(.constValue(result: labelExpr, value: .stringLiteral(labelInterned)))

            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_string_builder_append_obj"),
                arguments: [builderExpr, labelExpr],
                result: builderExpr,
                canThrow: false,
                thrownResult: nil
            ))

            // Read the constructor-backed field directly so data-class synthesis
            // does not depend on separate property accessor emission.
            let receiverRef = module.arena.appendExpr(.symbolRef(parameterSymbol), type: receiverType)
            body.append(.constValue(result: receiverRef, value: .symbolRef(parameterSymbol)))

            let propType = sema.symbols.propertyType(for: property.id) ?? sema.types.anyType
            let propValue = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: propType
            )
            let backingField = sema.symbols.backingFieldSymbol(for: property.id) ?? property.id
            if let layout,
               let fieldOffset = layout.fieldOffsets[backingField] ?? layout.fieldOffsets[property.id]
            {
                let offsetExpr = module.arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
                body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [receiverRef, offsetExpr],
                    result: propValue,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                let nullOutThrown = module.arena.appendExpr(.null, type: sema.types.nullableAnyType)
                body.append(.constValue(result: nullOutThrown, value: .null))
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_abort_unreachable"),
                    arguments: [nullOutThrown],
                    result: propValue,
                    canThrow: false,
                    thrownResult: nil
                ))
            }

            // Convert to string via kk_any_to_string using the same tag convention
            // as Any.toString lowering.
            let anyTag = anyToStringTag(for: propType, sema: sema)
            let tagExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: intType
            )
            body.append(.constValue(result: tagExpr, value: .intLiteral(anyTag)))

            let propStr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: stringType
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_to_string"),
                arguments: [propValue, tagExpr],
                result: propStr,
                canThrow: false,
                thrownResult: nil
            ))

            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_string_builder_append_obj"),
                arguments: [builderExpr, propStr],
                result: builderExpr,
                canThrow: false,
                thrownResult: nil
            ))
        }

        // Append closing ")" only if not inheriting from another class
        let shouldCloseParen = explicitSuperclass == nil
        
        if shouldCloseParen {
            let suffixStr = interner.intern(")")
            let suffixExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: stringType
            )
            body.append(.constValue(result: suffixExpr, value: .stringLiteral(suffixStr)))

            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_string_builder_append_obj"),
                arguments: [builderExpr, suffixExpr],
                result: builderExpr,
                canThrow: false,
                thrownResult: nil
            ))
        }

        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: stringType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_string_builder_toString"),
            arguments: [builderExpr],
            result: resultExpr,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(resultExpr))

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: stringType,
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: [],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: name,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body
        )
    }

    /// Synthesizes `equals(other: Any?): Boolean` for data class with properties.
    /// Compares each property of `this` and `other` via `kk_op_eq`, returning false
    /// if any differ.
    func appendSyntheticDataClassEqualsIfNeeded(
        owner: SemanticSymbol,
        properties: [SemanticSymbol],
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = sema.types.nullableAnyType
        let layout = sema.symbols.nominalLayout(for: owner.id)
        let equalsName = interner.intern("equals")
        let paramName = interner.intern("other")
        let fqName = owner.fqName + [equalsName]
        let paramSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: fqName + [paramName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverParam = KIRParameter(
            symbol: sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("$self"),
                fqName: fqName + [interner.intern("$self")],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            ),
            type: receiverType
        )
        let otherParam = KIRParameter(symbol: paramSymbol, type: nullableAnyType)

        var body: [KIRInstruction] = []
        var nextLabel: Int32 = 0
        func allocateLabel() -> Int32 {
            defer { nextLabel += 1 }
            return nextLabel
        }

        if properties.isEmpty {
            let receiverRef = module.arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
            let otherRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: nullableAnyType)
            let resultExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: boolType
            )
            body.append(.constValue(result: receiverRef, value: .symbolRef(receiverParam.symbol)))
            body.append(.constValue(result: otherRef, value: .symbolRef(paramSymbol)))
            
            // STDLIB-DATA-014: If data class inherits from another class, call super.equals()
            if let superSymbol = dataClassExplicitSuperclass(owner: owner, sema: sema, interner: interner) {
                // Find super.equals() method symbol
                let equalsName = interner.intern("equals")
                let superEqualsFQName = superSymbol.fqName + [equalsName]
                let superEqualsSymbol = sema.symbols.lookupAll(fqName: superEqualsFQName).first
                
                // Call super.equals(other) if it exists, otherwise use reference equality
                if let superEqualsSymbol = superEqualsSymbol {
                    body.append(.call(
                        symbol: superEqualsSymbol,
                        callee: interner.intern("equals"),
                        arguments: [receiverRef, otherRef],
                        result: resultExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    // Fallback: use reference equality
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_op_eq"),
                        arguments: [receiverRef, otherRef],
                        result: resultExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
            } else {
                // Use reference equality for data class with no properties and no inheritance
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_eq"),
                    arguments: [receiverRef, otherRef],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            body.append(.returnValue(resultExpr))
        } else {
            let intType = sema.types.intType
            let falseExpr = module.arena.appendExpr(.boolLiteral(false), type: boolType)
            body.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

            let typeTokenValue = RuntimeTypeCheckToken.encode(type: receiverType, sema: sema, interner: interner)
            let typeTokenExpr = module.arena.appendExpr(.intLiteral(typeTokenValue), type: intType)
            body.append(.constValue(result: typeTokenExpr, value: .intLiteral(typeTokenValue)))

            let otherAnyRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: nullableAnyType)
            body.append(.constValue(result: otherAnyRef, value: .symbolRef(paramSymbol)))

            let isSameTypeExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: boolType
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [otherAnyRef, typeTokenExpr],
                result: isSameTypeExpr,
                canThrow: false,
                thrownResult: nil
            ))

            let returnFalseLabel = allocateLabel()
            body.append(.jumpIfEqual(lhs: isSameTypeExpr, rhs: falseExpr, target: returnFalseLabel))

            let otherTypedRef = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: receiverType
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_safe_cast"),
                arguments: [otherAnyRef, typeTokenExpr],
                result: otherTypedRef,
                canThrow: false,
                thrownResult: nil
            ))

            for property in properties {
                let propType = sema.symbols.propertyType(for: property.id) ?? sema.types.anyType
                let backingField = sema.symbols.backingFieldSymbol(for: property.id) ?? property.id
                let fieldOffset = layout.flatMap { $0.fieldOffsets[backingField] ?? $0.fieldOffsets[property.id] }

                let selfRef = module.arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
                body.append(.constValue(result: selfRef, value: .symbolRef(receiverParam.symbol)))
                let selfProp = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: propType
                )

                let otherProp = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: propType
                )
                if let fieldOffset {
                    let offsetExpr = module.arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
                    body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [selfRef, offsetExpr],
                        result: selfProp,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [otherTypedRef, offsetExpr],
                        result: otherProp,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    let nullOutThrown = module.arena.appendExpr(.null, type: sema.types.nullableAnyType)
                    body.append(.constValue(result: nullOutThrown, value: .null))
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_abort_unreachable"),
                        arguments: [nullOutThrown],
                        result: selfProp,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_abort_unreachable"),
                        arguments: [nullOutThrown],
                        result: otherProp,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }

                let cmpResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: boolType
                )
                // Use structural equality for reference types (String, class instances, etc.)
                // to match Kotlin data class equals() semantics. Primitive types can use
                // pointer/value equality via kk_op_eq.
                let eqCallee: String = switch sema.types.kind(of: sema.types.makeNonNullable(propType)) {
                case .primitive(.string, _), .classType, .any:
                    "kk_structural_eq"
                case .primitive:
                    "kk_op_eq"
                default:
                    "kk_structural_eq"
                }
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern(eqCallee),
                    arguments: [selfProp, otherProp],
                    result: cmpResult,
                    canThrow: false,
                    thrownResult: nil
                ))

                body.append(.jumpIfEqual(lhs: cmpResult, rhs: falseExpr, target: returnFalseLabel))
            }

            // STDLIB-DATA-014: If data class inherits from another class, call super.equals() first
            if let superSymbol = dataClassExplicitSuperclass(owner: owner, sema: sema, interner: interner) {
                let receiverRef = module.arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
                let otherRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: nullableAnyType)
                let superEqualsResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: boolType
                )
                body.append(.constValue(result: receiverRef, value: .symbolRef(receiverParam.symbol)))
                body.append(.constValue(result: otherRef, value: .symbolRef(paramSymbol)))
                
                // Find super.equals() method symbol
                let equalsName = interner.intern("equals")
                let superEqualsFQName = superSymbol.fqName + [equalsName]
                let superEqualsSymbol = sema.symbols.lookupAll(fqName: superEqualsFQName).first
                
                // Call super.equals(other) if it exists, otherwise use reference equality
                if let superEqualsSymbol = superEqualsSymbol {
                    body.append(.call(
                        symbol: superEqualsSymbol,
                        callee: interner.intern("equals"),
                        arguments: [receiverRef, otherRef],
                        result: superEqualsResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    // Fallback: use reference equality (consistent with properties-empty branch)
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_op_eq"),
                        arguments: [receiverRef, otherRef],
                        result: superEqualsResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }

                // If super.equals() returns false, return false immediately
                body.append(.jumpIfEqual(lhs: superEqualsResult, rhs: falseExpr, target: returnFalseLabel))
            }

            let trueResult = module.arena.appendExpr(
                .boolLiteral(true),
                type: boolType
            )
            body.append(.constValue(result: trueResult, value: .boolLiteral(true)))
            body.append(.returnValue(trueResult))

            body.append(.label(returnFalseLabel))
            let falseResult = module.arena.appendExpr(
                .boolLiteral(false),
                type: boolType
            )
            body.append(.constValue(result: falseResult, value: .boolLiteral(false)))
            body.append(.returnValue(falseResult))
        }

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [nullableAnyType],
            returnType: boolType,
            isSuspend: false,
            valueParameterSymbols: [paramSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: equalsName,
            module: module,
            sema: sema,
            signature: signature,
            params: [receiverParam, otherParam],
            body: body
        )
    }

}
