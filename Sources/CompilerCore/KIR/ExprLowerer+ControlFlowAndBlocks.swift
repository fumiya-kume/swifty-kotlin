// swiftlint:disable file_length

extension ExprLowerer {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func lowerExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        guard let expr = ast.arena.expr(exprID) else {
            let temp = arena.appendTemporary(type: sema.types.errorType)
            instructions.append(.constValue(result: temp, value: .unit))
            return temp
        }
        let stringType = sema.types.stringType

        switch expr {
        case let .intLiteral(value, _):
            let id = arena.appendExpr(.intLiteral(value), type: boundType ?? intType)
            instructions.append(.constValue(result: id, value: .intLiteral(value)))
            return id

        case let .longLiteral(value, _):
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let id = arena.appendExpr(.longLiteral(value), type: boundType ?? longType)
            instructions.append(.constValue(result: id, value: .longLiteral(value)))
            return id

        case let .uintLiteral(value, _):
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let id = arena.appendExpr(.uintLiteral(value), type: boundType ?? uintType)
            instructions.append(.constValue(result: id, value: .uintLiteral(value)))
            return id

        case let .ulongLiteral(value, _):
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let id = arena.appendExpr(.ulongLiteral(value), type: boundType ?? ulongType)
            instructions.append(.constValue(result: id, value: .ulongLiteral(value)))
            return id

        case let .floatLiteral(value, _):
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let id = arena.appendExpr(.floatLiteral(value), type: boundType ?? floatType)
            instructions.append(.constValue(result: id, value: .floatLiteral(value)))
            return id

        case let .doubleLiteral(value, _):
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let id = arena.appendExpr(.doubleLiteral(value), type: boundType ?? doubleType)
            instructions.append(.constValue(result: id, value: .doubleLiteral(value)))
            return id

        case let .charLiteral(value, _):
            let charType = sema.types.make(.primitive(.char, .nonNull))
            let id = arena.appendExpr(.charLiteral(value), type: boundType ?? charType)
            instructions.append(.constValue(result: id, value: .charLiteral(value)))
            return id

        case let .boolLiteral(value, _):
            let id = arena.appendExpr(.boolLiteral(value), type: boundType ?? boolType)
            instructions.append(.constValue(result: id, value: .boolLiteral(value)))
            return id

        case let .stringLiteral(value, _):
            let id = arena.appendExpr(.stringLiteral(value), type: boundType ?? stringType)
            instructions.append(.constValue(result: id, value: .stringLiteral(value)))
            return id

        case let .stringTemplate(parts, _):
            var partIDs: [KIRExprID] = []
            for part in parts {
                switch part {
                case let .literal(interned):
                    let partID = arena.appendExpr(.stringLiteral(interned), type: stringType)
                    instructions.append(.constValue(result: partID, value: .stringLiteral(interned)))
                    partIDs.append(partID)
                case let .expression(exprID):
                    let lowered = lowerExpr(
                        exprID,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    // Bodies Sema never visits (a stdlib delegate's callback
                    // lambda, for instance) have no bound expression type; the
                    // lowered KIR type is the only description of the value and
                    // must still drive the string conversion.
                    let exprType = sema.bindings.exprTypes[exprID] ?? arena.exprType(lowered)
                    if let exprType, exprType != stringType {
                        // See CallLowerer.emitAnyToStringWithNullGuard for why nullable
                        // Float?/Double?/ULong? need an explicit null guard before
                        // kk_any_to_string (their null-sentinel bit pattern coincides
                        // with a legitimate in-range value for those tags).
                        let converted = driver.callLowerer.emitAnyToStringWithNullGuard(
                            valueID: lowered,
                            valueType: exprType,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        partIDs.append(converted)
                    } else {
                        partIDs.append(lowered)
                    }
                }
            }
            if partIDs.isEmpty {
                let emptyStr = interner.intern("")
                let id = arena.appendExpr(.stringLiteral(emptyStr), type: stringType)
                instructions.append(.constValue(result: id, value: .stringLiteral(emptyStr)))
                return id
            }
            var accumulated = partIDs[0]
            for i in 1 ..< partIDs.count {
                let concatResult = arena.appendTemporary(type: stringType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_concat_flat"),
                    arguments: [accumulated, partIDs[i]],
                    result: concatResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                accumulated = concatResult
            }
            return accumulated

        case let .nameRef(name, _):
            let nullID = interner.intern("null")
            let thisID = interner.intern("this")
            // Resolve lambda param by name (handles collection HOF fallback where identifierSymbols may be unbound).
            if let paramSymbol = driver.ctx.lambdaParamSymbol(named: name),
               let localValue = driver.ctx.localValue(for: paramSymbol)
            {
                return localValue
            }
            if name == nullID {
                let id = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
                instructions.append(.constValue(result: id, value: .null))
                return id
            }
            if name == thisID,
               let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
            {
                return receiverExprID
            }
            // STDLIB-004: Implicit receiver member access (e.g. `length` inside
            // `run { length }` resolves as `this.length`).
            if let memberName = sema.bindings.implicitReceiverMemberNames[exprID],
               let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
            {
                let receiverType = arena.exprType(receiverExprID) ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                let memberStr = interner.resolve(memberName)
                let resultType = boundType ?? sema.types.anyType
                let result = arena.appendTemporary(type: resultType
                )
                // String properties
                if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                    if memberStr == "length" {
                        emitNonThrowingCall(
                            callee: interner.intern("__kk_string_struct_get_length"),
                            arg: receiverExprID,
                            result: result,
                            into: &instructions
                        )
                        return result
                    }
                }

                // Collection properties: size, isEmpty. Restricted to receivers
                // that are collections (or of unknown class), so that a user
                // class declaring its own `size`/`isEmpty` member keeps its
                // declared accessor / backing field on implicit-receiver reads.
                let receiverMayBeCollection = resolveClassTypeSymbol(nonNullReceiverType, sema: sema)
                    .map { KnownCompilerNames(interner: interner).isCollectionLikeSymbol($0.symbol) }
                    ?? true
                // Abstract class properties have no usable declaration-local
                // field value. Resolve them through the class vtable before
                // collection shortcuts or the stored-field fallback below.
                if let propertySymbol = sema.bindings.identifierSymbols[exprID],
                   let (accessorSymbol, dispatch) = driver.callLowerer.tryResolvePropertyAccessorVirtualDispatch(
                       propertySymbol: propertySymbol,
                       receiverExpr: exprID,
                       accessorKind: .getter,
                       ast: ast,
                       sema: sema
                   )
                {
                    instructions.append(.virtualCall(
                        symbol: accessorSymbol,
                        callee: interner.intern("get"),
                        receiver: receiverExprID,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil,
                        dispatch: dispatch
                    ))
                    return result
                }

                // A user-declared member with a custom getter shadows the built-in
                // collection shortcuts below: `size` / `isEmpty` inside a class that
                // declares them must run its own getter, not kk_collection_size.
                let implicitMemberUsesAccessor: Bool = {
                    guard let symbol = sema.bindings.identifierSymbols[exprID],
                          let sym = sema.symbols.symbol(symbol),
                          sym.kind == .property,
                          let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                          let ownerKind = sema.symbols.symbol(ownerSymbol)?.kind,
                          ownerKind == .class || ownerKind == .interface
                    else {
                        return false
                    }
                    return driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema)
                }()

                if receiverMayBeCollection, memberStr == "size", !implicitMemberUsesAccessor {
                    emitNonThrowingCall(
                        callee: interner.intern("__kk_collection_size"),
                        arg: receiverExprID,
                        result: result,
                        into: &instructions
                    )
                    return result
                }
                if receiverMayBeCollection, memberStr == "isEmpty", !implicitMemberUsesAccessor {
                    emitNonThrowingCall(
                        callee: interner.intern("__kk_collection_isEmpty"),
                        arg: receiverExprID,
                        result: result,
                        into: &instructions
                    )
                    return result
                }

                // Some implicit member expressions carry their selected
                // property only in the call binding. Preserve the same
                // abstract/open class dispatch in that representation too.
                if let symbol = sema.bindings.identifierSymbols[exprID]
                    ?? sema.bindings.callBindings[exprID]?.chosenCallee,
                   let propertyInfo = sema.symbols.symbol(symbol),
                   propertyInfo.kind == .property,
                   propertyInfo.flags.contains(.abstractType)
                       || propertyInfo.flags.contains(.openType),
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerInfo = sema.symbols.symbol(ownerSymbol),
                   ownerInfo.kind == .class,
                   !sema.symbols.directSubtypes(of: ownerSymbol).isEmpty,
                   let getterSlot = sema.symbols.nominalLayout(for: ownerSymbol)?.vtableSlots[
                       SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                   ]
                {
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                    instructions.append(.virtualCall(
                        symbol: getterSymbol,
                        callee: interner.intern("get"),
                        receiver: receiverExprID,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil,
                        dispatch: .vtable(slot: getterSlot)
                    ))
                    return result
                }

                if let symbol = sema.bindings.identifierSymbols[exprID],
                   sema.bindings.isObjectLiteralPropertySymbol(symbol),
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[symbol]
                {
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [receiverExprID, offsetExpr],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return wrapLateinitReadIfNeeded(
                        result,
                        symbol: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                }

                // Native stub properties with externalLinkName: call native function
                // directly via the implicit receiver (e.g. kk_duration_inWholeNanoseconds
                // accessed inside a bundled Kotlin source extension getter body).
                if let symbol = sema.bindings.identifierSymbols[exprID],
                   let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property,
                   let externalLinkName = sema.symbols.externalLinkName(for: symbol),
                   !externalLinkName.isEmpty
                {
                    instructions.append(.call(
                        symbol: symbol,
                        callee: interner.intern(externalLinkName),
                        arguments: [receiverExprID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }

                if let symbol = sema.bindings.identifierSymbols[exprID],
                   let interfaceRead = driver.callLowerer.tryLowerInterfaceItablePropertyGetterRead(
                       propertySymbol: symbol,
                       loweredReceiverID: receiverExprID,
                       resultType: resultType,
                       sema: sema,
                       arena: arena,
                       interner: interner,
                       instructions: &instructions
                   )
                {
                    return interfaceRead
                }

                // KSP-928: implicit reads of abstract/open class properties
                // must dispatch through the class vtable. This is the path
                // used by AbstractMap's skeletal methods for `entries`.
                if let symbol = sema.bindings.identifierSymbols[exprID],
                   let propertyInfo = sema.symbols.symbol(symbol),
                   propertyInfo.kind == .property,
                   propertyInfo.flags.contains(.abstractType)
                       || propertyInfo.flags.contains(.openType),
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerInfo = sema.symbols.symbol(ownerSymbol),
                   ownerInfo.kind == .class,
                   !sema.symbols.directSubtypes(of: ownerSymbol).isEmpty,
                   let getterSlot = sema.symbols.nominalLayout(for: ownerSymbol)?.vtableSlots[
                       SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                   ]
                {
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                    instructions.append(.virtualCall(
                        symbol: getterSymbol,
                        callee: interner.intern("get"),
                        receiver: receiverExprID,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil,
                        dispatch: .vtable(slot: getterSlot)
                    ))
                    return result
                }

                // A custom getter must run for implicit-receiver reads just as
                // it does for an explicit `receiver.property` read.
                if let symbol = sema.bindings.identifierSymbols[exprID],
                   let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property,
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerKind = sema.symbols.symbol(ownerSymbol)?.kind,
                   ownerKind == .class || ownerKind == .interface,
                   driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema)
                {
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                    instructions.append(.call(
                        symbol: getterSymbol,
                        callee: interner.intern("get"),
                        arguments: [receiverExprID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }

                if let symbol = sema.bindings.identifierSymbols[exprID],
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerInfo = sema.symbols.symbol(ownerSymbol),
                   ownerInfo.kind == .class || ownerInfo.kind == .interface,
                   let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                       sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                   ]
                {
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [receiverExprID, offsetExpr],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return wrapLateinitReadIfNeeded(
                        result,
                        symbol: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                }

                // General fallback: try to find a getter symbol for the property
                if let symbol = sema.bindings.identifierSymbols[exprID],
                   !driver.ctx.isMutableCaptureBoxed(symbol)
                {
                    if let delegateValue = readLocalDelegateValue(
                        symbol: symbol, sema: sema, arena: arena, interner: interner,
                        instructions: &instructions
                    ) {
                        return delegateValue
                    }
                    if let localValue = driver.ctx.localValue(for: symbol) {
                        return localValue
                    }
                }
            }
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                if driver.ctx.isMutableCaptureBoxed(symbol),
                   let loadedValue = loadMutableCaptureCellValue(
                       symbol: symbol,
                       resultType: {
                           driver.ctx.localDeclaredType(for: symbol)
                               ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                       }(),
                       sema: sema,
                       arena: arena,
                       interner: interner,
                       instructions: &instructions
                   )
                {
                    return loadedValue
                }
                if let delegateValue = readLocalDelegateValue(
                    symbol: symbol, sema: sema, arena: arena, interner: interner,
                    instructions: &instructions
                ) {
                    return delegateValue
                }
                if let localValue = driver.ctx.localValue(for: symbol) {
                    return localValue
                }
                // Inline constant initializers only for immutable (val) properties.
                // Mutable (var) properties must always load from global store at runtime.
                if let symInfo = sema.symbols.symbol(symbol),
                   let constant = propertyConstantInitializers[symbol] ?? sema.symbols.constValueExprKind(for: symbol),
                   !symInfo.flags.contains(.mutable)
                {
                    let id = arena.appendExpr(constant, type: boundType)
                    instructions.append(.constValue(result: id, value: constant))
                    return id
                }
                // Synthetic top-level properties backed by a runtime bridge
                // have no global storage. Emit their zero-argument bridge
                // before the ordinary top-level property load path (for
                // example, the bare kotlinx.coroutines.isActive property).
                if let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property,
                   sema.symbols.extensionPropertyReceiverType(for: symbol) == nil,
                   let externalLinkName = sema.symbols.externalLinkName(for: symbol),
                   !externalLinkName.isEmpty
                {
                    let resultType = boundType
                        ?? sema.symbols.propertyType(for: symbol)
                        ?? sema.types.anyType
                    let result = arena.appendTemporary(type: resultType)
                    instructions.append(.call(
                        symbol: symbol,
                        callee: interner.intern(externalLinkName),
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                // Native stub properties with externalLinkName: call native function
                // directly via the implicit receiver, bypassing field-offset dispatch.
                // (e.g. kk_duration_inWholeNanoseconds accessed inside a bundled
                // Kotlin source extension getter body.)
                if let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property,
                   let externalLinkName = sema.symbols.externalLinkName(for: symbol),
                   !externalLinkName.isEmpty,
                   let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
                {
                    let resultType = boundType
                        ?? sema.symbols.propertyType(for: symbol)
                        ?? sema.types.anyType
                    let result = arena.appendTemporary(type: resultType)
                    instructions.append(.call(
                        symbol: symbol,
                        callee: interner.intern(externalLinkName),
                        arguments: [receiverExprID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                // Member property references inside class/object bodies must read
                // from the current implicit receiver instance rather than treating
                // the property symbol as a standalone value.
                //
                // Getter-only properties (`val size: Int get() = ...`) still occupy a
                // layout slot keyed by the property symbol, but that slot is never
                // written, so reading it here would yield garbage. Those dispatch to
                // the getter accessor in the branch below, matching the explicit
                // `this.size` path in CallLowerer+MemberPropertyReads.swift.
                if let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property || sym.kind == .field || sym.kind == .backingField,
                   let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerKind = sema.symbols.symbol(ownerSymbol)?.kind,
                   ownerKind == .class || ownerKind == .interface,
                   sym.kind != .property
                       || sema.symbols.backingFieldSymbol(for: symbol) != nil
                       || !driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema),
                   let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                       sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                   ]
                {
                    let resultType = boundType
                        ?? sema.symbols.propertyType(for: symbol)
                        ?? sema.types.anyType
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    let result = arena.appendTemporary(type: resultType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [receiverExprID, offsetExpr],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return wrapLateinitReadIfNeeded(
                        result,
                        symbol: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                }
                // No direct field offset (the property has a distinct backing
                // field because it declares a custom accessor): dispatch to
                // the getter accessor when a real `get() { ... }` body exists
                // (mirrors CallLowerer+MemberPropertyReads.swift's explicit-
                // receiver equivalent), otherwise fall back to reading the
                // backing field's own storage directly, since the compiler-
                // provided default getter is just `return field` — the same
                // backing-field global that MemberLowerer+
                // DelegatedAndAccessorLowering.swift's lowerAccessorBody
                // resolves through the active receiver's instance layout.
                if let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property,
                   let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerKind = sema.symbols.symbol(ownerSymbol)?.kind,
                   ownerKind == .class,
                   !sema.symbols.directSubtypes(of: ownerSymbol).isEmpty
                {
                    let resultType = boundType
                        ?? sema.symbols.propertyType(for: symbol)
                        ?? sema.types.anyType
                    if let interfaceRead = driver.callLowerer.tryLowerInterfaceItablePropertyGetterRead(
                        propertySymbol: symbol,
                        loweredReceiverID: receiverExprID,
                        resultType: resultType,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    ) {
                        return interfaceRead
                    }
                    // KSP-928: the abstract `entries` property in
                    // AbstractMap is resolved from an implicit receiver in
                    // its base-class methods, so use the subclass vtable
                    // entry instead of the generated abstract getter stub.
                    if let propertyInfo = sema.symbols.symbol(symbol),
                       propertyInfo.flags.contains(.abstractType)
                           || propertyInfo.flags.contains(.openType),
                       let getterSlot = sema.symbols.nominalLayout(for: ownerSymbol)?.vtableSlots[
                           SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                       ]
                    {
                        let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                            ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                        let result = arena.appendTemporary(type: resultType)
                        instructions.append(.virtualCall(
                            symbol: getterSymbol,
                            callee: interner.intern("get"),
                            receiver: receiverExprID,
                            arguments: [],
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            dispatch: .vtable(slot: getterSlot)
                        ))
                        return result
                    }
                    if driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema) {
                        let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                            ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                        let result = arena.appendTemporary(type: resultType)
                        instructions.append(.call(
                            symbol: getterSymbol,
                            callee: interner.intern("get"),
                            arguments: [receiverExprID],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        return result
                    }
                    if let backingFieldSym = sema.symbols.backingFieldSymbol(for: symbol) {
                        let id = arena.appendExpr(.symbolRef(backingFieldSym), type: resultType)
                        instructions.append(.loadGlobal(result: id, symbol: backingFieldSym))
                        return wrapLateinitReadIfNeeded(
                            id,
                            symbol: symbol,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                    }
                }
                // Imported top-level properties with a custom getter have no
                // global slot in the producing artifact; their reads dispatch
                // to the precompiled getter accessor instead.
                if let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property,
                   sym.flags.contains(.importedLibrary),
                   sema.symbols.propertyHasCustomGetter(for: symbol),
                   sema.symbols.extensionPropertyReceiverType(for: symbol) == nil,
                   let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol),
                   {
                       let parentKind = sema.symbols.parentSymbol(for: symbol)
                           .flatMap { sema.symbols.symbol($0) }?.kind
                       return parentKind == nil || parentKind == .package
                   }()
                {
                    let resultType = boundType
                        ?? sema.symbols.propertyType(for: symbol)
                        ?? sema.types.anyType
                    let result = arena.appendTemporary(type: resultType)
                    instructions.append(.call(
                        symbol: getterSymbol,
                        callee: interner.intern("get"),
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                // For top-level or object-member property symbols, emit loadGlobal so the
                // backend reads the current value from the global slot.
                if let sym = sema.symbols.symbol(symbol),
                   sym.kind == .property || sym.kind == .field,
                   {
                       let p = sema.symbols.parentSymbol(for: symbol)
                       let pk = p.flatMap { sema.symbols.symbol($0) }?.kind
                       return pk == nil || pk == .package || pk == .object
                   }()
                {
                    let id = arena.appendExpr(.symbolRef(symbol), type: boundType)
                    instructions.append(.loadGlobal(result: id, symbol: symbol))
                    return wrapLateinitReadIfNeeded(
                        id,
                        symbol: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                }
                // Synthetic singleton objects with an externalLinkName (e.g.
                // kotlinx.coroutines.NonCancellable) resolve to a runtime handle via a
                // direct zero-argument call, bypassing the eager module-init allocation
                // used for real `object` declarations (which real objects need for their
                // own stored state, but a synthetic native-backed singleton doesn't).
                if let sym = sema.symbols.symbol(symbol),
                   sym.kind == .object,
                   let externalLinkName = sema.symbols.externalLinkName(for: symbol),
                   !externalLinkName.isEmpty
                {
                    let resultType = boundType ?? sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let result = arena.appendTemporary(type: resultType)
                    instructions.append(.call(
                        symbol: symbol,
                        callee: interner.intern(externalLinkName),
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let id = arena.appendExpr(.symbolRef(symbol), type: boundType)
                instructions.append(.constValue(result: id, value: .symbolRef(symbol)))
                return id
            }
            let id = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: id, value: .unit))
            return id

        case let .forExpr(_, iterableExpr, bodyExpr, label, _):
            return driver.controlFlowLowerer.lowerForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .whileExpr(conditionExpr, bodyExpr, label, _):
            return driver.controlFlowLowerer.lowerWhileExpr(
                exprID,
                conditionExpr: conditionExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .doWhileExpr(bodyExpr, conditionExpr, label, _):
            return driver.controlFlowLowerer.lowerDoWhileExpr(
                exprID,
                bodyExpr: bodyExpr,
                conditionExpr: conditionExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .breakExpr(label, _):
            // CODE-001: Inline only finally blocks whose try scope is exited
            // by this break.  If the loop is nested inside a try body,
            // break stays within the try scope and should not trigger finally.
            inlineFinallyBlocksForBreakOrContinue(
                label: label,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let targetLabel: Int32? = if let label {
                driver.ctx.breakLabel(for: label)
            } else {
                driver.ctx.breakLabel(for: nil)
            }
            if let targetLabel {
                instructions.append(.jump(targetLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .continueExpr(label, _):
            // CODE-001: Inline only finally blocks whose try scope is exited
            // by this continue.
            inlineFinallyBlocksForBreakOrContinue(
                label: label,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let targetLabel: Int32? = if let label {
                driver.ctx.continueLabel(for: label)
            } else {
                driver.ctx.continueLabel(for: nil)
            }
            if let targetLabel {
                instructions.append(.jump(targetLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .localFunDecl(localFunName, localFunValueParams, _, localFunBody, _, _):
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                let sig = sema.symbols.functionSignature(for: symbol)
                let funType: TypeID = if let sig {
                    sema.types.make(.functionType(FunctionType(
                        params: sig.parameterTypes,
                        returnType: sig.returnType,
                        isSuspend: sig.isSuspend,
                        nullability: .nonNull
                    )))
                } else {
                    boundType ?? sema.types.anyType
                }
                let funRef = arena.appendExpr(.symbolRef(symbol), type: funType)
                instructions.append(.constValue(result: funRef, value: .symbolRef(symbol)))
                driver.ctx.setLocalValue(funRef, for: symbol)

                let localFunCalleeName = driver.lambdaLowerer.callableTargetName(for: symbol, sema: sema, interner: interner)

                // Emit the local function body as a KIRFunction declaration.
                let localFunValueParamList: [KIRParameter]
                let localFunReturnType: TypeID
                if let sig {
                    localFunValueParamList = zip(sig.valueParameterSymbols, sig.parameterTypes).map { pair in
                        KIRParameter(symbol: pair.0, type: pair.1)
                    }
                    localFunReturnType = sig.returnType
                } else {
                    localFunValueParamList = localFunValueParams.indices.map { index in
                        KIRParameter(
                            symbol: driver.lambdaLowerer.syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                            type: sema.types.anyType
                        )
                    }
                    localFunReturnType = sema.types.unitType
                }

                // Compute capture symbols by collecting referenced identifiers
                // from the local function body, filtering to those available in
                // the current scope (analogous to lambda capture analysis).
                var captureBodyExprIDs: [ExprID] = []
                switch localFunBody {
                case let .block(bodyExprIDs, _):
                    captureBodyExprIDs = bodyExprIDs
                case let .expr(bodyExprID, _):
                    captureBodyExprIDs = [bodyExprID]
                case .unit:
                    break
                }

                var referencedSymbols: [SymbolID] = []
                var seenSymbols: Set<SymbolID> = []
                for bodyExprID in captureBodyExprIDs {
                    driver.lambdaLowerer.collectBoundIdentifierSymbols(
                        in: bodyExprID,
                        ast: ast,
                        sema: sema,
                        referenced: &referencedSymbols,
                        seen: &seenSymbols
                    )
                }
                let localFunParamSymbols = Set(localFunValueParamList.map(\.symbol))
                var captureSymbols = referencedSymbols.filter { sym in
                    if localFunParamSymbols.contains(sym) { return false }
                    if sym == symbol { return false }
                    if driver.ctx.localDelegateStorage(for: sym) != nil { return true }
                    if driver.ctx.localValue(for: sym) != nil { return true }
                    if sym == driver.ctx.activeImplicitReceiverSymbol(),
                       driver.ctx.activeImplicitReceiverExprID() != nil { return true }
                    guard let semanticSymbol = sema.symbols.symbol(sym) else { return false }
                    return semanticSymbol.kind == .valueParameter
                }

                // Implicit receiver (this/super) is not collected by
                // collectBoundIdentifierSymbols, so check separately —
                // mirrors the post-filter in lexicalCaptureSymbolsForLambda.
                if let receiverSymbol = driver.ctx.activeImplicitReceiverSymbol(),
                   driver.ctx.activeImplicitReceiverExprID() != nil,
                   !captureSymbols.contains(receiverSymbol)
                {
                    let needsReceiver = captureBodyExprIDs.contains { bodyExprID in
                        driver.lambdaLowerer.containsImplicitReceiverReference(in: bodyExprID, ast: ast)
                    }
                    if needsReceiver {
                        captureSymbols.append(receiverSymbol)
                    }
                }

                // Transitive capture: if a captured symbol is a callable with
                // its own captures, also capture those dependencies so call
                // sites inside the body can forward correct capture arguments.
                // Build a deterministic reverse map (KIRExprID → SymbolID) from
                // current local bindings so we avoid nondeterministic Dictionary
                // iteration with first(where:).
                var exprIDToSymbol: [KIRExprID: SymbolID] = [:]
                for (sym, expr) in driver.ctx.allLocalValues() {
                    exprIDToSymbol[expr] = sym
                }
                var transitiveChanged = true
                while transitiveChanged {
                    transitiveChanged = false
                    for sym in captureSymbols {
                        guard let outerExpr = driver.ctx.localValue(for: sym),
                              let callableInfo = driver.ctx.callableValueInfo(for: outerExpr)
                        else {
                            continue
                        }
                        for captureArg in callableInfo.captureArguments {
                            var transitiveSym: SymbolID?
                            if let found = exprIDToSymbol[captureArg] {
                                transitiveSym = found
                            } else if case let .symbolRef(argSym) = arena.expr(captureArg) {
                                transitiveSym = argSym
                            } else if captureArg == driver.ctx.activeImplicitReceiverExprID() {
                                transitiveSym = driver.ctx.activeImplicitReceiverSymbol()
                            }
                            if let transitiveSym, !captureSymbols.contains(transitiveSym) {
                                captureSymbols.append(transitiveSym)
                                transitiveChanged = true
                            }
                        }
                    }
                }

                var captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID)] = []
                captureBindings.reserveCapacity(captureSymbols.count)
                for (index, capturedSymbol) in captureSymbols.enumerated() {
                    let declaredType = driver.ctx.localDeclaredType(for: capturedSymbol)
                        ?? driver.ctx.localValue(for: capturedSymbol).flatMap { arena.exprType($0) }
                        ?? driver.lambdaLowerer.typeForSymbolReference(capturedSymbol, sema: sema)
                    if let semanticSymbol = sema.symbols.symbol(capturedSymbol),
                       semanticSymbol.kind == .local,
                       semanticSymbol.flags.contains(.mutable)
                    {
                        _ = ensureMutableCaptureCell(
                            for: capturedSymbol,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                    }
                    guard let captureValue = driver.lambdaLowerer.captureValueExpr(
                        for: capturedSymbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    ) else {
                        continue
                    }
                    let captureType = arena.exprType(captureValue) ?? driver.lambdaLowerer.typeForSymbolReference(capturedSymbol, sema: sema)
                    let captureParamSymbol = driver.lambdaLowerer.syntheticLambdaCaptureParamSymbol(
                        lambdaExprID: exprID,
                        captureIndex: index
                    )
                    let captureParam = KIRParameter(symbol: captureParamSymbol, type: captureType)
                    captureBindings.append((
                        capturedSymbol: capturedSymbol,
                        param: captureParam,
                        valueExpr: captureValue,
                        declaredType: declaredType
                    ))
                }

                driver.ctx.registerCallableValue(
                    funRef,
                    symbol: symbol,
                    callee: localFunCalleeName,
                    captureArguments: captureBindings.map(\.valueExpr)
                )

                let scopeSnapshot = driver.ctx.saveScope()
                let boxedCaptureSymbols = Set(
                    captureBindings.compactMap { binding in
                        driver.ctx.isMutableCaptureBoxed(binding.capturedSymbol) ? binding.capturedSymbol : nil
                    }
                )
                let savedReceiverSymbol = scopeSnapshot.currentImplicitReceiverSymbol
                defer { driver.ctx.restoreScope(scopeSnapshot) }
                driver.ctx.resetScopeForFunction()

                var localFunBodyInstructions: [KIRInstruction] = [.beginBlock]

                // Bind capture parameters so body references resolve correctly.
                for capture in captureBindings {
                    let captureExpr = arena.appendExpr(.symbolRef(capture.param.symbol), type: capture.param.type)
                    localFunBodyInstructions.append(.constValue(result: captureExpr, value: .symbolRef(capture.param.symbol)))
                    if sema.symbols.delegateGetValueSymbol(for: capture.capturedSymbol) != nil {
                        driver.ctx.setLocalDelegateStorage(captureExpr, for: capture.capturedSymbol)
                    } else if boxedCaptureSymbols.contains(capture.capturedSymbol) {
                        driver.ctx.setMutableCaptureCell(captureExpr, for: capture.capturedSymbol)
                    } else {
                        driver.ctx.setLocalValue(captureExpr, for: capture.capturedSymbol)
                    }
                    driver.ctx.setLocalDeclaredType(capture.declaredType, for: capture.capturedSymbol)
                    if capture.capturedSymbol == savedReceiverSymbol {
                        driver.ctx.setImplicitReceiver(symbol: capture.param.symbol, exprID: captureExpr)
                    }
                }

                for param in localFunValueParamList {
                    let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
                    localFunBodyInstructions.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
                    driver.ctx.setLocalValue(paramExpr, for: param.symbol)
                }

                // Propagate callable value info for captured callables so that
                // calls inside the body find correct capture arguments.
                // Build a direct outer-expr → body-expr mapping from capture
                // bindings. This works for any expression kind (symbolRef,
                // intLiteral, etc.) without needing reverse lookups.
                var outerExprToBodyExpr: [KIRExprID: KIRExprID] = [:]
                for capture in captureBindings {
                    if let bodyExpr = driver.ctx.localValue(for: capture.capturedSymbol) {
                        outerExprToBodyExpr[capture.valueExpr] = bodyExpr
                    }
                }
                for capture in captureBindings {
                    if let outerCallableInfo = driver.ctx.callableValueInfo(for: capture.valueExpr),
                       let bodyCallableExpr = driver.ctx.localValue(for: capture.capturedSymbol)
                    {
                        var remappedArgs: [KIRExprID] = []
                        var mappingFailed = false
                        for argExpr in outerCallableInfo.captureArguments {
                            if let bodyArgExpr = outerExprToBodyExpr[argExpr] {
                                remappedArgs.append(bodyArgExpr)
                            } else if case let .symbolRef(argSym) = arena.expr(argExpr),
                                      let bodyArgExpr = driver.ctx.localValue(for: argSym)
                            {
                                remappedArgs.append(bodyArgExpr)
                            } else {
                                assertionFailure("BuildKIRPhase: failed to remap capture argument for local function body")
                                mappingFailed = true
                                break
                            }
                        }
                        if !mappingFailed {
                            driver.ctx.registerCallableValue(
                                bodyCallableExpr,
                                symbol: outerCallableInfo.symbol,
                                callee: outerCallableInfo.callee,
                                captureArguments: remappedArgs
                            )
                        }
                    }
                }

                // Re-register the local function symbol inside its own body
                // so that recursive calls resolve correctly with capture arguments.
                // Inside the body, capture arguments reference the capture *parameters*
                // (not the outer values) since we're in the body's scope.
                let bodyFunRef = arena.appendExpr(.symbolRef(symbol), type: funType)
                localFunBodyInstructions.append(.constValue(result: bodyFunRef, value: .symbolRef(symbol)))
                driver.ctx.setLocalValue(bodyFunRef, for: symbol)
                let recursiveCaptureArguments: [KIRExprID] = captureBindings.map { binding in
                    guard let value = driver.ctx.localValue(for: binding.capturedSymbol)
                        ?? driver.ctx.localDelegateStorage(for: binding.capturedSymbol)
                    else {
                        preconditionFailure("BuildKIRPhase: missing capture binding for recursive local function '\(symbol)'")
                    }
                    return value
                }
                driver.ctx.registerCallableValue(
                    bodyFunRef,
                    symbol: symbol,
                    callee: localFunCalleeName,
                    captureArguments: recursiveCaptureArguments
                )

                switch localFunBody {
                case let .block(bodyExprIDs, _):
                    var lastValue: KIRExprID?
                    var terminatedByReturn = false
                    for bodyExprID in bodyExprIDs {
                        if let bodyExpr = ast.arena.expr(bodyExprID),
                           case let .returnExpr(value, _, _) = bodyExpr
                        {
                            if let value {
                                let lowered = lowerExpr(
                                    value,
                                    ast: ast,
                                    sema: sema,
                                    arena: arena,
                                    interner: interner,
                                    propertyConstantInitializers: propertyConstantInitializers,
                                    instructions: &localFunBodyInstructions
                                )
                                localFunBodyInstructions.append(.returnValue(lowered))
                            } else {
                                localFunBodyInstructions.append(.returnUnit)
                            }
                            terminatedByReturn = true
                            break
                        }
                        if let bodyExpr = ast.arena.expr(bodyExprID),
                           case .throwExpr = bodyExpr
                        {
                            _ = lowerExpr(
                                bodyExprID,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &localFunBodyInstructions
                            )
                            terminatedByReturn = true
                            break
                        }
                        lastValue = lowerExpr(
                            bodyExprID,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            propertyConstantInitializers: propertyConstantInitializers,
                            instructions: &localFunBodyInstructions
                        )
                        // Detect nested termination (e.g., if/when/try with return in all branches)
                        if let lastValue, driver.controlFlowLowerer.isTerminatedExpr(lastValue, arena: arena, sema: sema) {
                            terminatedByReturn = true
                            break
                        }
                    }
                    if !terminatedByReturn {
                        if let lastValue {
                            localFunBodyInstructions.append(.returnValue(lastValue))
                        } else {
                            localFunBodyInstructions.append(.returnUnit)
                        }
                    }
                case let .expr(bodyExprID, _):
                    let value = lowerExpr(
                        bodyExprID,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &localFunBodyInstructions
                    )
                    localFunBodyInstructions.append(.returnValue(value))
                case .unit:
                    localFunBodyInstructions.append(.returnUnit)
                }
                localFunBodyInstructions.append(.endBlock)

                let localFunDeclID = arena.appendDecl(
                    .function(
                        KIRFunction(
                            symbol: symbol,
                            name: localFunName,
                            params: captureBindings.map(\.param) + localFunValueParamList,
                            returnType: localFunReturnType,
                            body: localFunBodyInstructions,
                            isSuspend: sig?.isSuspend ?? false,
                            isInline: false
                        )
                    )
                )
                driver.ctx.appendGeneratedCallableDecl(localFunDeclID)
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .localDecl(_, isMutable, _, initializer, isDelegated, _):
            if let initializer {
                let initializerID = lowerExpr(
                    initializer,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                if let symbol = sema.bindings.identifierSymbols[exprID] {
                    // Local delegated declaration (custom and, since KSP-491, the
                    // stdlib factories lazy/Delegates.observable/vetoable/notNull
                    // alike -- they all resolve getValue/setValue through the same
                    // operator convention now). `initializer`'s own AST shape here
                    // (unlike a member/top-level PropertyDecl's `delegateExpression`)
                    // already includes any trailing lambda as a normal call
                    // argument, so `lowerExpr` above already invoked the real
                    // factory correctly.
                    let isCustomDelegateDecl = isDelegated
                        && sema.symbols.delegateGetValueSymbol(for: symbol) != nil
                    if isCustomDelegateDecl {
                        // Local delegate declaration (custom, and since KSP-491 the
                        // stdlib factories lazy/Delegates.observable/vetoable/notNull
                        // alike): binds `x`'s storage to the delegate *instance*
                        // (`Prop()`/`LazyImpl(...)`/...), not its value -- unlike a
                        // plain local, `x`'s getValue runs at each *read* site (see
                        // below), not here, which is what keeps `val x by lazy { ... }`'s
                        // initializer deferred until `x` is first read (BUG-014 /
                        // KSP-CAP-007's fix for the read side predates this; this
                        // declaration-site half only resolves the delegate object).
                        //
                        // provideDelegate (BUG-146): when the delegate exposes a
                        // `provideDelegate` operator, the *effective* delegate is
                        // its return value, mirroring member/top-level lowering in
                        // KIRLoweringDriver+ProvideDelegate.swift. Call
                        // `Factory().provideDelegate(null, KProperty("x"))` first and
                        // resolve getValue/setValue against that result (Sema already
                        // recorded getValue/setValue for the effective delegate type
                        // via DeclTypeChecker.typeCheckDelegate).
                        let effectiveDelegateID = lowerLocalProvideDelegateIfNeeded(
                            symbol: symbol,
                            rawDelegateID: initializerID,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        driver.ctx.setLocalDelegateStorage(effectiveDelegateID, for: symbol)
                        let propertyType = sema.symbols.propertyType(for: symbol)
                            ?? arena.exprType(effectiveDelegateID)
                            ?? sema.types.anyType
                        driver.ctx.setLocalDeclaredType(propertyType, for: symbol)
                    } else {
                        let initializerType = arena.exprType(initializerID)
                        // Prefer the symbol's Sema-recorded declared type over the
                        // initializer's own type: an explicit widening annotation
                        // (e.g. `val x: Any = 42L`) records `Any` on the symbol while
                        // the literal's own arena type stays `Long`. Falling back to
                        // the initializer's type here would silently drop the
                        // widening, leaving the local aliased to an unboxed literal
                        // register.
                        let declaredType = (isDelegated ? nil : sema.symbols.propertyType(for: symbol))
                            ?? initializerType
                            ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                        driver.ctx.setLocalDeclaredType(declaredType, for: symbol)
                        // Reference-like declared locals need a slot typed to the
                        // declaration rather than an alias to the initializer. This
                        // keeps later assignments (e.g. String -> Int in Any) in the
                        // same erased storage and lets ABILoweringPass apply the
                        // correct boxing at each copy. Primitive destinations are
                        // intentionally excluded: nullable primitive locals use a
                        // distinct sentinel representation and must keep their
                        // existing coercion path.
                        let declaredTypeIsReferenceLike: Bool = switch sema.types.kind(of: declaredType) {
                        case .any, .classType, .functionType, .typeParam:
                            true
                        default:
                            false
                        }
                        // A mutable local initialized directly from a bare symbol
                        // reference (an enum entry or object singleton, e.g. `var d:
                        // Direction = Direction.NORTH`) must not alias its storage to
                        // that exact expression. `arena.expr` never changes once
                        // recorded, so a later reassignment (`d = Direction.SOUTH`)
                        // only patches the runtime bits in place via `.copy` — any
                        // fold that pattern-matches the storage's static `.symbolRef`
                        // shape (e.g. enum `.name`/`.ordinal` constant-folding in
                        // tryLowerEnumEntryPropertyRead) would keep resolving to the
                        // *initial* entry forever, regardless of the reassignment.
                        let initializerIsBareSymbolRef: Bool = {
                            if case .symbolRef = arena.expr(initializerID) { return true }
                            return false
                        }()
                        let requiresFreshSlotForMutableAlias = isMutable
                            && declaredTypeIsReferenceLike
                            && initializerIsBareSymbolRef
                        if !isDelegated, declaredTypeIsReferenceLike,
                           (initializerType != nil && initializerType != declaredType)
                           || requiresFreshSlotForMutableAlias
                        {
                            let localSlot = arena.appendTemporary(type: declaredType)
                            instructions.append(.copy(from: initializerID, to: localSlot))
                            driver.ctx.setLocalValue(localSlot, for: symbol)
                            if let callableInfo = driver.ctx.callableValueInfo(for: initializerID) {
                                driver.ctx.callableValueInfoByExprID[localSlot] = callableInfo
                            }
                        } else if !isDelegated, isBareVariableRead(initializer, ast: ast) {
                            // `val a = b` must snapshot `b`'s current value. Binding the
                            // new local directly to the initializer register would alias
                            // the two, so a later in-place update of `b` (`b += 1`, which
                            // copies into the same register) would retroactively change
                            // `a` as well.
                            let localSlot = arena.appendTemporary(type: declaredType)
                            instructions.append(.copy(from: initializerID, to: localSlot))
                            driver.ctx.setLocalValue(localSlot, for: symbol)
                            if let callableInfo = driver.ctx.callableValueInfo(for: initializerID) {
                                driver.ctx.callableValueInfoByExprID[localSlot] = callableInfo
                            }
                        } else {
                            driver.ctx.setLocalValue(initializerID, for: symbol)
                        }
                    }
                }
            } else if let symbol = sema.bindings.identifierSymbols[exprID] {
                let declaredType = driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                driver.ctx.setLocalDeclaredType(declaredType, for: symbol)
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .localAssign(_, valueExpr, _):
            let valueID = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                // Check if this is a top-level or object-member property assignment.
                // These need a copy to global storage rather than just updating
                // localValuesBySymbol (which wouldn't persist across function calls).
                // Top-level properties have nil or .package parent.
                // Object member properties have .object parent.
                if let delegateStorageID = driver.ctx.localDelegateStorage(for: symbol),
                   let setValueSymbol = sema.symbols.delegateSetValueSymbol(for: symbol)
                {
                    // Local delegated `var` (BUG-014 / KSP-CAP-007 / BUG-052): `x = value`
                    // calls `Prop().setValue(null, KProperty("x"), value)`, mirroring
                    // the getValue call synthesized at the declaration in the
                    // `.localDecl` case, instead of overwriting x's storage register.
                    let setterArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
                        localSymbol: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    let setResultExprID = arena.appendTemporary(type: sema.types.unitType)
                    instructions.append(driver.memberLowerer.dispatchedDelegateMemberCall(
                        symbol: setValueSymbol,
                        callee: interner.intern("setValue"),
                        receiver: delegateStorageID,
                        extraArguments: setterArgs + [valueID],
                        result: setResultExprID,
                        sema: sema,
                        interner: interner
                    ))
                    // Reads always dispatch a fresh getValue (see
                    // readLocalDelegateValue) rather than caching, so a
                    // vetoable-style delegate rejecting this write is
                    // observed correctly with no extra bookkeeping here.
                } else if let symInfo = sema.symbols.symbol(symbol), symInfo.kind == .property || symInfo.kind == .field, {
                    let p = sema.symbols.parentSymbol(for: symbol)
                    let pk = p.flatMap { sema.symbols.symbol($0) }?.kind
                    return pk == nil || pk == .package || pk == .object
                }() {
                    let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
                    instructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
                    instructions.append(.copy(from: valueID, to: globalRef))
                } else if storeMutableCaptureCellValue(
                    valueID,
                    for: symbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ) {
                } else if let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
                          let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                          let ownerInfo = sema.symbols.symbol(ownerSymbol),
                          ownerInfo.kind == .class || ownerInfo.kind == .interface,
                          !(
                              sema.symbols.symbol(symbol)?.kind == .property
                                  && driver.callLowerer.memberPropertyUsesSetterAccessor(symbol, ast: ast, sema: sema)
                          ),
                          let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                              sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                          ]
                {
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_set"),
                        arguments: [receiverExprID, offsetExpr, valueID],
                        result: nil,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else if let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
                          let symInfo = sema.symbols.symbol(symbol),
                          symInfo.kind == .property,
                          let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                          let ownerInfo = sema.symbols.symbol(ownerSymbol),
                          ownerInfo.kind == .class || ownerInfo.kind == .interface
                {
                    // No direct field offset (the property has a distinct
                    // backing field because it declares a custom accessor):
                    // this bare-name write must not be treated as a plain
                    // local variable. If a real `set(...)` body exists,
                    // dispatch to the setter accessor directly (mirrors
                    // CallLowerer+MemberPropertyReads.swift's getter dispatch
                    // for the analogous read side). Otherwise the setter is
                    // the compiler-provided default (`field = value`), so
                    // write straight to the backing field's own storage —
                    // the same backing-field global that MemberLowerer+
                    // DelegatedAndAccessorLowering.swift's lowerAccessorBody
                    // resolves through the active receiver's instance layout.
                    // (`.object` is deliberately excluded: the branch above
                    // already routes every object-member property through
                    // global-copy storage before reaching here.)
                    if driver.callLowerer.memberPropertyUsesSetterAccessor(symbol, ast: ast, sema: sema) {
                        let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: symbol)
                            ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol)
                        instructions.append(.call(
                            symbol: setterSymbol,
                            callee: interner.intern("set"),
                            arguments: [receiverExprID, valueID],
                            result: nil,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    } else if let backingFieldSym = sema.symbols.backingFieldSymbol(for: symbol) {
                        // Deliberately `.storeGlobal`, not `.copy(to: .symbolRef(...))`:
                        // PropertyLoweringPass rewrites any `.copy` targeting a
                        // `.backingField`-kind symbolRef into a setter-accessor
                        // call, which would misfire here since no setter
                        // accessor function was emitted for this property.
                        instructions.append(.storeGlobal(value: valueID, symbol: backingFieldSym))
                    } else if let storageID = driver.ctx.localValue(for: symbol) {
                        // Neither a real setter nor a backing field exists (e.g. an
                        // abstract property with no accessor of its own): fall back
                        // to the same treatment as the outer `else` below rather than
                        // silently dropping the write, since this `else if` already
                        // claimed the assignment and nothing after it will run.
                        instructions.append(.copy(from: valueID, to: storageID))
                    } else {
                        driver.ctx.setLocalValue(valueID, for: symbol)
                    }
                } else {
                    if let storageID = driver.ctx.localValue(for: symbol) {
                        // Mutable local already has storage: emit a copy so the C variable
                        // is updated in place, preserving the value across loop iterations.
                        instructions.append(.copy(from: valueID, to: storageID))
                        // Reassigning a callable-typed local to a different lambda/function
                        // reference must overwrite storageID's callableValueInfo too, or a
                        // later call through this local would still invoke the previous value.
                        if let callableInfo = driver.ctx.callableValueInfo(for: valueID) {
                            driver.ctx.callableValueInfoByExprID[storageID] = callableInfo
                        } else {
                            driver.ctx.callableValueInfoByExprID.removeValue(forKey: storageID)
                        }
                    } else {
                        driver.ctx.setLocalValue(valueID, for: symbol)
                    }
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .memberAssign(receiverExpr, calleeName, valueExpr, _):
            return driver.callLowerer.lowerMemberAssignExpr(
                exprID,
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .indexedAccess(receiverExpr, indices, _):
            return driver.callLowerer.lowerIndexedAccessExpr(
                exprID,
                receiverExpr: receiverExpr,
                indices: indices,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .indexedAssign(receiverExpr, indices, valueExpr, _):
            return driver.callLowerer.lowerIndexedAssignExpr(
                exprID,
                receiverExpr: receiverExpr,
                indices: indices,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .returnExpr(value, label, _):
            if let value {
                let lowered = lowerExpr(
                    value,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                // CODE-001: Inline all enclosing finally blocks before return.
                inlineAllEnclosingFinallyBlocks(
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                if label == nil, driver.ctx.currentLambdaAllowsNonLocalReturn {
                    instructions.append(.nonLocalReturn(lowered))
                } else {
                    instructions.append(.returnValue(lowered))
                }
            } else {
                // CODE-001: Inline all enclosing finally blocks before return.
                inlineAllEnclosingFinallyBlocks(
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                if label == nil, driver.ctx.currentLambdaAllowsNonLocalReturn {
                    instructions.append(.nonLocalReturn(nil))
                } else {
                    instructions.append(.returnUnit)
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .ifExpr(condition, thenExpr, elseExpr, _):
            return driver.controlFlowLowerer.lowerIfExpr(
                exprID,
                condition: condition,
                thenExpr: thenExpr,
                elseExpr: elseExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .tryExpr(bodyExpr, catchClauses, finallyExpr, _):
            return driver.controlFlowLowerer.lowerTryExpr(
                exprID,
                bodyExpr: bodyExpr,
                catchClauses: catchClauses,
                finallyExpr: finallyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .binary(op, lhs, rhs, _):
            return driver.callLowerer.lowerBinaryExpr(
                exprID,
                op: op,
                lhs: lhs,
                rhs: rhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .call(calleeExpr, _, args, _):
            return driver.callLowerer.lowerCallExpr(
                exprID,
                calleeExpr: calleeExpr,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .memberCall(receiverExpr, calleeName, _, args, _):
            return driver.callLowerer.lowerMemberCallExpr(
                exprID,
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .unaryExpr(op, operandExpr, _):
            if let callBinding = sema.bindings.callBindings[exprID],
               let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
               signature.receiverType != nil
            {
                return driver.callLowerer.lowerMemberCallExpr(
                    exprID,
                    receiverExpr: operandExpr,
                    calleeName: interner.intern(op.kotlinFunctionName),
                    args: [],
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let operandID = lowerExpr(
                operandExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            switch op {
            case .unaryPlus:
                return operandID
            case .unaryMinus:
                // IEEE floating-point negation must flip the sign bit so that
                // `-(0.0) == -0.0`. Lowering it as `0.0 - x` is wrong because
                // `0.0 - 0.0 == +0.0`. Use `x * -1.0`, which preserves the sign
                // of zero, infinity and NaN. The result type of unary minus
                // equals the operand type, so fall back to the operand's type
                // when the unary expression itself has no recorded binding
                // (e.g. inside expression-body function bodies).
                let negationType = boundType
                    ?? sema.bindings.exprTypes[operandExpr]
                    ?? arena.exprType(operandID)
                if let negationType,
                   case let .primitive(primitiveKind, _) = sema.types.kind(of: negationType),
                   primitiveKind == .double || primitiveKind == .float {
                    let negativeOne = arena.appendTemporary(type: negationType)
                    let literalValue: KIRExprKind = primitiveKind == .double ? .doubleLiteral(-1.0) : .floatLiteral(-1.0)
                    instructions.append(.constValue(result: negativeOne, value: literalValue))
                    let result = arena.appendTemporary(type: negationType)
                    instructions.append(.binary(op: .multiply, lhs: operandID, rhs: negativeOne, result: result))
                    return result
                }
                let zero = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: zero, value: .intLiteral(0)))
                let result = arena.appendTemporary(type: boundType ?? intType)
                instructions.append(.binary(op: .subtract, lhs: zero, rhs: operandID, result: result))
                return result
            case .not:
                let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
                instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
                let result = arena.appendTemporary(type: boundType ?? boolType)
                instructions.append(.binary(op: .equal, lhs: operandID, rhs: falseValue, result: result))
                return result
            }

        case let .isCheck(exprToCheck, typeRefID, negated, _):
            let operandID = lowerExpr(
                exprToCheck,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let typeToken: KIRExprID = if let targetType = sema.bindings.isCheckTargetType(for: exprID) {
                lowerTypeCheckTokenExpr(
                    targetType: targetType,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
            } else {
                lowerIsCheckTypeTokenExpr(
                    typeRefID: typeRefID,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
            }
            let isResult = arena.appendTemporary(type: boundType ?? boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [operandID, typeToken],
                result: isResult,
                canThrow: false,
                thrownResult: nil
            ))
            guard negated else {
                return isResult
            }
            let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
            instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
            let negatedResult = arena.appendTemporary(type: boundType ?? boolType)
            instructions.append(.binary(op: .equal, lhs: isResult, rhs: falseValue, result: negatedResult))
            return negatedResult

        case let .asCast(exprToCast, typeRefID, isSafe, _):
            let operandID = lowerExpr(
                exprToCast,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let targetType = sema.bindings.castTargetType(for: exprID),
               isRedundantGenericArrayCast(
                   from: sema.bindings.exprTypes[exprToCast],
                   to: targetType,
                   sema: sema,
                   interner: interner
               )
            {
                return operandID
            }
            if let targetType = sema.bindings.castTargetType(for: exprID),
               isRedundantComparableCast(
                   from: sema.bindings.exprTypes[exprToCast],
                   to: targetType,
                   sema: sema
               )
            {
                return operandID
            }
            // Unchecked erasure cast: `as`/`as?` to a non-reified type parameter
            // has no runtime type information to check against — Sema allows
            // this (with an "unchecked cast" warning) but only rejects `is T`
            // for non-reified T (KSWIFTK-SEMA-0084), matching Kotlin/JVM, where
            // `as T` under erasure is a pure "trust me" annotation for the type
            // checker with no runtime checkcast at all. Passing this through to
            // `kk_op_cast` would encode an `unknownBase` token, which
            // `kk_op_is` always reports as a mismatch — turning every such cast
            // into an unconditional ClassCastException. Pass the value through
            // unchanged instead.
            if let targetType = sema.bindings.castTargetType(for: exprID),
               case let .typeParam(typeParam) = sema.types.kind(of: targetType),
               let typeParamSymbol = sema.symbols.symbol(typeParam.symbol),
               !typeParamSymbol.flags.contains(.reifiedTypeParameter)
            {
                let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
                instructions.append(.copy(from: operandID, to: result))
                return result
            }
            let typeToken: KIRExprID = if let targetType = sema.bindings.castTargetType(for: exprID) {
                lowerTypeCheckTokenExpr(
                    targetType: targetType,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
            } else {
                lowerIsCheckTypeTokenExpr(
                    typeRefID: typeRefID,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
            }
            let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(isSafe ? "kk_op_safe_cast" : "kk_op_cast"),
                arguments: [operandID, typeToken],
                result: result,
                canThrow: !isSafe,
                thrownResult: nil
            ))
            return result

        case let .nullAssert(innerExpr, _):
            let operandID = lowerExpr(
                innerExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
            instructions.append(.nullAssert(operand: operandID, result: result))
            return result

        case let .safeMemberCall(receiverExpr, calleeName, _, args, _):
            return driver.callLowerer.lowerSafeMemberCallExpr(
                exprID,
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .compoundAssign(op, _, valueExpr, _):
            let rhsID = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let kirOp: KIRBinaryOp = switch op {
            case .plusAssign: .add
            case .minusAssign: .subtract
            case .timesAssign: .multiply
            case .divAssign: .divide
            case .modAssign: .modulo
            }
            let stringType = sema.types.stringType
            let nullableStringType = sema.types.makeNullable(sema.types.stringType)

            func appendBuiltinCompoundResult(
                lhs: KIRExprID,
                lhsType: TypeID,
                rhs: KIRExprID,
                rhsType: TypeID?
            ) -> KIRExprID {
                let isStringCompound = op == .plusAssign
                    && (
                        lhsType == stringType
                            || lhsType == nullableStringType
                            || rhsType == stringType
                            || rhsType == nullableStringType
                    )
                if !isStringCompound {
                    let resultType = arena.exprType(lhs) ?? lhsType
                    let resultID = arena.appendTemporary(type: resultType)
                    instructions.append(.binary(op: kirOp, lhs: lhs, rhs: rhs, result: resultID))
                    return resultID
                }

                let effectiveRHS: KIRExprID
                if rhsType == stringType || rhsType == nullableStringType {
                    effectiveRHS = rhs
                } else {
                    effectiveRHS = driver.callLowerer.emitAnyToStringWithNullGuard(
                        valueID: rhs,
                        valueType: rhsType ?? sema.types.anyType,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                }

                let effectiveLHS: KIRExprID
                if lhsType == stringType || lhsType == nullableStringType {
                    effectiveLHS = lhs
                } else {
                    effectiveLHS = driver.callLowerer.emitAnyToStringWithNullGuard(
                        valueID: lhs,
                        valueType: lhsType,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                }

                let resultID = arena.appendTemporary(type: stringType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_concat_flat"),
                    arguments: [effectiveLHS, effectiveRHS],
                    result: resultID,
                    canThrow: false,
                    thrownResult: nil
                ))
                return resultID
            }

            func appendOperatorCompoundResult(
                lhs: KIRExprID,
                rhs: KIRExprID,
                resultType: TypeID
            ) -> KIRExprID? {
                guard let callBinding = sema.bindings.callBindings[exprID],
                      let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
                      signature.receiverType != nil
                else {
                    return nil
                }

                let normalizedResult = driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: [rhs],
                    callBinding: callBinding,
                    chosenCallee: callBinding.chosenCallee,
                    spreadFlags: [false],
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                var finalArguments = normalizedResult.arguments
                finalArguments.insert(lhs, at: 0)
                let callResult = arena.appendTemporary(type: resultType)
                let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                                                           !externalLinkName.isEmpty {
                    interner.intern(externalLinkName)
                } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                    symbol.name
                } else {
                    interner.intern(op.kotlinFunctionName)
                }
                instructions.append(.call(
                    symbol: callBinding.chosenCallee,
                    callee: loweredCalleeName,
                    arguments: finalArguments,
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                return callResult
            }
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                // Top-level or object-member property compound assignment
                // needs a copy to global storage. Top-level properties have
                // nil or .package parent; object members have .object parent.
                // `field` inside a custom getter/setter resolves to a
                // `.backingField`-kind symbol (see typeCheckGetter/typeCheckSetter
                // in DeclTypeChecker+PropertyHelpers.swift), so it must be
                // accepted here too — otherwise `field += x` on a top-level or
                // object property silently falls through to the generic local-
                // variable branch below, which only updates the compiler's
                // lowering-time local-value cache and never emits any
                // instruction that writes the backing field's global storage.
                if let delegateStorageID = driver.ctx.localDelegateStorage(for: symbol),
                   let getValueSymbol = sema.symbols.delegateGetValueSymbol(for: symbol),
                   let setValueSymbol = sema.symbols.delegateSetValueSymbol(for: symbol)
                {
                    // Local delegated `var` compound assignment (BUG-147):
                    // read-modify-write through the delegate's getValue/setValue.
                    // Without this the generic local branch below would overwrite
                    // the register that holds the delegate handle itself with the
                    // arithmetic result.
                    let propertyType = driver.ctx.localDeclaredType(for: symbol) ?? sema.types.anyType
                    let getterArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
                        localSymbol: symbol, sema: sema, arena: arena, interner: interner,
                        instructions: &instructions
                    )
                    let loadedValue = arena.appendTemporary(type: propertyType)
                    instructions.append(driver.memberLowerer.dispatchedDelegateMemberCall(
                        symbol: getValueSymbol,
                        callee: interner.intern("getValue"),
                        receiver: delegateStorageID,
                        extraArguments: getterArgs,
                        result: loadedValue,
                        sema: sema,
                        interner: interner
                    ))
                    let computedValue = appendBuiltinCompoundResult(
                        lhs: loadedValue,
                        lhsType: propertyType,
                        rhs: rhsID,
                        rhsType: arena.exprType(rhsID)
                    )
                    let setterArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
                        localSymbol: symbol, sema: sema, arena: arena, interner: interner,
                        instructions: &instructions
                    )
                    let setResultExprID = arena.appendTemporary(type: sema.types.unitType)
                    instructions.append(driver.memberLowerer.dispatchedDelegateMemberCall(
                        symbol: setValueSymbol,
                        callee: interner.intern("setValue"),
                        receiver: delegateStorageID,
                        extraArguments: setterArgs + [computedValue],
                        result: setResultExprID,
                        sema: sema,
                        interner: interner
                    ))
                    // Reads always dispatch a fresh getValue (see
                    // readLocalDelegateValue) rather than caching, so a
                    // vetoable-style delegate rejecting this write is
                    // observed correctly with no extra bookkeeping here.
                } else if let symInfo = sema.symbols.symbol(symbol),
                          symInfo.kind == .property || symInfo.kind == .field || symInfo.kind == .backingField, {
                              let p = sema.symbols.parentSymbol(for: symbol)
                              let pk = p.flatMap { sema.symbols.symbol($0) }?.kind
                              return pk == nil || pk == .package || pk == .object
                          }() {
                    let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
                    instructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
                    let loadedValue = arena.appendExpr(.symbolRef(symbol), type: propType)
                    instructions.append(.loadGlobal(result: loadedValue, symbol: symbol))
                    if let callBinding = sema.bindings.callBindings[exprID],
                       let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                        if signature.returnType == sema.types.unitType {
                            _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                        } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                            instructions.append(.copy(from: resultID, to: globalRef))
                        }
                    } else {
                        let resultID = appendBuiltinCompoundResult(
                            lhs: loadedValue,
                            lhsType: propType,
                            rhs: rhsID,
                            rhsType: arena.exprType(rhsID)
                        )
                        instructions.append(.copy(from: resultID, to: globalRef))
                    }
                } else if let symInfo = sema.symbols.symbol(symbol),
                          symInfo.kind == .property || symInfo.kind == .field,
                          let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                          let ownerInfo = sema.symbols.symbol(ownerSymbol),
                          ownerInfo.kind == .class || ownerInfo.kind == .interface,
                          let receiverID = driver.ctx.activeImplicitReceiverExprID(),
                          let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                              sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                          ]
                {
                    // Class/interface instance property compound assignment: the
                    // property lives inside the heap-allocated instance, not in a
                    // module-global slot, so the read-modify-write must go through
                    // kk_array_get_inbounds / kk_array_set at the computed field
                    // offset — mirroring tryLowerStoredMemberPropertyRead (reads)
                    // and lowerMemberAssignExpr (plain `=` writes). Falling through
                    // to the local-variable branch below would silently discard the
                    // computed result instead of storing it back into the instance.
                    let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    let loadedValue = arena.appendTemporary(type: propType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [receiverID, offsetExpr],
                        result: loadedValue,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    func storeFieldResult(_ value: KIRExprID) {
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_array_set"),
                            arguments: [receiverID, offsetExpr, value],
                            result: nil,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }
                    if let callBinding = sema.bindings.callBindings[exprID],
                       let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                        if signature.returnType == sema.types.unitType {
                            _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                        } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                            storeFieldResult(resultID)
                        }
                    } else {
                        let resultID = appendBuiltinCompoundResult(
                            lhs: loadedValue,
                            lhsType: propType,
                            rhs: rhsID,
                            rhsType: arena.exprType(rhsID)
                        )
                        storeFieldResult(resultID)
                    }
                } else if driver.ctx.isMutableCaptureBoxed(symbol),
                          let loadedValue = loadMutableCaptureCellValue(
                              symbol: symbol,
                              resultType: {
                                  driver.ctx.localDeclaredType(for: symbol)
                                      ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                              }(),
                              sema: sema,
                              arena: arena,
                              interner: interner,
                              instructions: &instructions
                          )
                {
                    let symbolType = driver.ctx.localDeclaredType(for: symbol)
                        ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                    if let callBinding = sema.bindings.callBindings[exprID],
                       let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                        if signature.returnType == sema.types.unitType {
                            _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                        } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                            _ = storeMutableCaptureCellValue(
                                resultID,
                                for: symbol,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                instructions: &instructions
                            )
                        }
                    } else {
                        let resultID = appendBuiltinCompoundResult(
                            lhs: loadedValue,
                            lhsType: symbolType,
                            rhs: rhsID,
                            rhsType: arena.exprType(rhsID)
                        )
                        _ = storeMutableCaptureCellValue(
                            resultID,
                            for: symbol,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                    }
                } else if let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
                          let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                          let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                              sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                          ]
                {
                    // Instance field accessed via implicit `this` receiver: must load/store
                    // through the object's field storage, mirroring the `.localAssign` write
                    // path and the `nameRef` read path. Falling through to the plain-local
                    // branch below would only update the compiler's local-value cache
                    // (used for real locals/params), never the field itself, so the write
                    // was silently dropped.
                    let fieldType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    let rawLoadedValue = arena.appendTemporary(type: fieldType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [receiverExprID, offsetExpr],
                        result: rawLoadedValue,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    let loadedValue = wrapLateinitReadIfNeeded(
                        rawLoadedValue,
                        symbol: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    func storeField(_ value: KIRExprID) {
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_array_set"),
                            arguments: [receiverExprID, offsetExpr, value],
                            result: nil,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }
                    if let callBinding = sema.bindings.callBindings[exprID],
                       let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                        if signature.returnType == sema.types.unitType {
                            _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                        } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                            storeField(resultID)
                        }
                    } else {
                        let resultID = appendBuiltinCompoundResult(
                            lhs: loadedValue,
                            lhsType: fieldType,
                            rhs: rhsID,
                            rhsType: arena.exprType(rhsID)
                        )
                        storeField(resultID)
                    }
                } else {
                    if let storageID = driver.ctx.localValue(for: symbol) {
                        // Compute lhs op rhs and update storage in place so the value
                        // persists across loop iterations.
                        let symbolType = driver.ctx.localDeclaredType(for: symbol)
                            ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                        if let callBinding = sema.bindings.callBindings[exprID],
                           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                            if signature.returnType == sema.types.unitType {
                                _ = appendOperatorCompoundResult(lhs: storageID, rhs: rhsID, resultType: signature.returnType)
                            } else if let resultID = appendOperatorCompoundResult(lhs: storageID, rhs: rhsID, resultType: signature.returnType) {
                                instructions.append(.copy(from: resultID, to: storageID))
                            }
                        } else {
                            let resultID = appendBuiltinCompoundResult(
                                lhs: storageID,
                                lhsType: symbolType,
                                rhs: rhsID,
                                rhsType: arena.exprType(rhsID)
                            )
                            instructions.append(.copy(from: resultID, to: storageID))
                        }
                    } else {
                        // No existing local value — create a symbol reference as lhs
                        // so compound assignment still computes lhs op rhs.
                        let symbolType = driver.ctx.localDeclaredType(for: symbol)
                            ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                        let lhsID = arena.appendExpr(.symbolRef(symbol), type: symbolType)
                        instructions.append(.constValue(result: lhsID, value: .symbolRef(symbol)))
                        if let callBinding = sema.bindings.callBindings[exprID],
                           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                            if signature.returnType == sema.types.unitType {
                                _ = appendOperatorCompoundResult(lhs: lhsID, rhs: rhsID, resultType: signature.returnType)
                            } else if let resultID = appendOperatorCompoundResult(lhs: lhsID, rhs: rhsID, resultType: signature.returnType) {
                                driver.ctx.setLocalValue(resultID, for: symbol)
                            }
                        } else {
                            let resultID = appendBuiltinCompoundResult(
                                lhs: lhsID,
                                lhsType: symbolType,
                                rhs: rhsID,
                                rhsType: arena.exprType(rhsID)
                            )
                            driver.ctx.setLocalValue(resultID, for: symbol)
                        }
                    }
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .indexedCompoundAssign(_, receiverExpr, indices, valueExpr, _):
            return driver.callLowerer.lowerIndexedCompoundAssignExpr(
                exprID,
                receiverExpr: receiverExpr,
                indices: indices,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .memberCompoundAssign(op, receiverExpr, calleeName, valueExpr, _):
            return driver.callLowerer.lowerMemberCompoundAssignExpr(
                exprID,
                op: op,
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .throwExpr(valueExpr, _):
            let thrownValue = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            instructions.append(.rethrow(value: thrownValue))
            let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .lambdaLiteral(params, bodyExpr, _, _):
            let allowsNonLocalReturn = driver.ctx.pendingLambdaNonLocalReturnAllowance
            driver.ctx.pendingLambdaNonLocalReturnAllowance = false
            return driver.lambdaLowerer.lowerLambdaLiteralExpr(
                exprID,
                params: params,
                bodyExpr: bodyExpr,
                allowsNonLocalReturn: allowsNonLocalReturn,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .callableRef(receiverExpr, memberName, _):
            // T::class  — emit a KClass metadata object via kk_kclass_create.
            // When used as `T::class.simpleName`, the memberCall lowerer
            // intercepts and emits a direct kk_type_token_simple_name call
            // instead.  For standalone `T::class` (assigned to a variable,
            // passed as an argument, etc.) the KClass box is needed.
            if memberName == KnownCompilerNames(interner: interner).className,
               let classRefTargetType = sema.bindings.classRefTargetType(for: exprID)
            {
                let intType = sema.types.make(.primitive(.int, .nonNull))

                // 1. Emit the type token.
                let tokenExpr: KIRExprID
                if case let .typeParam(typeParam) = sema.types.kind(of: classRefTargetType) {
                    let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
                    tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
                    instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
                } else {
                    let encoded = RuntimeTypeCheckToken.encode(type: classRefTargetType, sema: sema, interner: interner)
                    tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
                }

                // 2. Emit the name-hint.
                // kk_kclass_create ABI expects (Int, Int) — both parameters are
                // intptr_t.  The name hint is either a runtime string pointer
                // (passed as an int-typed string literal that codegen materialises
                // into a pointer bit-pattern) or 0 when no name is available.
                // We always use intType here to stay consistent with the ABI.
                let nameHintExpr: KIRExprID
                if let name = RuntimeTypeCheckToken.simpleName(of: classRefTargetType, sema: sema, interner: interner) {
                    let internedName = interner.intern(name)
                    nameHintExpr = arena.appendExpr(.stringLiteral(internedName), type: intType)
                    instructions.append(.constValue(result: nameHintExpr, value: .stringLiteral(internedName)))
                } else {
                    nameHintExpr = arena.appendExpr(.intLiteral(0), type: intType)
                    instructions.append(.constValue(result: nameHintExpr, value: .intLiteral(0)))
                }

                // 3. Call kk_kclass_create to produce a KClass metadata object.
                // Prefer the sema-bound KClass<T> type and fall back to
                // KClass<classRefTargetType> so the result always carries the
                // precise generic parameter instead of degrading to Any.
                let kClassFallback = sema.types.makeKClassType(argument: classRefTargetType)
                let result = arena.appendTemporary(type: boundType ?? kClassFallback
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_kclass_create"),
                    arguments: [tokenExpr, nameHintExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))

                // STDLIB-REFLECT-067: A standalone `T::class` box may later be
                // queried for metadata-backed members (e.g. `val k = Foo::class;
                // k.isData`). The member-call lowerer only registers metadata when
                // the receiver is a literal class-ref, so register it here too,
                // reusing the same `tokenExpr` so the box and its metadata share a
                // type token. No-op for reified type parameters / built-ins.
                driver.callLowerer.emitClassLiteralMetadataRegistration(
                    classRefTargetType: classRefTargetType,
                    typeTokenExpr: tokenExpr,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                return result
            }
            return driver.lambdaLowerer.lowerCallableRefExpr(
                exprID,
                receiverExpr: receiverExpr,
                memberName: memberName,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .objectLiteral(superTypes, declID, _):
            return driver.objectLiteralLowerer.lowerObjectLiteralExpr(
                exprID,
                superTypes: superTypes,
                declID: declID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .whenExpr(subject, branches, elseExpr, _):
            return driver.controlFlowLowerer.lowerWhenExpr(
                exprID,
                subject: subject,
                branches: branches,
                elseExpr: elseExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .blockExpr(statements, trailingExpr, _):
            for stmt in statements {
                let loweredStmt = lowerExpr(
                    stmt,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                // If the statement is a terminator (return/throw), stop lowering
                if driver.controlFlowLowerer.isTerminatedExpr(loweredStmt, arena: arena, sema: sema) {
                    return loweredStmt
                }
            }
            if let trailingExpr {
                return lowerExpr(
                    trailingExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .superRef:
            if let receiverExprID = driver.ctx.activeImplicitReceiverExprID() {
                return receiverExprID
            }
            let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .thisRef:
            if let receiverExprID = driver.ctx.activeImplicitReceiverExprID() {
                return receiverExprID
            }
            let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .inExpr(lhsExpr, rhsExpr, _):
            let lhsID = lowerExpr(
                lhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let rhsID = lowerExpr(
                rhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let result = arena.appendTemporary(type: boundType ?? boolType)
            let rhsType = sema.bindings.exprTypes[rhsExpr]
            if let rhsType = rhsType,
               sema.types.makeNonNullable(rhsType) == sema.types.uintType {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_uint_range_contains"),
                    arguments: [rhsID, lhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if let rhsType = rhsType,
                      sema.bindings.isULongRangeExpr(rhsExpr) || sema.types.makeNonNullable(rhsType) == sema.types.ulongType {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_ulong_range_contains"),
                    arguments: [rhsID, lhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                appendContainsCall(
                    exprID: exprID,
                    elementID: lhsID,
                    containerID: rhsID,
                    resultID: result,
                    sema: sema,
                    interner: interner,
                    instructions: &instructions
                )
            }
            return result

        case let .notInExpr(lhsExpr, rhsExpr, _):
            let lhsID = lowerExpr(
                lhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let rhsID = lowerExpr(
                rhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let notInRhsType = sema.bindings.exprTypes[rhsExpr]
            let notInContainsCallee: String
            if let notInRhsType = notInRhsType,
               sema.types.makeNonNullable(notInRhsType) == sema.types.uintType {
                notInContainsCallee = "kk_uint_range_contains"
            } else if let notInRhsType = notInRhsType,
                      sema.bindings.isULongRangeExpr(rhsExpr) || sema.types.makeNonNullable(notInRhsType) == sema.types.ulongType {
                notInContainsCallee = "kk_ulong_range_contains"
            } else {
                notInContainsCallee = "kk_op_contains"
            }
            let containsResult = arena.appendTemporary(type: boolType)
            if notInContainsCallee == "kk_uint_range_contains" || notInContainsCallee == "kk_ulong_range_contains" {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(notInContainsCallee),
                    arguments: [rhsID, lhsID],
                    result: containsResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                appendContainsCall(
                    exprID: exprID,
                    elementID: lhsID,
                    containerID: rhsID,
                    resultID: containsResult,
                    sema: sema,
                    interner: interner,
                    instructions: &instructions
                )
            }
            let result = arena.appendTemporary(type: boundType ?? boolType)
            let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
            instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
            instructions.append(.binary(op: .equal, lhs: containsResult, rhs: falseValue, result: result))
            return result

        case let .destructuringDecl(names, _, initializer, _):
            // Lower: val (a, b) = expr  →  tmp = expr; a = tmp.component1(); b = tmp.component2()
            let rhsID = lowerExpr(
                initializer, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let rhsType = sema.bindings.exprTypes[initializer] ?? sema.types.anyType
            let nonNullRhsType = sema.types.makeNonNullable(rhsType)
            for (index, name) in names.enumerated() {
                guard let name else {
                    // Underscore — skip
                    continue
                }
                let componentIndex = index + 1
                let componentName = interner.intern("component\(componentIndex)")

                // Resolve componentN to externalLinkName when available (Pair, Triple, List, etc.)
                let memberCandidates = TypeCheckHelpers().collectMemberFunctionCandidates(
                    named: componentName,
                    receiverType: nonNullRhsType,
                    sema: sema,
                    interner: interner
                )
                // Sema's chosen callee wins: `componentN` is an overloaded name across
                // Pair/Triple, user extensions and bundled stdlib extensions, so the
                // symbol has to travel to codegen instead of being re-resolved by name.
                let chosenCallee = sema.bindings.destructuringComponentCallee(
                    for: exprID,
                    index: index
                ) ?? memberCandidates.first
                let calleeName: InternedString = if let chosenCallee,
                                                    let linkName = sema.symbols.externalLinkName(for: chosenCallee),
                                                    !linkName.isEmpty
                {
                    interner.intern(linkName)
                } else {
                    componentName
                }

                // Look up the symbol defined by Sema for this variable first,
                // so we can use its per-component type (not the expression-level Unit type)
                let candidates = sema.symbols.lookupAll(fqName: [
                    interner.intern("__destructuring_\(exprID.rawValue)"),
                    name,
                ])
                let componentType = candidates.first.flatMap { sema.symbols.propertyType(for: $0) } ?? sema.types.anyType
                let componentResult = arena.appendTemporary(type: componentType)
                let calleeSymbol: SymbolID? = chosenCallee.flatMap { callee in
                    sema.symbols.isSourceBackedSymbol(callee) ? callee : nil
                }
                instructions.append(.call(
                    symbol: calleeSymbol,
                    callee: calleeName,
                    arguments: [rhsID],
                    result: componentResult,
                    canThrow: false,
                    thrownResult: nil
                ))

                // Bind the destructured variable to the component result
                if let symbol = candidates.first {
                    driver.ctx.setLocalValue(componentResult, for: symbol)
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .forDestructuringExpr(names, iterableExpr, bodyExpr, _):
            // Lower as a regular for-loop, but inside the body, destructure the element
            // Delegate to control flow lowerer for loop structure
            return driver.controlFlowLowerer.lowerForDestructuringExpr(
                exprID,
                names: names,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
    }

    /// Emits a contains call instruction, dispatching to a user-defined operator fun contains
    /// if sema recorded a CallBinding, or falling back to the kk_op_contains runtime stub.
    private func appendContainsCall(
        exprID: ExprID,
        elementID: KIRExprID,
        containerID: KIRExprID,
        resultID: KIRExprID,
        sema: SemaModule,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        // Dispatch to a source-backed operator fun contains when available
        // (including range/progression members, STDLIB-OP-032), otherwise use the
        // generic kk_op_contains runtime stub.
        if
           let callBinding = sema.bindings.callBindings[exprID],
           callBinding.chosenCallee != .invalid,
           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
           signature.receiverType != nil
        {
            let calleeName: InternedString = if let linkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                                                !linkName.isEmpty
            {
                interner.intern(linkName)
            } else if let sym = sema.symbols.symbol(callBinding.chosenCallee) {
                sym.name
            } else {
                interner.intern("contains")
            }
            instructions.append(.call(
                symbol: callBinding.chosenCallee,
                callee: calleeName,
                arguments: [containerID, elementID],
                result: resultID,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_contains"),
                arguments: [containerID, elementID],
                result: resultID,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }

    /// Resolves the *effective* delegate for a local custom-delegate declaration
    /// (BUG-146). When the delegate factory exposes a `provideDelegate` operator,
    /// the actual delegate is its return value — the same rule member/top-level
    /// delegated properties follow in KIRLoweringDriver+ProvideDelegate.swift.
    /// Emits `rawDelegate.provideDelegate(null, KProperty("x"))` and returns the
    /// result. When no `provideDelegate` is present, returns `rawDelegateID`
    /// unchanged (the delegate factory instance is itself the delegate).
    func lowerLocalProvideDelegateIfNeeded(
        symbol: SymbolID,
        rawDelegateID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard sema.symbols.hasProvideDelegate(for: symbol),
              let provideDelegateSymbol = sema.symbols.delegateProvideDelegateSymbol(for: symbol)
        else {
            return rawDelegateID
        }
        let provideArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
            localSymbol: symbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let providedExprID = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: provideDelegateSymbol,
            callee: interner.intern("provideDelegate"),
            arguments: [rawDelegateID] + provideArgs,
            result: providedExprID,
            canThrow: false,
            thrownResult: nil
        ))
        return providedExprID
    }

    /// Reads a delegated local's current value by calling its resolved
    /// `getValue` operator fresh, rather than reusing whatever was computed
    /// at the declaration (which doesn't exist for delegates -- see the
    /// `.localDecl` case above). Real Kotlin delegated properties call
    /// getValue at every read site, and for `var` delegates observing writes
    /// (`Delegates.observable`, or a custom delegate a write may veto)
    /// depends on that: reusing a cached read would silently miss any
    /// change the delegate itself made to the stored value.
    /// Returns `nil` when `symbol` is not a delegated local.
    func readLocalDelegateValue(
        symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let delegateStorageID = driver.ctx.localDelegateStorage(for: symbol),
              let getValueSymbol = sema.symbols.delegateGetValueSymbol(for: symbol)
        else {
            return nil
        }
        let getterArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
            localSymbol: symbol, sema: sema, arena: arena, interner: interner,
            instructions: &instructions
        )
        let propertyType = driver.ctx.localDeclaredType(for: symbol)
            ?? sema.symbols.propertyType(for: symbol)
            ?? sema.types.anyType
        let resultExprID = arena.appendTemporary(type: propertyType)
        instructions.append(driver.memberLowerer.dispatchedDelegateMemberCall(
            symbol: getValueSymbol,
            callee: interner.intern("getValue"),
            receiver: delegateStorageID,
            extraArguments: getterArgs,
            result: resultExprID,
            sema: sema,
            interner: interner
        ))
        return resultExprID
    }

    /// Whether the expression is a plain read of a variable (`b` in `val a = b`).
    /// Such initializers must be snapshotted into their own register instead of
    /// aliasing the source variable's storage.
    func isBareVariableRead(_ exprID: ExprID, ast: ASTModule) -> Bool {
        if case .nameRef = ast.arena.expr(exprID) {
            return true
        }
        return false
    }

}
